#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Changelog fragment tooling: check a PR for a fragment, or assemble fragments into CHANGELOG.md.
.DESCRIPTION
    Fragments live in changelog/unreleased/<name>.md. Line 1 is "type: <breaking|feature|fix|docs|internal>",
    the remaining non-empty lines are a one-sentence user-facing description. See changelog/unreleased/README.md.

    check     Fail (exit 1) when files under src/ changed relative to -BaseRef and no fragment was added,
              unless -Labels contains "no-changelog". Always validates every fragment's format.
    assemble  Insert a "## [<version>] - <date>" section under "## [Unreleased]" in CHANGELOG.md from the
              fragments, grouped by type, then delete the fragments. -Version defaults to the derived bump.
    bump      Print the derived next version (from the newest "## [x.y.z]" heading and the fragment types):
              breaking -> major (0.x: minor), feature -> minor, fix/docs/internal -> patch.
.PARAMETER Command
    check | assemble | bump
.PARAMETER Version
    assemble only: the version to write. Derived when omitted.
.PARAMETER BaseRef
    check only: the git ref the PR is compared against. Default origin/main. CI passes the PR base SHA.
.PARAMETER Labels
    check only: comma-separated PR labels. "no-changelog" waives the fragment requirement.
.PARAMETER FragmentDir
    Directory holding the fragments. Default changelog/unreleased.
.PARAMETER ChangelogPath
    Default CHANGELOG.md.
.EXAMPLE
    pwsh ./scripts/changelog.ps1 check
.EXAMPLE
    pwsh ./scripts/changelog.ps1 assemble -Version 0.9.0
#>

[CmdletBinding()]
param
(
    [Parameter(Position = 0, Mandatory)]
    [ValidateSet('check', 'assemble', 'bump')]
    [string]$Command,

    [string]$Version,
    [string]$BaseRef = 'origin/main',
    [string]$Labels = '',
    [string]$FragmentDir = 'changelog/unreleased',
    [string]$ChangelogPath = 'CHANGELOG.md'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$kinds = [ordered]@{
    breaking = 'Breaking changes'
    feature  = 'Added'
    fix      = 'Fixed'
    docs     = 'Documentation'
    internal = 'Internal'
}



function Get-Fragments
{
    if (-not (Test-Path $FragmentDir)) { return @() }
    $files = @(Get-ChildItem $FragmentDir -File -Filter *.md | Where-Object { $_.Name -ne 'README.md' } | Sort-Object Name)
    $result = @()
    foreach ($f in $files)
    {
        $lines = @(Get-Content $f.FullName)
        $errors = @()
        $type = $null
        if ($lines.Count -eq 0 -or $lines[0] -notmatch '^type:\s*([a-z]+)\s*$')
        {
            $errors += 'line 1 must be "type: <breaking|feature|fix|docs|internal>"'
        }
        else
        {
            $type = $Matches[1]
            if (-not $kinds.Contains($type)) { $errors += "unknown type '$type'" }
        }
        $description = (($lines | Select-Object -Skip 1 | Where-Object { $_.Trim() }) -join ' ').Trim()
        if (-not $description) { $errors += 'description is empty' }
        $result += [pscustomobject]@{
            Path        = $f.FullName
            Name        = $f.Name
            RelPath     = (Join-Path $FragmentDir $f.Name) -replace '\\', '/'
            Type        = $type
            Description = $description
            Errors      = $errors
        }
    }
    return $result
}



function Get-CurrentVersion
{
    if (-not (Test-Path $ChangelogPath)) { return '0.0.0' }
    foreach ($line in Get-Content $ChangelogPath)
    {
        if ($line -match '^## \[(\d+)\.(\d+)\.(\d+)[^\]]*\]') { return "$($Matches[1]).$($Matches[2]).$($Matches[3])" }
    }
    return '0.0.0'
}



function Get-DerivedVersion
{
    param([string]$Current, [object[]]$Fragments)

    $parts = $Current.Split('.') | ForEach-Object { [int]$_ }
    $types = @($Fragments | ForEach-Object { $_.Type })
    $rank = if ('breaking' -in $types) { 'breaking' } elseif ('feature' -in $types) { 'feature' } else { 'patch' }
    # Fleet rule: patch releases are lean (fixes only); any new public surface
    # is a MINOR. In 0.x a breaking change is also a MINOR (SemVer has no
    # stable major to bump), so breaking and feature both land on 0.(m+1).0.
    if ($parts[0] -eq 0)
    {
        switch ($rank)
        {
            'patch'  { return "0.$($parts[1]).$($parts[2] + 1)" }
            default  { return "0.$($parts[1] + 1).0" }
        }
    }
    switch ($rank)
    {
        'breaking' { return "$($parts[0] + 1).0.0" }
        'feature'  { return "$($parts[0]).$($parts[1] + 1).0" }
        default    { return "$($parts[0]).$($parts[1]).$($parts[2] + 1)" }
    }
}



function Get-PrSuffix
{
    # Best effort: the PR number from the commit that introduced the fragment (squash "(#123)" or merge "#123").
    param([string]$RelPath)

    $subjects = & git log --format=%s --diff-filter=A -- $RelPath 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $subjects) { return '' }
    foreach ($s in @($subjects))
    {
        if ($s -match '#(\d+)') { return " (#$($Matches[1]))" }
    }
    return ''
}



function Invoke-Check
{
    $fragments = @(Get-Fragments)
    $bad = @($fragments | Where-Object { $_.Errors.Count -gt 0 })
    foreach ($b in $bad) { Write-Host "::error file=$($b.RelPath)::$($b.Name): $($b.Errors -join '; ')" }

    & git rev-parse --verify --quiet "$BaseRef^{commit}" *> $null
    if ($LASTEXITCODE -ne 0) { throw "base ref '$BaseRef' not found; fetch it first (git fetch origin main)" }

    $changed = @(& git diff --name-only "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "git diff against $BaseRef failed" }
    $srcChanged = @($changed | Where-Object { $_ -match '^src/' })
    # Only files ADDED by this PR count as its fragment; editing or deleting an existing fragment does not.
    $added = @(& git diff --name-only --diff-filter=A "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "git diff --diff-filter=A against $BaseRef failed" }
    $addedFragments = @($added | Where-Object { $_ -match "^$([regex]::Escape($FragmentDir))/" -and $_ -notmatch '/README\.md$' })
    $waived = ($Labels -split ',' | ForEach-Object { $_.Trim() }) -contains 'no-changelog'

    Write-Host "src/ files changed: $($srcChanged.Count); fragments added: $($addedFragments.Count); no-changelog label: $waived"

    $failed = $bad.Count -gt 0
    if ($srcChanged.Count -gt 0 -and $addedFragments.Count -eq 0 -and -not $waived)
    {
        Write-Host "::error::This PR changes src/ but adds no changelog fragment. Add $FragmentDir/<change-name>.md (see $FragmentDir/README.md) or apply the 'no-changelog' label."
        $failed = $true
    }
    if ($failed) { exit 1 }
    Write-Host '✅ Changelog fragment check passed'
}



function Invoke-Bump
{
    $fragments = @(Get-Fragments)
    $current = Get-CurrentVersion
    $next = Get-DerivedVersion $current $fragments
    Write-Host "current: $current  fragments: $($fragments.Count)  next: $next"
    Write-Output $next
}



function Invoke-Assemble
{
    $fragments = @(Get-Fragments)
    if ($fragments.Count -eq 0) { throw "no fragments in $FragmentDir; nothing to assemble" }
    $bad = @($fragments | Where-Object { $_.Errors.Count -gt 0 })
    if ($bad.Count -gt 0)
    {
        foreach ($b in $bad) { Write-Host "$($b.Name): $($b.Errors -join '; ')" }
        throw 'fix the fragments above before assembling'
    }
    if (-not (Test-Path $ChangelogPath)) { throw "$ChangelogPath not found" }

    $current = Get-CurrentVersion
    if (-not $Version) { $Version = Get-DerivedVersion $current $fragments }
    if ($Version -notmatch '^\d+\.\d+\.\d+$') { throw "version '$Version' is not x.y.z" }

    $sb = [System.Text.StringBuilder]::new()
    [void]$sb.AppendLine("## [$Version] - $(Get-Date -Format 'yyyy-MM-dd')")
    foreach ($kind in $kinds.Keys)
    {
        $group = @($fragments | Where-Object { $_.Type -eq $kind })
        if ($group.Count -eq 0) { continue }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("### $($kinds[$kind])")
        [void]$sb.AppendLine()
        foreach ($g in $group) { [void]$sb.AppendLine("- $($g.Description)$(Get-PrSuffix $g.RelPath)") }
    }
    $section = $sb.ToString().TrimEnd()

    $lines = [System.Collections.Generic.List[string]]::new([string[]](Get-Content $ChangelogPath))
    $unreleased = -1
    for ($i = 0; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## \[Unreleased\]') { $unreleased = $i; break } }
    if ($unreleased -lt 0) { throw "'## [Unreleased]' heading not found in $ChangelogPath" }
    $insertAt = $lines.Count
    for ($i = $unreleased + 1; $i -lt $lines.Count; $i++) { if ($lines[$i] -match '^## \[') { $insertAt = $i; break } }

    $block = @($section -split "`n") + @('')
    $lines.InsertRange($insertAt, [string[]]$block)
    Set-Content -Path $ChangelogPath -Value ($lines -join "`n") -NoNewline
    Add-Content -Path $ChangelogPath -Value ''

    foreach ($f in $fragments) { Remove-Item $f.Path -Force }
    Write-Host "✅ Wrote [$Version] to $ChangelogPath from $($fragments.Count) fragment(s) (previous: $current) and removed them"
}

switch ($Command)
{
    'check'    { Invoke-Check }
    'bump'     { Invoke-Bump }
    'assemble' { Invoke-Assemble }
}
