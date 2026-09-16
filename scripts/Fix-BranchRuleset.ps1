#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Replaces the branch ruleset: creates a fresh "Protect main branch" with Setup-BranchRuleset.ps1
    and deletes the previous one only after that succeeds (other active rulesets are disabled).

.DESCRIPTION
    Use it when the canonical ruleset changed upstream (a required check was renamed or added) and
    the repository's ruleset is stuck on the old definition. The script inspects the repository's
    rulesets, disables any other ruleset that is still active (left in place, disabled, for
    inspection), renames "Protect main branch" aside WITHOUT disabling it, runs
    Setup-BranchRuleset.ps1 to create the fresh ruleset, and only then deletes the old one. If the
    creation fails the old ruleset is renamed back, so main is never left unprotected. It does not
    patch rules in place.

    The script presents a plan of all changes before executing and prompts for confirmation.

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.PARAMETER Force
    Skip the confirmation prompt and proceed automatically. Alias: -y

.PARAMETER RequireLinearHistory
    Forwarded to Setup-BranchRuleset.ps1 when the ruleset is recreated (adds the
    required_linear_history rule and limits merges to squash/rebase).

.EXAMPLE
    .\Fix-BranchRuleset.ps1
    Inspects and fixes rulesets for the current repository with interactive confirmation

.EXAMPLE
    .\Fix-BranchRuleset.ps1 -Force
    Inspects and fixes rulesets without prompting for confirmation

.EXAMPLE
    .\Fix-BranchRuleset.ps1 -Repository "Chris-Wolfgang/my-repo"
    Inspects and fixes rulesets for a specific repository

.NOTES
    Requires: GitHub CLI (gh) authenticated with admin permissions
    Install gh: https://cli.github.com/
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository = "{{GITHUB_OWNER}}/{{REPO_NAME}}",

    [Parameter()]
    [Alias("y")]
    [switch]$Force,

    [Parameter()]
    [switch]$RequireLinearHistory
)

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

# Normalize Repository: strip leading "@" and trailing ".git" that can
# leak in from SSH remotes (e.g. git@github.com:owner/repo.git -> @owner/repo).
# Both prefixes make gh api /repos/... calls fail with 404.
if ($Repository) {
    $Repository = $Repository.TrimStart('@')
    if ($Repository.EndsWith('.git')) { $Repository = $Repository.Substring(0, $Repository.Length - 4) }
}

# Determine repository
if ($Repository -eq "{{GITHUB_OWNER}}/{{REPO_NAME}}" -or -not $Repository) {
    Write-Host "Detecting current repository..." -ForegroundColor Cyan
    try {
        $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $Repository = $repoInfo.nameWithOwner
        Write-Host "Using repository: $Repository" -ForegroundColor Green
    } catch {
        if ($Repository -eq "{{GITHUB_OWNER}}/{{REPO_NAME}}") {
            Write-Error "Could not detect repository. Please run the setup script first to replace placeholders, or specify -Repository parameter."
        } else {
            Write-Error "Could not detect repository. Please run from within a git repository or specify -Repository parameter."
        }
        exit 1
    }
} else {
    Write-Host "Using specified repository: $Repository" -ForegroundColor Green
}

# Fetch all rulesets
Write-Host "`nFetching existing rulesets..." -ForegroundColor Cyan

try {
    # Capture stderr to a temp file so gh's progress/warnings can't poison
    # the JSON stream on stdout (mixing them via 2>&1 can break ConvertFrom-Json
    # even on a successful API call).
    $rulesetsErr = [System.IO.Path]::GetTempFileName()
    try {
        # Don't use --paginate here: it concatenates multiple JSON array
        # payloads when results span pages, which breaks ConvertFrom-Json.
        # Rulesets are typically few per repo; per_page=100 in a single
        # call is enough and produces valid JSON.
        $rulesetsJson = gh api `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2022-11-28" `
            "/repos/$Repository/rulesets?per_page=100" `
            2> $rulesetsErr
    } finally {
        if (Test-Path -LiteralPath $rulesetsErr) {
            $errText = (Get-Content -LiteralPath $rulesetsErr -Raw -ErrorAction SilentlyContinue)
            Remove-Item -LiteralPath $rulesetsErr -Force
        }
    }

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch rulesets (exit code $LASTEXITCODE). gh stderr: $errText"
        exit 1
    }

    $rulesets = $rulesetsJson | ConvertFrom-Json
} catch {
    Write-Error "Failed to fetch rulesets: $($_.Exception.Message)"
    exit 1
}

if (-not $rulesets -or $rulesets.Count -eq 0) {
    Write-Host "No rulesets found for $Repository. Nothing to fix." -ForegroundColor Green
    exit 0
}

# Build the plan
$plan = @()
$targetRulesetName = "Protect main branch"

Write-Host "`nFound $($rulesets.Count) ruleset(s):" -ForegroundColor Cyan
Write-Host ""

foreach ($ruleset in $rulesets) {
    $status = if ($ruleset.enforcement -eq "disabled") { "disabled" } else { $ruleset.enforcement }
    Write-Host "  [$($ruleset.id)] $($ruleset.name) (enforcement: $status)" -ForegroundColor Gray

    $actions = @()

    # If this is the target name, rename it
    if ($ruleset.name -eq $targetRulesetName) {
        $actions += @{
            type        = "replace"
            description = "Replace '$($ruleset.name)' [$($ruleset.id)]: rename aside, create the new ruleset with Setup-BranchRuleset.ps1, then delete the old one (renamed back if creation fails)"
        }
    }

    # If not already disabled, disable it
    if ($ruleset.name -ne $targetRulesetName -and $ruleset.enforcement -ne "disabled") {
        $actions += @{
            type        = "disable"
            description = "Disable '$($ruleset.name)' (currently: $status)"
        }
    }

    if ($actions.Count -gt 0) {
        $plan += @{
            ruleset = $ruleset
            actions = $actions
        }
    }
}

Write-Host ""

# Present the plan
if ($plan.Count -eq 0) {
    Write-Host "No '$targetRulesetName' ruleset to replace and no other active ruleset. Nothing to do." -ForegroundColor Green
    exit 0
}

Write-Host "Planned changes:" -ForegroundColor Yellow
Write-Host ""

$stepNumber = 1
foreach ($item in $plan) {
    foreach ($action in $item.actions) {
        Write-Host "  $stepNumber. $($action.description)" -ForegroundColor White
        $stepNumber++
    }
}

Write-Host ""

# Prompt for confirmation
if ($Force) {
    Write-Host "Auto-confirmed via -Force flag." -ForegroundColor Green
} else {
    $response = Read-Host "Proceed with these changes? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Cancelled. No changes were made." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Execute the plan
$errors = 0
$oldRuleset = $null      # the "Protect main branch" ruleset being replaced, if any
$oldName = $null

function Invoke-RulesetUpdate {
    param([int]$Id, [hashtable]$Payload, [string]$What)
    $jsonPayload = $Payload | ConvertTo-Json -Depth 5
    $tempFile = [System.IO.Path]::GetTempFileName()
    $jsonPayload | Out-File -FilePath $tempFile -Encoding utf8NoBOM
    try {
        Write-Host "  $What..." -ForegroundColor Cyan
        $result = gh api `
            --method PUT `
            -H "Accept: application/vnd.github+json" `
            -H "X-GitHub-Api-Version: 2022-11-28" `
            "/repos/$Repository/rulesets/$Id" `
            --input $tempFile 2>&1
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  Done." -ForegroundColor Green
            return $true
        }
        Write-Host "  Failed: $result" -ForegroundColor Red
        return $false
    } catch {
        Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    } finally {
        if (Test-Path $tempFile) { Remove-Item $tempFile -Force }
    }
}

foreach ($item in $plan) {
    $ruleset = $item.ruleset
    $rulesetId = $ruleset.id

    foreach ($action in $item.actions) {
        switch ($action.type) {
            "replace" {
                # Step 1 of the replacement: move the old ruleset out of the way by
                # NAME only. It stays active, so main keeps its protection until the
                # replacement exists; it is deleted only after Setup-BranchRuleset.ps1
                # succeeds (see below) and renamed back if that fails.
                $oldRuleset = $ruleset
                $oldName = $ruleset.name
                $tempName = "$($ruleset.name) (replacing)"
                if (-not (Invoke-RulesetUpdate -Id $rulesetId -Payload @{ name = $tempName } -What "Renaming '$oldName' [$rulesetId] to '$tempName' while the replacement is created")) {
                    $errors++
                    $oldRuleset = $null
                }
            }
            "disable" {
                if (-not (Invoke-RulesetUpdate -Id $rulesetId -Payload @{ enforcement = "disabled" } -What "Disabling ruleset [$rulesetId] '$($ruleset.name)'")) {
                    $errors++
                }
            }
        }
    }
}

Write-Host ""

if ($errors -gt 0) {
    Write-Host "$errors action(s) failed. Review the errors above. Nothing was deleted." -ForegroundColor Red
    exit 1
}

# Step 2: create the replacement. Only then is the old ruleset removed.
$setupScript = Join-Path $PSScriptRoot "Setup-BranchRuleset.ps1"
if (-not (Test-Path $setupScript)) {
    Write-Host "Setup-BranchRuleset.ps1 not found. Run it manually to create a fresh ruleset." -ForegroundColor Yellow
    if ($oldRuleset) {
        Write-Host "The previous ruleset is still active as '$($oldRuleset.name) (replacing)' [$($oldRuleset.id)]; delete it once the replacement exists." -ForegroundColor Yellow
    }
    Write-Host "View rulesets at: https://github.com/$Repository/settings/rules" -ForegroundColor Cyan
    exit 1
}

Write-Host "Running Setup-BranchRuleset.ps1 to create a fresh ruleset..." -ForegroundColor Cyan
Write-Host ""
& $setupScript -Repository $Repository -RequireLinearHistory:$RequireLinearHistory
$setupExit = $LASTEXITCODE

if ($setupExit -ne 0) {
    Write-Host ""
    Write-Host "Setup-BranchRuleset.ps1 failed (exit $setupExit)." -ForegroundColor Red
    if ($oldRuleset) {
        # Step 3 (failure path): put the old ruleset back under its original name.
        # It was never disabled, so main stayed protected throughout.
        if (Invoke-RulesetUpdate -Id $oldRuleset.id -Payload @{ name = $oldName } -What "Restoring '$oldName' [$($oldRuleset.id)]") {
            Write-Host "The previous ruleset is back in place, unchanged." -ForegroundColor Yellow
        } else {
            Write-Host "Could not restore the name; the previous ruleset is still active as '$oldName (replacing)' [$($oldRuleset.id)]. Rename it by hand at https://github.com/$Repository/settings/rules" -ForegroundColor Red
        }
    }
    exit 1
}

if ($oldRuleset) {
    # Step 3 (success path): the replacement exists and is active; drop the old one.
    Write-Host ""
    Write-Host "  Deleting the replaced ruleset [$($oldRuleset.id)] '$oldName (replacing)'..." -ForegroundColor Cyan
    $result = gh api `
        --method DELETE `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repository/rulesets/$($oldRuleset.id)" 2>&1
    if ($LASTEXITCODE -eq 0) {
        Write-Host "  Done." -ForegroundColor Green
    } else {
        Write-Host "  Failed: $result" -ForegroundColor Red
        Write-Host "  Both rulesets are active; delete '$oldName (replacing)' by hand at https://github.com/$Repository/settings/rules" -ForegroundColor Yellow
        exit 1
    }
}

Write-Host ""
Write-Host "All changes applied successfully." -ForegroundColor Green
