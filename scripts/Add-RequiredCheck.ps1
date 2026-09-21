#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Adds one or more required status checks to an existing branch ruleset, in place.

.DESCRIPTION
    Use it when a workflow gained a job that main must now require (for example "Protected Files
    Guard", which moved out of pr.yaml into protected-files.yaml) and the repository's ruleset was
    set up before that job existed. Unlike Fix-BranchRuleset.ps1, nothing else about the ruleset
    changes: bypass actors, linear history, the other required checks and any per-repository
    tweaks are read back from GitHub and written back untouched. Only the required_status_checks
    rule's list gains the new contexts; a context already present is left alone.

    Several repositories can be patched in one run by passing them all to -Repository. Each
    repository is fetched, planned and (after one confirmation, or -Force) updated in turn; a
    failure on one repository is reported and the run continues with the next.

.PARAMETER Check
    The status check context(s) to require, exactly as the job name appears on a pull request
    (e.g. "Protected Files Guard"). Defaults to "Protected Files Guard".

.PARAMETER Repository
    One or more repositories in owner/repo format. If not provided, uses the current repository.

.PARAMETER RulesetName
    The ruleset to patch. Defaults to "Protect main branch" (the name Setup-BranchRuleset.ps1 uses).

.PARAMETER Force
    Skip the confirmation prompt and proceed automatically. Alias: -y

.EXAMPLE
    .\Add-RequiredCheck.ps1
    Requires "Protected Files Guard" on the current repository's "Protect main branch" ruleset.

.EXAMPLE
    .\Add-RequiredCheck.ps1 -Repository Chris-Wolfgang/ETL-Csv, Chris-Wolfgang/ETL-Json -Force
    Patches both repositories without prompting.

.EXAMPLE
    .\Add-RequiredCheck.ps1 -Check "Stryker Gate (mutation score)" -Repository Chris-Wolfgang/my-repo
    Requires a different check.

.NOTES
    Requires: GitHub CLI (gh) authenticated with admin permissions on each repository.
    A ruleset with no required_status_checks rule is skipped with a warning: adding that rule from
    scratch is Setup-BranchRuleset.ps1's job, because it also decides strictness and the source.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$Check = @("Protected Files Guard"),

    [Parameter()]
    [string[]]$Repository = @("{{GITHUB_OWNER}}/{{REPO_NAME}}"),

    [Parameter()]
    [string]$RulesetName = "Protect main branch",

    [Parameter()]
    [Alias("y")]
    [switch]$Force
)

$ErrorActionPreference = "Stop"

# Check if gh CLI is installed
try {
    $null = gh --version
} catch {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH."
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Check if authenticated
try {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not authenticated with GitHub CLI."
        Write-Host "Run: gh auth login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Error "Failed to check GitHub CLI authentication status."
    exit 1
}

$headers = @(
    "-H", "Accept: application/vnd.github+json",
    "-H", "X-GitHub-Api-Version: 2022-11-28"
)

# Runs a gh api call with stderr captured separately so progress/warnings cannot poison the JSON
# on stdout. Returns the parsed body; throws with gh's stderr on a non-zero exit.
function Invoke-GhApi {
    param(
        [Parameter(Mandatory)] [string]$Method,
        [Parameter(Mandatory)] [string]$Path,
        [string]$Body
    )

    $errFile = [System.IO.Path]::GetTempFileName()
    try {
        if ($Body) {
            $bodyFile = [System.IO.Path]::GetTempFileName()
            try {
                # UTF-8 without BOM: gh sends the file bytes verbatim and GitHub rejects a BOM.
                [System.IO.File]::WriteAllText($bodyFile, $Body, [System.Text.UTF8Encoding]::new($false))
                $json = gh api -X $Method @headers $Path --input $bodyFile 2> $errFile
            } finally {
                Remove-Item -LiteralPath $bodyFile -Force -ErrorAction SilentlyContinue
            }
        } else {
            $json = gh api -X $Method @headers $Path 2> $errFile
        }
        $exit = $LASTEXITCODE
        $errText = Get-Content -LiteralPath $errFile -Raw -ErrorAction SilentlyContinue
    } finally {
        Remove-Item -LiteralPath $errFile -Force -ErrorAction SilentlyContinue
    }

    if ($exit -ne 0) {
        throw "gh api $Method $Path failed (exit $exit): $errText"
    }
    return ($json | ConvertFrom-Json)
}

# Normalize each repository: strip a leading "@" and trailing ".git" that leak in from SSH remotes.
$repositories = @()
foreach ($repo in $Repository) {
    $name = $repo.Trim().TrimStart('@')
    if ($name.EndsWith('.git')) { $name = $name.Substring(0, $name.Length - 4) }

    if ($name -eq "{{GITHUB_OWNER}}/{{REPO_NAME}}" -or -not $name) {
        Write-Host "Detecting current repository..." -ForegroundColor Cyan
        try {
            $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
            $name = $repoInfo.nameWithOwner
        } catch {
            Write-Error "Could not detect repository. Run from within a git repository or specify -Repository."
            exit 1
        }
    }
    $repositories += $name
}

$checksWanted = @($Check | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($checksWanted.Count -eq 0) {
    Write-Error "No check names given."
    exit 1
}

Write-Host "Required check(s) to add: $($checksWanted -join ', ')" -ForegroundColor Cyan
Write-Host "Ruleset: '$RulesetName'" -ForegroundColor Cyan
Write-Host ""

# ---------------------------------------------------------------------------
# Plan: fetch every repository's ruleset and work out what would change.
# ---------------------------------------------------------------------------
$plan = @()
foreach ($repo in $repositories) {
    Write-Host "[$repo]" -ForegroundColor White
    try {
        $rulesets = @(Invoke-GhApi -Method GET -Path "/repos/$repo/rulesets?per_page=100")
    } catch {
        Write-Host "  ERROR: could not list rulesets - $($_.Exception.Message)" -ForegroundColor Red
        $plan += @{ repo = $repo; action = "error"; reason = $_.Exception.Message }
        continue
    }

    $summary = @($rulesets | Where-Object { $_.name -eq $RulesetName }) | Select-Object -First 1
    if (-not $summary) {
        Write-Host "  SKIP: no ruleset named '$RulesetName' (run Setup-BranchRuleset.ps1 first)" -ForegroundColor Yellow
        $plan += @{ repo = $repo; action = "skip"; reason = "no ruleset named '$RulesetName'" }
        continue
    }

    # The list endpoint returns summaries; the rules live on the single-ruleset endpoint.
    try {
        $ruleset = Invoke-GhApi -Method GET -Path "/repos/$repo/rulesets/$($summary.id)"
    } catch {
        Write-Host "  ERROR: could not read ruleset $($summary.id) - $($_.Exception.Message)" -ForegroundColor Red
        $plan += @{ repo = $repo; action = "error"; reason = $_.Exception.Message }
        continue
    }

    $checksRule = @($ruleset.rules | Where-Object { $_.type -eq "required_status_checks" }) | Select-Object -First 1
    if (-not $checksRule) {
        Write-Host "  SKIP: ruleset [$($ruleset.id)] has no required_status_checks rule (Setup-BranchRuleset.ps1 adds it)" -ForegroundColor Yellow
        $plan += @{ repo = $repo; action = "skip"; reason = "no required_status_checks rule" }
        continue
    }

    $existing = @($checksRule.parameters.required_status_checks | ForEach-Object { $_.context })
    $missing = @($checksWanted | Where-Object { $existing -notcontains $_ })

    if ($missing.Count -eq 0) {
        Write-Host "  OK: already requires $($checksWanted -join ', ') (enforcement: $($ruleset.enforcement))" -ForegroundColor Green
        $plan += @{ repo = $repo; action = "none" }
        continue
    }

    Write-Host "  ADD: $($missing -join ', ') -> ruleset [$($ruleset.id)] (enforcement: $($ruleset.enforcement); $($existing.Count) check(s) already required)" -ForegroundColor Cyan
    $plan += @{ repo = $repo; action = "add"; ruleset = $ruleset; rule = $checksRule; missing = $missing }
}

$toChange = @($plan | Where-Object { $_.action -eq "add" })
if ($toChange.Count -eq 0) {
    Write-Host "`nNothing to change." -ForegroundColor Green
    exit 0
}

if (-not $Force) {
    Write-Host ""
    $answer = Read-Host "Update $($toChange.Count) ruleset(s)? [y/N]"
    if ($answer -notmatch '^(y|yes)$') {
        Write-Host "Aborted." -ForegroundColor Yellow
        exit 0
    }
}

# ---------------------------------------------------------------------------
# Apply: PUT the ruleset back with only the checks list extended.
# ---------------------------------------------------------------------------
$failed = 0
foreach ($item in $toChange) {
    $repo = $item.repo
    $ruleset = $item.ruleset
    $rule = $item.rule

    foreach ($ctx in $item.missing) {
        # Same shape GitHub returns for the existing entries: context only. Do NOT send
        # integration_id = $null - the API schema rejects an explicit null (HTTP 422
        # "Invalid property /rules/N"); omitting it means any app may report the check.
        $rule.parameters.required_status_checks += [pscustomobject]@{ context = $ctx }
    }

    # PUT takes the same fields the GET returned minus the read-only ones. Rule objects are sent
    # back exactly as read (with the extended list), so unrelated rules keep their parameters.
    $body = [ordered]@{
        name          = $ruleset.name
        target        = $ruleset.target
        enforcement   = $ruleset.enforcement
        bypass_actors = @($ruleset.bypass_actors | ForEach-Object {
            [ordered]@{ actor_id = $_.actor_id; actor_type = $_.actor_type; bypass_mode = $_.bypass_mode }
        })
        conditions    = $ruleset.conditions
        rules         = @($ruleset.rules)
    }

    try {
        $updated = Invoke-GhApi -Method PUT -Path "/repos/$repo/rulesets/$($ruleset.id)" -Body ($body | ConvertTo-Json -Depth 20)
        $now = @(($updated.rules | Where-Object { $_.type -eq "required_status_checks" }).parameters.required_status_checks | ForEach-Object { $_.context })
        $stillMissing = @($item.missing | Where-Object { $now -notcontains $_ })
        if ($stillMissing.Count -gt 0) {
            throw "GitHub accepted the update but the read-back is missing: $($stillMissing -join ', ')"
        }
        Write-Host "[$repo] updated: now requires $($now.Count) check(s) incl. $($item.missing -join ', ')" -ForegroundColor Green
    } catch {
        $failed++
        Write-Host "[$repo] FAILED: $($_.Exception.Message)" -ForegroundColor Red
    }
}

$skipped = @($plan | Where-Object { $_.action -in @("skip", "error") })
if ($skipped.Count -gt 0) {
    Write-Host "`nNot updated:" -ForegroundColor Yellow
    foreach ($s in $skipped) { Write-Host "  $($s.repo): $($s.reason)" -ForegroundColor Yellow }
}

if ($failed -gt 0) { exit 1 }
