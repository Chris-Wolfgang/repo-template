#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Reports (and optionally applies) template updates for a repository created from repo-template.

.DESCRIPTION
    setup.ps1 stamps .template-version with the template's commit at setup time. This script
    compares the template-managed files in this repository against the template's current main
    and sorts every changed file into one of three buckets:

      safe    - the template changed the file and this repository still has the version it was
                set up with (a three-way check against the stamped commit). Applied by -Apply.
      review  - both the template and this repository changed the file. Never touched; the
                template's version is written next to the file as <name>.template for a manual merge.
      in-sync - identical to the template; nothing to do.

    Only files the template owns are considered (workflows, analyzer config, scripts, hooks,
    license-audit and pip pins, docs/ guides). Files that carry setup placeholders - README,
    CONTRIBUTING, SECURITY, CODEOWNERS, docfx_project, LICENSE - are never compared: after setup
    they are this repository's, not the template's.

    Without .template-version (a repository set up before stamping existed) every differing file
    is reported as review, since there is no base to tell "template moved" from "we customised".
    Pass -Since <template commit> to supply the base by hand.

.PARAMETER Template
    owner/repo of the template. Default: the value stamped in .template-version, else
    Chris-Wolfgang/repo-template.
.PARAMETER Since
    Template commit to treat as the base instead of the stamped one.
.PARAMETER Apply
    Overwrite the files in the safe bucket with the template's current content and update
    .template-version. Review files still only get a <name>.template sidecar. Default is a
    dry run (report only).
.PARAMETER IncludeDocs
    Also compare docs/*.md guides (off by default: repositories often edit them).

.EXAMPLE
    pwsh ./scripts/upgrade.ps1
    Dry run: lists safe / review / in-sync files against the template's main.
.EXAMPLE
    pwsh ./scripts/upgrade.ps1 -Apply
    Applies the safe files and stamps the new template commit; commit the result as a PR.
.NOTES
    Requires gh (authenticated) and git. Run from the repository root. Remember that workflow and
    Directory.Build.props changes trip the protected-file guard in pr.yaml and need the admin bypass.
#>
[CmdletBinding()]
param
(
    [string]$Template,
    [string]$Since,
    [switch]$Apply,
    [switch]$IncludeDocs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$stampPath = '.template-version'
$stamp = $null
if (Test-Path $stampPath)
{
    $stamp = Get-Content $stampPath -Raw | ConvertFrom-Json
}
if (-not $Template) { $Template = if ($stamp -and $stamp.template) { $stamp.template } else { 'Chris-Wolfgang/repo-template' } }
$base = if ($Since) { $Since } elseif ($stamp -and $stamp.commit) { $stamp.commit } else { $null }

# Files the template owns. Anything else is the repository's after setup.
$managedPrefixes = @('.github/workflows/', '.github/license-audit/', '.github/requirements/', '.githooks/', 'scripts/')
$managedFiles = @('.editorconfig', '.globalconfig', 'BannedSymbols.txt', 'coverlet.runsettings', 'Directory.Build.props',
                  '.gitleaks.toml', '.gitattributes', '.github/dependabot.yml', '.github/pull_request_template.md',
                  '.github/ISSUE_TEMPLATE/BUG_REPORT.yaml', '.github/ISSUE_TEMPLATE/feature_request.yaml',
                  '.github/ISSUE_TEMPLATE/maintenance-task.yaml', 'changelog/unreleased/README.md')
if ($IncludeDocs) { $managedPrefixes += 'docs/' }
# Template-only files that never belong in a generated repository, plus the one-time setup
# scripts that delete themselves after a successful run (their absence is expected).
$templateOnly = @('scripts/setup.ps1', 'scripts/audit-repos.ps1', 'scripts/upgrade.ps1', 'scripts/templates/', 'docs/repository-baseline.md',
                  'scripts/Setup-BranchRuleset.ps1', 'scripts/Setup-GitHubPages.ps1', 'scripts/Setup-Maintenance.ps1')

function Test-Managed([string]$Path)
{
    if ($templateOnly | Where-Object { $Path -eq $_ -or $Path.StartsWith($_) }) { return $false }
    if ($Path -in $managedFiles) { return $true }
    foreach ($p in $managedPrefixes) { if ($Path.StartsWith($p)) { return $true } }
    return $false
}

function Get-TemplateFile([string]$Path, [string]$Ref)
{
    # Raw content at a ref; $null when the file does not exist there.
    $tmp = [System.IO.Path]::GetTempFileName()
    try
    {
        & gh api "repos/$Template/contents/${Path}?ref=${Ref}" -H 'Accept: application/vnd.github.raw' > $tmp 2>$null
        if ($LASTEXITCODE -ne 0) { return $null }
        return [System.IO.File]::ReadAllText($tmp)
    }
    finally { Remove-Item $tmp -Force -ErrorAction SilentlyContinue }
}

function Get-Normalized($Text)
{
    # Untyped on purpose: a [string] parameter turns $null (file absent at that ref) into ''.
    if ($null -eq $Text) { return $null }
    return ([string]$Text -replace "`r`n", "`n").TrimEnd("`n")
}

$head = (& gh api "repos/$Template/commits/main" --jq '.sha')
if ($LASTEXITCODE -ne 0 -or -not $head) { throw "could not read $Template main" }
Write-Host "Template: $Template @ $($head.Substring(0, 7))" -ForegroundColor Cyan
Write-Host "Base:     $(if ($base) { $base.Substring(0, [Math]::Min(7, $base.Length)) + ' (' + $(if ($Since) { '-Since' } else { '.template-version' }) + ')' } else { 'none - no .template-version; every difference is reported as review' })" -ForegroundColor Cyan
Write-Host ''

# Candidate files: everything managed that exists in the template head.
$tree = (& gh api "repos/$Template/git/trees/${head}?recursive=1" --jq '.tree[] | select(.type == "blob") | .path')
if ($LASTEXITCODE -ne 0) { throw "could not list $Template tree" }
$candidates = @($tree | Where-Object { Test-Managed $_ } | Sort-Object)

$safe = @(); $review = @(); $inSync = @(); $missing = @()
foreach ($path in $candidates)
{
    $templateNow = Get-Normalized (Get-TemplateFile $path $head)
    if ($null -eq $templateNow) { continue }
    $local = if (Test-Path $path) { Get-Normalized ([System.IO.File]::ReadAllText($path)) } else { $null }

    if ($null -eq $local)
    {
        # New in the template since setup, or deliberately deleted here. New-in-template is
        # safe to add when the base did not have it either; otherwise it is a local deletion.
        $templateThen = if ($base) { Get-Normalized (Get-TemplateFile $path $base) } else { $null }
        if ($base -and $null -eq $templateThen) { $safe += [pscustomobject]@{ Path = $path; Reason = 'new in template'; Content = $templateNow } }
        else { $missing += $path }
        continue
    }
    if ($local -eq $templateNow) { $inSync += $path; continue }

    $templateThen = if ($base) { Get-Normalized (Get-TemplateFile $path $base) } else { $null }
    if ($base -and $null -ne $templateThen -and $local -eq $templateThen)
    {
        $safe += [pscustomobject]@{ Path = $path; Reason = 'template changed, local untouched since setup'; Content = $templateNow }
    }
    else
    {
        $review += [pscustomobject]@{ Path = $path; Content = $templateNow; Reason = $(if ($base) { 'changed in both the template and this repository' } else { 'differs from the template (no base to compare)' }) }
    }
}

Write-Host "In sync : $($inSync.Count) file(s)" -ForegroundColor Green
if ($missing.Count -gt 0)
{
    Write-Host "Absent here (present in the template; not added automatically): $($missing.Count)" -ForegroundColor DarkGray
    foreach ($m in $missing) { Write-Host "    $m" -ForegroundColor DarkGray }
}
Write-Host "Safe    : $($safe.Count) file(s)$(if (-not $Apply -and $safe.Count) { ' - re-run with -Apply to take them' })" -ForegroundColor $(if ($safe.Count) { 'Yellow' } else { 'Green' })
foreach ($s in $safe) { Write-Host "    $($s.Path)  ($($s.Reason))" }
Write-Host "Review  : $($review.Count) file(s)$(if ($review.Count) { ' - template version written as <file>.template for a manual merge' })" -ForegroundColor $(if ($review.Count) { 'Yellow' } else { 'Green' })
foreach ($r in $review) { Write-Host "    $($r.Path)  ($($r.Reason))" }

if (-not $Apply)
{
    Write-Host ''
    Write-Host 'Dry run - nothing written.' -ForegroundColor Cyan
    exit 0
}

foreach ($s in $safe)
{
    $dir = Split-Path -Parent $s.Path
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    Set-Content -Path $s.Path -Value ($s.Content + "`n") -Encoding utf8NoBOM -NoNewline
    Write-Host "  applied  $($s.Path)" -ForegroundColor Green
}
foreach ($r in $review)
{
    Set-Content -Path "$($r.Path).template" -Value ($r.Content + "`n") -Encoding utf8NoBOM -NoNewline
    Write-Host "  sidecar  $($r.Path).template" -ForegroundColor Yellow
}

$newStamp = [ordered]@{
    template  = $Template
    commit    = $head
    updated   = (Get-Date).ToString('yyyy-MM-dd')
    note      = 'Written by scripts/setup.ps1 and scripts/upgrade.ps1; the template commit this repository last took template-managed files from.'
}
$newStamp | ConvertTo-Json | Set-Content -Path $stampPath -Encoding utf8NoBOM
Write-Host ''
Write-Host "Stamped $stampPath at $($head.Substring(0, 7)). Review the diff, resolve any *.template sidecars, and open a PR." -ForegroundColor Cyan
if ($review.Count -gt 0) { Write-Host 'Delete each .template sidecar once merged; do not commit them.' -ForegroundColor Yellow }
