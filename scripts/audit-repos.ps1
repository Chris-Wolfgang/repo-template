#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Audits every repository owned by a GitHub user against docs/repository-baseline.md.
.DESCRIPTION
    For each in-scope repository the script checks all 24 baseline items via the GitHub API
    (settings, rulesets, workflow runs) and a shallow clone (file checks), then writes:

      audit-results.json  - one record per (repo, item): repo, item, name, status, evidence
      audit-summary.md    - repo x item table with pass/fail/na/pending counts

    With -OpenIssues it also opens one issue per failing item in the repository where it fails
    (title "Baseline: <item name>", labels baseline + security|process). Issues are deduplicated
    by title against open issues, so the script can be re-run safely.

    Scope: every non-archived public repository (-Repo / -Exclude narrow it).
    Nothing is changed in any repository except (with -OpenIssues) creating labels and issues.
.PARAMETER Owner
    GitHub user whose repositories are audited.
.PARAMETER Repo
    Optional subset of repository names. Default: every in-scope repository.
.PARAMETER OpenIssues
    Open one issue per failing item. Without it the script is read-only.
.PARAMETER SkipItems
    Item numbers that are audited and reported but never turned into issues (for example, items whose
    policy is still under discussion).
.PARAMETER Exclude
    Repository names to leave out.
.PARAMETER OutputDir
    Where audit-results.json and audit-summary.md are written. Default: current directory.
.PARAMETER WorkDir
    Where shallow clones are made. Default: a fresh temp directory, deleted at the end. A
    directory reused from an earlier run is refreshed (each clone is fetched and reset to the
    default branch) before auditing.
.EXAMPLE
    pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang
.EXAMPLE
    pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang -Repo ETL-Csv,ETL-Json -OpenIssues
.NOTES
    Requires gh authenticated as the owner (rulesets and Dependabot settings need admin read),
    git, and outbound HTTPS to api.securityscorecards.dev (optional; score is evidence only).
#>

[CmdletBinding()]
param
(
    [string]$Owner = 'Chris-Wolfgang',
    [string[]]$Repo,
    [switch]$OpenIssues,
    [int[]]$SkipItems,
    [string[]]$Exclude,
    [string]$OutputDir = '.',
    [string]$WorkDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Baseline item catalogue (numbers match docs/repository-baseline.md)
# ---------------------------------------------------------------------------
$items = @(
    @{ N = 1;  Name = 'Secret scanning enabled';                                  Label = 'security' }
    @{ N = 2;  Name = 'Push protection enabled';                                  Label = 'security' }
    @{ N = 3;  Name = 'Custom secret patterns registered';                        Label = 'security' }
    @{ N = 4;  Name = 'gitleaks pre-commit hook shipped';                         Label = 'security' }
    @{ N = 5;  Name = 'Dependabot security updates on';                           Label = 'security' }
    @{ N = 6;  Name = 'Dependabot version updates for NuGet and Actions';         Label = 'security' }
    @{ N = 7;  Name = 'CodeQL workflow present and passing';                      Label = 'security' }
    @{ N = 8;  Name = 'gitleaks / DevSkim workflow present';                      Label = 'security' }
    @{ N = 9;  Name = 'Branch ruleset on default branch';                         Label = 'security' }
    @{ N = 10; Name = 'Ruleset active with no person in bypass list';             Label = 'security' }
    @{ N = 11; Name = 'Actions pinned by commit SHA';                             Label = 'security' }
    @{ N = 12; Name = 'permissions block in every workflow';                      Label = 'security' }
    @{ N = 13; Name = 'CODEOWNERS present';                                       Label = 'process'  }
    @{ N = 14; Name = 'SECURITY.md present with reporting channel';               Label = 'process'  }
    @{ N = 15; Name = 'CODE_OF_CONDUCT.md and CONTRIBUTING.md present';           Label = 'process'  }
    @{ N = 16; Name = 'LICENSE present and correct';                              Label = 'process'  }
    @{ N = 17; Name = 'OpenSSF Scorecard workflow present and badge in README';   Label = 'process'  }
    @{ N = 18; Name = 'IsAotCompatible and IsTrimmable enabled';                  Label = 'process'  }
    @{ N = 19; Name = 'Changelog fragments convention and CI check';              Label = 'process'  }
    @{ N = 20; Name = 'Security-alert triage workflow present';                   Label = 'security' }
    @{ N = 21; Name = 'Warnings-as-errors on for Release builds';                 Label = 'process'  }
    @{ N = 22; Name = 'README present with build and test instructions';          Label = 'process'  }
    @{ N = 23; Name = 'GitHub Pages deploy mode matches the docs workflow';        Label = 'process'  }
    @{ N = 24; Name = 'No workflow disabled for inactivity';                       Label = 'process'  }
)
$itemByNumber = @{}
foreach ($i in $items) { $itemByNumber[$i.N] = $i }

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Invoke-GhApi
{
    param([string]$Path, [switch]$AllowNotFound)

    # Keep stdout (JSON) and stderr (gh diagnostics) apart: a warning on stderr
    # would otherwise corrupt the JSON and abort the whole repository's audit.
    $errFile = [System.IO.Path]::GetTempFileName()
    try
    {
        $raw = & gh api $Path 2> $errFile
        $exit = $LASTEXITCODE
        $err = if (Test-Path $errFile) { (Get-Content $errFile -Raw -ErrorAction SilentlyContinue) } else { '' }
    }
    finally
    {
        Remove-Item $errFile -Force -ErrorAction SilentlyContinue
    }
    if ($exit -ne 0)
    {
        # -AllowNotFound means exactly that: a 404 is a legitimate "not configured" answer.
        # Rate limits, permission and transient errors still throw so the repository lands
        # in the failed list instead of being scored as if the resource were absent.
        if ($AllowNotFound -and $err -match 'HTTP 404') { return $null }
        throw "gh api $Path failed (exit $exit): $err"
    }
    return ($raw | Out-String | ConvertFrom-Json -Depth 20)
}



function New-Result
{
    param([string]$RepoName, [int]$Item, [ValidateSet('pass', 'fail', 'na', 'pending')][string]$Status, [string]$Evidence)

    [pscustomobject]@{
        repo     = $RepoName
        item     = $Item
        name     = $itemByNumber[$Item].Name
        status   = $Status
        evidence = $Evidence
    }
}



function Get-FirstExisting
{
    param([string]$Root, [string[]]$Candidates)

    foreach ($c in $Candidates)
    {
        $p = Join-Path $Root $c
        if (Test-Path $p) { return $p }
    }
    return $null
}



function Get-Workflows
{
    param([string]$Root)

    $dir = Join-Path $Root '.github/workflows'
    if (-not (Test-Path $dir)) { return @() }
    return @(Get-ChildItem $dir -File | Where-Object { $_.Name -match '\.ya?ml$' })
}



function Test-WorkflowPermissions
{
    # True when the workflow has a top-level permissions: key, or every job declares one.
    param([string]$Path)

    $lines = Get-Content $Path
    if ($lines | Where-Object { $_ -match '^permissions:' }) { return $true }

    $inJobs = $false
    $jobs = @()
    $current = $null
    foreach ($line in $lines)
    {
        if ($line -match '^jobs:\s*$') { $inJobs = $true; continue }
        if (-not $inJobs) { continue }
        if ($line -match '^[A-Za-z]') { break }                       # left the jobs: block
        if ($line -match '^  ([A-Za-z0-9_.-]+):\s*$')
        {
            $current = @{ Name = $Matches[1]; HasPermissions = $false }
            $jobs += $current
            continue
        }
        if ($null -ne $current -and $line -match '^    permissions:') { $current.HasPermissions = $true }
    }
    if ($jobs.Count -eq 0) { return $false }
    return -not ($jobs | Where-Object { -not $_.HasPermissions })
}



function Get-DefaultBranchRuleset
{
    # Returns the ruleset objects (full detail) that target the default branch.
    param([string]$FullName, [string]$DefaultBranch)

    $list = Invoke-GhApi "repos/$FullName/rulesets" -AllowNotFound
    if ($null -eq $list) { return @() }
    $matched = @()
    foreach ($rs in @($list))
    {
        if ($rs.target -ne 'branch') { continue }
        $detail = Invoke-GhApi "repos/$FullName/rulesets/$($rs.id)"
        $includes = @()
        if ($detail.PSObject.Properties['conditions'] -and $detail.conditions -and $detail.conditions.PSObject.Properties['ref_name'])
        {
            $includes = @($detail.conditions.ref_name.include)
        }
        $targetsDefault = $includes | Where-Object { $_ -in @('~DEFAULT_BRANCH', '~ALL', "refs/heads/$DefaultBranch") }
        if ($targetsDefault) { $matched += $detail }
    }
    return $matched
}



function Get-ScorecardScore
{
    param([string]$FullName)

    try
    {
        $r = Invoke-RestMethod -Uri "https://api.securityscorecards.dev/projects/github.com/$FullName" -TimeoutSec 20
        return "score $($r.score) on $(([datetime]$r.date).ToString('yyyy-MM-dd'))"
    }
    catch
    {
        return 'no score published'
    }
}



function Get-CodeqlRunStatus
{
    param([string]$FullName, [string]$WorkflowFile, [string]$DefaultBranch)

    $runs = Invoke-GhApi "repos/$FullName/actions/workflows/$WorkflowFile/runs?branch=$DefaultBranch&status=completed&per_page=1" -AllowNotFound
    if ($null -eq $runs -or $runs.total_count -eq 0) { return 'no completed run on default branch' }
    $run = $runs.workflow_runs[0]
    return "$($run.conclusion) ($($run.html_url))"
}

# ---------------------------------------------------------------------------
# Per-repository audit
# ---------------------------------------------------------------------------
function Invoke-RepoAudit
{
    param([pscustomobject]$RepoInfo, [string]$CloneRoot)

    $name = $RepoInfo.name
    $full = "$Owner/$name"
    $out = [System.Collections.Generic.List[object]]::new()
    Write-Host "== $full" -ForegroundColor Cyan

    $meta = Invoke-GhApi "repos/$full"
    $default = $meta.default_branch
    $sa = $meta.security_and_analysis

    $clone = Join-Path $CloneRoot $name
    if (-not (Test-Path $clone))
    {
        $cloneOut = & git -c core.longpaths=true clone --quiet --depth 1 --branch $default "https://github.com/$full.git" $clone 2>&1
        if ($LASTEXITCODE -ne 0) { throw "clone of $full failed: $cloneOut" }
    }
    else
    {
        # A reused -WorkDir must audit the default branch as it is NOW, not as it was
        # when the directory was first populated (a stale clone silently reports the
        # previous run's state for every file-based item).
        $fetchOut = & git -C $clone fetch --quiet --depth 1 origin $default 2>&1
        if ($LASTEXITCODE -ne 0) { throw "fetch of $full failed: $fetchOut" }
        & git -C $clone checkout --quiet --force -B $default FETCH_HEAD 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) { throw "checkout of $full $default failed" }
    }

    $csprojs   = @(Get-ChildItem $clone -Recurse -File -Filter *.csproj)
    $srcCsproj = @($csprojs | Where-Object { $_.FullName.Substring($clone.Length) -match '[\\/]src[\\/]' })
    $isDotNet  = $csprojs.Count -gt 0
    # Library = at least one src/ project that is not an Exe, not a template pack, and not a test/benchmark project.
    $libCsproj = @($srcCsproj | Where-Object {
        $t = Get-Content $_.FullName -Raw
        $t -notmatch '(?i)<OutputType>\s*Exe\s*<' -and $t -notmatch '(?i)<PackageType>\s*Template' -and $_.BaseName -notmatch '(?i)\.(Tests?|IntegrationTests|Benchmarks?)$'
    })
    $isLibrary = $libCsproj.Count -gt 0
    $hasCSharp = $isDotNet -or (Get-ChildItem $clone -Recurse -File -Filter *.cs | Select-Object -First 1)
    $workflows = @(Get-Workflows $clone)
    $readme    = Get-FirstExisting $clone @('README.md', 'readme.md', 'README')
    $readmeTxt = if ($readme) { Get-Content $readme -Raw } else { '' }
    $dbpPath   = Join-Path $clone 'Directory.Build.props'
    $dbpTxt    = if (Test-Path $dbpPath) { Get-Content $dbpPath -Raw } else { '' }

    # 1 / 2 / 5 -- repository security settings
    $ss = if ($sa -and $sa.PSObject.Properties['secret_scanning']) { $sa.secret_scanning.status } else { 'unknown' }
    $out.Add((New-Result $name 1 ($(if ($ss -eq 'enabled') { 'pass' } else { 'fail' })) "secret_scanning.status=$ss"))

    $pp = if ($sa -and $sa.PSObject.Properties['secret_scanning_push_protection']) { $sa.secret_scanning_push_protection.status } else { 'unknown' }
    $out.Add((New-Result $name 2 ($(if ($pp -eq 'enabled') { 'pass' } else { 'fail' })) "secret_scanning_push_protection.status=$pp"))

    $out.Add((New-Result $name 3 'pending' 'pending WMS: license-key and API-key formats not defined yet; no API on a personal account'))

    $hook = $null
    $hookEvidence = 'no .pre-commit-config.yaml with gitleaks and no .githooks/pre-commit'
    $preCommit = Join-Path $clone '.pre-commit-config.yaml'
    if ((Test-Path $preCommit) -and ((Get-Content $preCommit -Raw) -match 'gitleaks')) { $hook = '.pre-commit-config.yaml references gitleaks' }
    $githook = Join-Path $clone '.githooks/pre-commit'
    if (-not $hook -and (Test-Path $githook))
    {
        $contrib = Get-FirstExisting $clone @('CONTRIBUTING.md', '.github/CONTRIBUTING.md')
        $docs = $readmeTxt + $(if ($contrib) { Get-Content $contrib -Raw } else { '' })
        if ($docs -match 'core\.hooksPath') { $hook = '.githooks/pre-commit present and core.hooksPath documented' }
        else { $hook = $null; $hookEvidence = '.githooks/pre-commit present but core.hooksPath not documented' }
    }
    if ($hook) { $out.Add((New-Result $name 4 'pass' $hook)) }
    else { $out.Add((New-Result $name 4 'fail' $hookEvidence)) }

    $dsu = if ($sa -and $sa.PSObject.Properties['dependabot_security_updates']) { $sa.dependabot_security_updates.status } else { $null }
    if ($null -eq $dsu)
    {
        $asf = Invoke-GhApi "repos/$full/automated-security-fixes" -AllowNotFound
        $dsu = if ($asf -and $asf.enabled) { 'enabled' } else { 'disabled' }
    }
    $out.Add((New-Result $name 5 ($(if ($dsu -eq 'enabled') { 'pass' } else { 'fail' })) "dependabot_security_updates.status=$dsu"))

    # 6 -- dependabot.yml ecosystems
    $depPath = Get-FirstExisting $clone @('.github/dependabot.yml', '.github/dependabot.yaml')
    if (-not $isDotNet -and $workflows.Count -eq 0)
    {
        $out.Add((New-Result $name 6 'na' 'no .csproj and no workflows'))
    }
    elseif (-not $depPath)
    {
        $out.Add((New-Result $name 6 'fail' '.github/dependabot.yml missing'))
    }
    else
    {
        $dep = Get-Content $depPath -Raw
        $missing = @()
        if ($isDotNet -and $dep -notmatch 'package-ecosystem:\s*["'']?nuget') { $missing += 'nuget' }
        if ($workflows.Count -gt 0 -and $dep -notmatch 'package-ecosystem:\s*["'']?github-actions') { $missing += 'github-actions' }
        if ($missing.Count -eq 0) { $out.Add((New-Result $name 6 'pass' 'nuget and github-actions ecosystems present')) }
        else { $out.Add((New-Result $name 6 'fail' "dependabot.yml missing ecosystem(s): $($missing -join ', ')")) }
    }

    # 7 -- CodeQL
    $codeql = @($workflows | Where-Object { $_.Name -match '^codeql.*\.ya?ml$' })
    if (-not $hasCSharp)
    {
        $out.Add((New-Result $name 7 'na' 'no C# source'))
    }
    elseif ($codeql.Count -eq 0)
    {
        $out.Add((New-Result $name 7 'fail' 'no .github/workflows/codeql*.yml'))
    }
    else
    {
        $status = Get-CodeqlRunStatus $full $codeql[0].Name $default
        $out.Add((New-Result $name 7 ($(if ($status -like 'success*') { 'pass' } else { 'fail' })) "$($codeql[0].Name): last run $status"))
    }

    # 8 -- gitleaks / DevSkim
    $scanners = @()
    foreach ($wf in $workflows)
    {
        # Only uncommented lines that are not job/step names count, so a comment or a step
        # called "gitleaks" cannot satisfy the item; a uses: or run: invocation can.
        $active = @(Get-Content $wf.FullName | Where-Object { $_ -notmatch '^\s*#' -and $_ -notmatch '^\s*-?\s*name:' })
        if ($active -match '(?i)gitleaks') { $scanners += "gitleaks ($($wf.Name))" }
        if ($active -match '(?i)devskim')  { $scanners += "devskim ($($wf.Name))" }
    }
    if ($scanners.Count -gt 0) { $out.Add((New-Result $name 8 'pass' ($scanners -join '; '))) }
    else { $out.Add((New-Result $name 8 'fail' 'no workflow references gitleaks or DevSkim')) }

    # 9 / 10 -- rulesets
    $rulesets = @(Get-DefaultBranchRuleset $full $default)
    if ($rulesets.Count -eq 0)
    {
        $out.Add((New-Result $name 9 'fail' "no branch ruleset targets $default"))
        $out.Add((New-Result $name 10 'fail' "no branch ruleset targets $default"))
    }
    else
    {
        # required_linear_history is advisory: linear history is being trialled per repo
        # (wms first) rather than mandated fleet-wide, so it is reported in the evidence but
        # does not fail the item. Promote it to $required once the trial settles.
        $required = @('pull_request', 'required_status_checks', 'non_fast_forward', 'deletion')
        $present = @($rulesets | ForEach-Object { $_.rules } | ForEach-Object { $_.type } | Sort-Object -Unique)
        $missingRules = @($required | Where-Object { $_ -notin $present })
        $linear = if ('required_linear_history' -in $present) { 'linear history on' } else { 'linear history off (advisory)' }
        $rsNames = ($rulesets | ForEach-Object { "'$($_.name)' (#$($_.id))" }) -join ', '
        if ($missingRules.Count -eq 0) { $out.Add((New-Result $name 9 'pass' "$rsNames has all required rules; $linear")) }
        else { $out.Add((New-Result $name 9 'fail' "$rsNames missing rule(s): $($missingRules -join ', '); $linear")) }

        $problems = @()
        foreach ($rs in $rulesets)
        {
            if ($rs.enforcement -ne 'active') { $problems += "'$($rs.name)' enforcement=$($rs.enforcement)" }
            $actors = if ($rs.PSObject.Properties['bypass_actors']) { @($rs.bypass_actors) } else { @() }
            foreach ($a in $actors)
            {
                if ($a.actor_type -notin @('RepositoryRole', 'OrganizationAdmin', 'DeployKey'))
                {
                    $problems += "'$($rs.name)' bypass actor $($a.actor_type) #$($a.actor_id)"
                }
            }
        }
        if ($problems.Count -eq 0) { $out.Add((New-Result $name 10 'pass' "$rsNames active; bypass list has no users, teams, or apps")) }
        else { $out.Add((New-Result $name 10 'fail' ($problems -join '; '))) }
    }

    # 11 / 12 -- workflow hygiene
    if ($workflows.Count -eq 0)
    {
        $out.Add((New-Result $name 11 'na' 'no workflows'))
        $out.Add((New-Result $name 12 'na' 'no workflows'))
    }
    else
    {
        $unpinned = @()
        $noPerms = @()
        foreach ($wf in $workflows)
        {
            foreach ($line in (Get-Content $wf.FullName))
            {
                if ($line -match '^\s*-?\s*uses:\s*["'']?([^\s"''#]+)')
                {
                    $ref = $Matches[1]
                    if ($ref.StartsWith('./') -or $ref.StartsWith('docker://')) { continue }
                    if ($ref -notmatch '@[0-9a-f]{40}$') { $unpinned += "$($wf.Name): $ref" }
                }
            }
            if (-not (Test-WorkflowPermissions $wf.FullName)) { $noPerms += $wf.Name }
        }
        if ($unpinned.Count -eq 0) { $out.Add((New-Result $name 11 'pass' "all external uses: in $($workflows.Count) workflow(s) are SHA-pinned")) }
        else { $out.Add((New-Result $name 11 'fail' ("$($unpinned.Count) unpinned: " + (($unpinned | Select-Object -Unique) -join '; ')))) }

        if ($noPerms.Count -eq 0) { $out.Add((New-Result $name 12 'pass' "permissions declared in all $($workflows.Count) workflow(s)")) }
        else { $out.Add((New-Result $name 12 'fail' "no permissions block: $($noPerms -join ', ')")) }
    }

    # 13 / 14 / 15 -- community files
    $co = Get-FirstExisting $clone @('.github/CODEOWNERS', 'CODEOWNERS', 'docs/CODEOWNERS')
    $out.Add((New-Result $name 13 ($(if ($co) { 'pass' } else { 'fail' })) $(if ($co) { $co.Substring($clone.Length + 1) } else { 'no CODEOWNERS' })))

    $sec = Get-FirstExisting $clone @('SECURITY.md', '.github/SECURITY.md')
    if (-not $sec) { $out.Add((New-Result $name 14 'fail' 'no SECURITY.md')) }
    else
    {
        $secTxt = Get-Content $sec -Raw
        if ($secTxt -match '(?i)[\w.+-]+@[\w-]+\.[\w.]+|security advisor|report a vulnerability|security/advisories') { $out.Add((New-Result $name 14 'pass' 'SECURITY.md has a reporting channel')) }
        else { $out.Add((New-Result $name 14 'fail' 'SECURITY.md present but no reporting channel found')) }
    }

    $coc = Get-FirstExisting $clone @('CODE_OF_CONDUCT.md', '.github/CODE_OF_CONDUCT.md')
    $contribFile = Get-FirstExisting $clone @('CONTRIBUTING.md', '.github/CONTRIBUTING.md')
    $missingCommunity = @()
    if (-not $coc) { $missingCommunity += 'CODE_OF_CONDUCT.md' }
    if (-not $contribFile) { $missingCommunity += 'CONTRIBUTING.md' }
    if ($missingCommunity.Count -eq 0) { $out.Add((New-Result $name 15 'pass' 'both present')) }
    else { $out.Add((New-Result $name 15 'fail' "missing: $($missingCommunity -join ', ')")) }

    # 16 -- license
    $lic = Get-FirstExisting $clone @('LICENSE', 'LICENSE.md', 'LICENSE.txt')
    $spdx = if ($meta.license) { $meta.license.spdx_id } else { 'none' }
    # The template offers MIT, Apache-2.0 and MPL-2.0 at setup; all three are acceptable for a
    # library. The custom/TBD option ("all rights reserved pending selection") is a pending state.
    $templateLicenses = @('MIT', 'Apache-2.0', 'MPL-2.0')
    $licTxt = if ($lic) { Get-Content $lic -Raw } else { '' }
    if (-not $lic) { $out.Add((New-Result $name 16 'fail' 'no LICENSE file')) }
    elseif ($isLibrary -and $licTxt -match '(?i)all rights reserved.*pending') { $out.Add((New-Result $name 16 'pending' 'custom/TBD license placeholder - choose a license')) }
    elseif ($isLibrary -and $spdx -notin $templateLicenses) { $out.Add((New-Result $name 16 'fail' "library repo license is $spdx, expected one of $($templateLicenses -join ', ')")) }
    else { $out.Add((New-Result $name 16 'pass' "license $spdx")) }

    # 17 -- scorecard
    $scWf = @($workflows | Where-Object { (Get-Content $_.FullName -Raw) -match 'ossf/scorecard-action' })
    $badge = $readmeTxt -match 'securityscorecards\.dev|scorecard\.dev'
    $score = Get-ScorecardScore $full
    $scProblems = @()
    if ($scWf.Count -eq 0) { $scProblems += 'no Scorecard workflow' }
    if (-not $badge) { $scProblems += 'no Scorecard badge in README' }
    if ($scProblems.Count -eq 0) { $out.Add((New-Result $name 17 'pass' "$($scWf[0].Name); badge present; $score")) }
    else { $out.Add((New-Result $name 17 'fail' "$($scProblems -join '; '); $score")) }

    # 18 -- AOT / trim
    if (-not $isLibrary) { $out.Add((New-Result $name 18 'na' 'not a library repo (no non-Exe, non-template src/**/*.csproj)')) }
    else
    {
        $aot  = $dbpTxt -match '<IsAotCompatible[^>]*>\s*true\s*<'
        $trim = $dbpTxt -match '<IsTrimmable[^>]*>\s*true\s*<'
        if (-not $aot -or -not $trim)
        {
            # Fall back to per-project declarations: every src csproj must carry the flag.
            $projAot  = @($libCsproj | Where-Object { (Get-Content $_.FullName -Raw) -match '<IsAotCompatible[^>]*>\s*true\s*<' }).Count
            $projTrim = @($libCsproj | Where-Object { (Get-Content $_.FullName -Raw) -match '<IsTrimmable[^>]*>\s*true\s*<' }).Count
            if (-not $aot)  { $aot  = $projAot  -eq $libCsproj.Count }
            if (-not $trim) { $trim = $projTrim -eq $libCsproj.Count -or $aot }   # IsAotCompatible=true implies IsTrimmable on net8+
        }
        if ($aot -and $trim) { $out.Add((New-Result $name 18 'pass' 'IsAotCompatible=true (IsTrimmable implied or explicit); trim-warning build not performed by audit')) }
        else
        {
            $found = @()
            if (-not $aot)  { $found += 'IsAotCompatible not set' }
            if (-not $trim) { $found += 'IsTrimmable not set' }
            $out.Add((New-Result $name 18 'fail' ($found -join '; ')))
        }
    }

    # 19 -- changelog fragments
    $fragDir = Test-Path (Join-Path $clone 'changelog/unreleased')
    $fragCheck = @($workflows | Where-Object { (Get-Content $_.FullName -Raw) -match 'changelog\.ps1' }).Count -gt 0
    if ($fragDir -and $fragCheck) { $out.Add((New-Result $name 19 'pass' 'changelog/unreleased/ present and CI check wired')) }
    else
    {
        $found = @()
        if (-not $fragDir)   { $found += 'no changelog/unreleased/ directory' }
        if (-not $fragCheck) { $found += 'no workflow runs changelog.ps1 check' }
        $out.Add((New-Result $name 19 'fail' ($found -join '; ')))
    }

    # 20 -- security-alerts workflow
    $alerts = Get-FirstExisting $clone @('.github/workflows/security-alerts.yml', '.github/workflows/security-alerts.yaml')
    $out.Add((New-Result $name 20 ($(if ($alerts) { 'pass' } else { 'fail' })) $(if ($alerts) { 'security-alerts workflow present' } else { 'no .github/workflows/security-alerts.yml' })))

    # 21 -- warnings as errors
    if (-not $isDotNet) { $out.Add((New-Result $name 21 'na' 'no .csproj')) }
    elseif (-not $dbpTxt) { $out.Add((New-Result $name 21 'fail' 'no Directory.Build.props')) }
    else
    {
        # Must be conditioned on Configuration == Release (the fleet convention: Release is what CI builds
        # and packs; Debug stays warnings-as-warnings for local iteration). Unconditional true fails because
        # it would gate Debug too. Inner MSBuild quotes may be ' or " (captured and back-referenced).
        $twae = [regex]::Matches($dbpTxt, '<TreatWarningsAsErrors([^>]*)>\s*([^<]*)\s*<')
        $releaseCond = "^\s*Condition\s*=\s*[`"']\s*([`"'])\`$\(Configuration\)\1\s*==\s*([`"'])Release\2\s*[`"']\s*$"
        $good = @($twae | Where-Object { $_.Groups[2].Value.Trim() -eq 'true' -and $_.Groups[1].Value.Trim() -match $releaseCond })
        if ($good.Count -gt 0) { $out.Add((New-Result $name 21 'pass' 'TreatWarningsAsErrors=true for Release in Directory.Build.props')) }
        elseif ($twae | Where-Object { $_.Groups[2].Value.Trim() -eq 'true' -and $_.Groups[1].Value -notmatch 'Condition' }) { $out.Add((New-Result $name 21 'fail' 'TreatWarningsAsErrors=true is unconditional; it must be conditioned on Release so Debug builds are not gated')) }
        elseif ($twae.Count -gt 0) { $out.Add((New-Result $name 21 'fail' "TreatWarningsAsErrors present but not conditioned on Release:$($twae[0].Groups[1].Value.Trim())")) }
        else { $out.Add((New-Result $name 21 'fail' 'TreatWarningsAsErrors not set in Directory.Build.props')) }
    }

    # 22 -- README
    if (-not $readme) { $out.Add((New-Result $name 22 'fail' 'no README.md')) }
    elseif ($isDotNet)
    {
        $hasBuild = $readmeTxt -match 'dotnet build|build-pr\.ps1|build\.ps1'
        $hasTest  = $readmeTxt -match 'dotnet test|build-pr\.ps1|build\.ps1'
        if ($hasBuild -and $hasTest) { $out.Add((New-Result $name 22 'pass' 'README documents build and test')) }
        else { $out.Add((New-Result $name 22 'fail' "README lacks $(if (-not $hasBuild) { 'build' }) $(if (-not $hasTest) { 'test' }) instructions".Trim())) }
    }
    else
    {
        if ($readmeTxt -match '(?im)^#+\s*(build|usage|getting started)') { $out.Add((New-Result $name 22 'pass' 'README has a Build/Usage/Getting Started section')) }
        else { $out.Add((New-Result $name 22 'fail' 'README has no Build, Usage, or Getting Started section')) }
    }

    # 23 -- GitHub Pages deploy mode vs the docs workflow
    # A docs deployment workflow is any docfx*.yaml (the template's push-to-gh-pages pattern)
    # or any workflow with an active `uses: actions/deploy-pages` step (the modern pattern),
    # whatever it is named. Every one found is checked; comments do not count.
    $docsWfs = @()
    foreach ($wf in $workflows)
    {
        $active = @(Get-Content $wf.FullName | Where-Object { $_ -notmatch '^\s*#' })
        $deployPages = [bool]($active -match '^\s*-?\s*uses:\s*actions/deploy-pages')
        if ($deployPages -or $wf.Name -match '^docfx.*\.ya?ml$')
        {
            $docsWfs += [pscustomobject]@{ Name = $wf.Name; UsesDeployPages = $deployPages; Expected = $(if ($deployPages) { 'workflow' } else { 'legacy' }) }
        }
    }
    if ($docsWfs.Count -eq 0)
    {
        $out.Add((New-Result $name 23 'na' 'no docs deployment workflow (docfx*.yaml or actions/deploy-pages)'))
    }
    else
    {
        $wfNames = ($docsWfs | ForEach-Object { $_.Name }) -join ', '
        $pages = Invoke-GhApi "repos/$full/pages" -AllowNotFound
        if ($null -eq $pages)
        {
            $out.Add((New-Result $name 23 'na' "$wfNames present but no Pages site configured yet"))
        }
        else
        {
            $bt = if ($pages.PSObject.Properties['build_type']) { $pages.build_type } else { 'unknown' }
            $branch = if ($pages.PSObject.Properties['source'] -and $pages.source) { $pages.source.branch } else { $null }
            $problems = @()
            foreach ($d in $docsWfs)
            {
                if ($bt -ne $d.Expected) { $problems += "build_type=$bt but $($d.Name) $(if ($d.UsesDeployPages) { 'uses actions/deploy-pages' } else { 'pushes to gh-pages' }) (expected $($d.Expected))" }
                if (-not $d.UsesDeployPages -and $branch -ne 'gh-pages') { $problems += "source.branch=$branch but $($d.Name) pushes to gh-pages" }
            }
            if ($problems.Count -eq 0) { $out.Add((New-Result $name 23 'pass' "build_type=$bt, source.branch=$branch, matches $wfNames")) }
            else { $out.Add((New-Result $name 23 'fail' (($problems | Select-Object -Unique) -join '; '))) }
        }
    }

    # 24 -- workflows switched off (60 days idle disables scheduled workflows, and with
    # them that file's pull_request runs; a required check from one never reports)
    if ($workflows.Count -eq 0)
    {
        $out.Add((New-Result $name 24 'na' 'no workflows'))
    }
    else
    {
        # Paginate: the endpoint caps at 100 per page and a disabled workflow on page 2 must not pass.
        $allWf = @(); $page = 1
        do
        {
            $wfState = Invoke-GhApi "repos/$full/actions/workflows?per_page=100&page=$page"
            $batch = @($wfState.workflows)
            $allWf += $batch
            $page++
        } while ($batch.Count -eq 100)
        $off = @($allWf | Where-Object { $_.path -like '.github/workflows/*' -and $_.state -ne 'active' })
        if ($off.Count -eq 0) { $out.Add((New-Result $name 24 'pass' "$($allWf.Count) workflow(s) active")) }
        else { $out.Add((New-Result $name 24 'fail' (($off | ForEach-Object { "$($_.path -replace '^\.github/workflows/', '')=$($_.state)" }) -join ', '))) }
    }

    return $out
}

# ---------------------------------------------------------------------------
# Issue creation
# ---------------------------------------------------------------------------
function Confirm-Labels
{
    param([string]$FullName)

    $existing = @(& gh label list -R $FullName --limit 200 --json name --jq '.[].name')
    $wanted = @(
        @{ Name = 'baseline'; Color = '0e8a16'; Description = 'Repository hardening baseline gap' }
        @{ Name = 'security'; Color = 'd93f0b'; Description = 'Security-related' }
        @{ Name = 'process';  Color = 'c5def5'; Description = 'Process or hygiene' }
    )
    foreach ($l in $wanted)
    {
        if ($l.Name -notin $existing)
        {
            & gh label create $l.Name -R $FullName --color $l.Color --description $l.Description | Out-Null
            Write-Host "   created label '$($l.Name)'"
        }
    }
}



function Open-BaselineIssues
{
    param([string]$FullName, [object[]]$Failures, [string]$BaselineUrl)

    if ($Failures.Count -eq 0) { return 0 }
    Confirm-Labels $FullName
    $openTitles = @(& gh issue list -R $FullName --state open --limit 500 --search 'Baseline: in:title' --json title --jq '.[].title')
    # A closed issue carrying the wontfix label is a deliberate decision not to meet the item in
    # this repository; do not re-open it on every run.
    $wontfixTitles = @(& gh issue list -R $FullName --state closed --limit 500 --label wontfix --search 'Baseline: in:title' --json title --jq '.[].title')
    $created = 0
    foreach ($f in $Failures)
    {
        $title = "Baseline: $($f.name)"
        if ($title -in $openTitles) { Write-Host "   skip (open): $title"; continue }
        if ($title -in $wontfixTitles) { Write-Host "   skip (closed wontfix): $title"; continue }
        $label = $itemByNumber[$f.item].Label
        $body = @"
Repository hardening baseline item **$($f.item) — $($f.name)** is not met.

**Found:** $(if ($f.evidence.Length -gt 1500) { $f.evidence.Substring(0, 1500) + ' …' } else { $f.evidence })

**Expected:** see item $($f.item) in the [repository baseline]($BaselineUrl#$($f.item)-$(($f.name.ToLower() -replace '[^a-z0-9 ]', '' -replace ' ', '-'))).

**Fix:** follow the fix pointer for item $($f.item) in the baseline (template file or settings page). Re-run ``scripts/audit-repos.ps1`` from ``repo-template`` to verify; this issue is deduplicated by title, so it will not be re-opened once the item passes.

_Opened by the E86 repository hardening audit._
"@
        $url = & gh issue create -R $FullName --title $title --body $body --label baseline --label $label 2>&1
        if ($LASTEXITCODE -ne 0 -or -not ($url -match 'https://github.com/')) { Write-Warning "   failed to create '$title' in ${FullName}: $url"; continue }
        Write-Host "   opened: $url"
        $created++
        Start-Sleep -Seconds 2
    }
    return $created
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
$repos = @(((& gh repo list $Owner --limit 200 --json name,isArchived,visibility) -join "`n") | ConvertFrom-Json)
$repos = @($repos | Where-Object { -not $_.isArchived -and $_.visibility -eq 'PUBLIC' })
if ($Exclude) { $Exclude = @($Exclude | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }); $repos = @($repos | Where-Object { $_.name -notin $Exclude }) }
if ($Repo) { $Repo = @($Repo | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ }); $repos = @($repos | Where-Object { $_.name -in $Repo }) }
$repos = @($repos | Sort-Object name)
if ($repos.Count -eq 0) { throw 'no repositories selected' }
Write-Host "Auditing $($repos.Count) repositories under $Owner" -ForegroundColor Green

$cleanup = $false
if (-not $WorkDir)
{
    # Keep the clone root short: Windows path-length limits bite on deep test-snapshot paths.
    $tempRoot = if ($IsWindows -and (Test-Path 'C:\Temp')) { 'C:\Temp' } else { [System.IO.Path]::GetTempPath() }
    $WorkDir = Join-Path $tempRoot "ra-$([guid]::NewGuid().ToString('N').Substring(0, 6))"
    $cleanup = $true
}
New-Item -ItemType Directory -Force -Path $WorkDir | Out-Null
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null

$results = [System.Collections.Generic.List[object]]::new()
$failedRepos = @()
foreach ($r in $repos)
{
    try
    {
        $results.AddRange((Invoke-RepoAudit $r $WorkDir))
    }
    catch
    {
        Write-Warning "audit of $($r.name) failed: $($_.Exception.Message)"
        $failedRepos += $r.name
    }
}

$results | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutputDir 'audit-results.json')

# Summary table
$symbol = @{ pass = '✅'; fail = '❌'; na = '–'; pending = '⏳' }
$sb = [System.Text.StringBuilder]::new()
[void]$sb.AppendLine("# Repository baseline audit — $(Get-Date -Format 'yyyy-MM-dd')")
[void]$sb.AppendLine()
[void]$sb.AppendLine("Owner: ``$Owner``. Items are numbered as in ``docs/repository-baseline.md``. ✅ pass · ❌ fail · – n/a · ⏳ pending")
[void]$sb.AppendLine()
$header = '| Repo | ' + (($items | ForEach-Object { $_.N }) -join ' | ') + ' | pass | fail | na | pending |'
[void]$sb.AppendLine($header)
[void]$sb.AppendLine('|' + ('---|' * ($items.Count + 5)))
foreach ($r in $repos)
{
    $rr = @($results | Where-Object { $_.repo -eq $r.name })
    if ($rr.Count -eq 0) { continue }
    $cells = foreach ($i in $items) { $x = $rr | Where-Object { $_.item -eq $i.N }; $symbol[$x.status] }
    $counts = @('pass', 'fail', 'na', 'pending') | ForEach-Object { $s = $_; @($rr | Where-Object { $_.status -eq $s }).Count }
    [void]$sb.AppendLine("| $($r.name) | $($cells -join ' | ') | $($counts -join ' | ') |")
}
[void]$sb.AppendLine()
[void]$sb.AppendLine('## Failures per item')
[void]$sb.AppendLine()
[void]$sb.AppendLine('| # | Item | Fail | Pass | n/a |')
[void]$sb.AppendLine('|---|------|-----:|-----:|----:|')
foreach ($i in $items)
{
    $ri = @($results | Where-Object { $_.item -eq $i.N })
    $f = @($ri | Where-Object { $_.status -eq 'fail' }).Count
    $p = @($ri | Where-Object { $_.status -eq 'pass' }).Count
    $n = @($ri | Where-Object { $_.status -eq 'na' }).Count
    [void]$sb.AppendLine("| $($i.N) | $($i.Name) | $f | $p | $n |")
}
if ($failedRepos.Count -gt 0)
{
    [void]$sb.AppendLine()
    [void]$sb.AppendLine("**Not audited (error):** $($failedRepos -join ', ')")
}
$sb.ToString() | Set-Content (Join-Path $OutputDir 'audit-summary.md')

Write-Host ''
Write-Host "Results: $(Join-Path $OutputDir 'audit-results.json')"
Write-Host "Summary: $(Join-Path $OutputDir 'audit-summary.md')"
Write-Host "Totals: pass=$(@($results | Where-Object status -eq 'pass').Count) fail=$(@($results | Where-Object status -eq 'fail').Count) na=$(@($results | Where-Object status -eq 'na').Count) pending=$(@($results | Where-Object status -eq 'pending').Count)"

if ($OpenIssues)
{
    Write-Host ''
    Write-Host 'Opening issues for failures...' -ForegroundColor Green
    $baselineUrl = "https://github.com/$Owner/repo-template/blob/main/docs/repository-baseline.md"
    $opened = @{}
    foreach ($r in $repos)
    {
        $fails = @($results | Where-Object { $_.repo -eq $r.name -and $_.status -eq 'fail' -and $_.item -notin @($SkipItems) })
        if ($fails.Count -eq 0) { continue }
        Write-Host "== $($r.name): $($fails.Count) failure(s)"
        $opened[$r.name] = Open-BaselineIssues "$Owner/$($r.name)" $fails $baselineUrl
    }
    $opened | ConvertTo-Json | Set-Content (Join-Path $OutputDir 'audit-issues-opened.json')
    Write-Host "Issues opened: $(($opened.Values | Measure-Object -Sum).Sum)"
}

if ($cleanup) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }
