#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Changelog fragment tooling: check a PR for a fragment, or assemble fragments into CHANGELOG.md.
.DESCRIPTION
    Fragments live in changelog/unreleased/<name>.md. Line 1 is "type: <breaking|feature|fix|docs|internal|dependencies>",
    the remaining non-empty lines are a one-sentence user-facing description. See changelog/unreleased/README.md.

    check     Fail (exit 1) when files under src/ changed relative to -BaseRef and no fragment was added,
              unless -Labels contains "no-changelog". A release-assembly PR is also exempt: one that
              changes CHANGELOG.md, deletes fragments, and leaves no fragment in -FragmentDir (what
              "assemble" produces). Always validates every fragment's format.
    assemble  Insert a "## [<version>] - <date>" section under "## [Unreleased]" in CHANGELOG.md from the
              fragments, grouped by type, then delete the fragments. -Version defaults to the derived bump.
    bump      Print the derived next version (from the newest "## [x.y.z]" heading and the fragment types):
              breaking -> major (0.x: minor), feature -> minor, fix/docs/internal/dependencies -> patch.
    dependabot
              Write a "type: dependencies" fragment for every open Dependabot PR that has none, named
              dependabot-<pr>.md and listing each bump from the PR body. Dry run by default: prints what it
              would write. With -Apply, commits the fragment onto each PR branch and pushes it. Dependabot
              stops rebasing a branch once someone else commits to it; comment "@dependabot rebase" if the
              PR later needs updating. The fragment check never requires this: Dependabot PRs stay exempt,
              and "assemble" lists any that merged without a fragment anyway (see below).
.PARAMETER Command
    check | assemble | bump | dependabot
.PARAMETER Apply
    dependabot only: commit and push the fragments instead of printing them.
.PARAMETER Repository
    dependabot and assemble: owner/repo for the gh queries. Default: the current repository.
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
    [ValidateSet('check', 'assemble', 'bump', 'dependabot')]
    [string]$Command,
    [switch]$Apply,
    [string]$Repository,

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
    # Dependency bumps. Dependabot PRs are exempt from the fragment check (they cannot write one), so these
    # arrive two ways: "changelog.ps1 dependabot" writes them onto open Dependabot PRs on request, and
    # "assemble" adds a line for every Dependabot PR merged since the previous release that has no fragment.
    dependencies = 'Dependencies'
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
            $errors += 'line 1 must be "type: <breaking|feature|fix|docs|internal|dependencies>"'
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



function Get-RepositorySlug
{
    if ($Repository) { return $Repository }
    $slug = & gh repo view --json nameWithOwner --jq .nameWithOwner 2>$null
    if ($LASTEXITCODE -ne 0 -or -not $slug) { throw 'could not determine the repository; pass -Repository owner/repo' }
    return $slug.Trim()
}



function Test-GhAvailable
{
    return [bool](Get-Command gh -ErrorAction SilentlyContinue)
}



function Get-DependabotPrs
{
    # Open Dependabot PRs, or the ones merged since -MergedSince (yyyy-MM-dd), oldest first.
    param([string]$State = 'open', [string]$MergedSince)
    $slug = Get-RepositorySlug
    $search = "author:app/dependabot is:pr"
    if ($State -eq 'merged') { $search += " is:merged merged:>=$MergedSince" } else { $search += ' is:open' }
    $json = & gh pr list --repo $slug --state all --search $search --limit 200 --json number,title,body,headRefName,mergedAt,url 2>$null
    if ($LASTEXITCODE -ne 0) { throw "gh pr list failed for $slug" }
    $prs = @($json | ConvertFrom-Json)
    return @($prs | Sort-Object number)
}



function Get-DependencyLines
{
    # One "- `package` a -> b" line per bump in a Dependabot PR. Grouped PRs list each update in the body
    # ("Updates `x` from 1.2 to 1.3"); a single-package PR says it in the title ("Bump x from 1.2 to 1.3").
    param($Pr)
    $lines = @()
    $body = [string]$Pr.body
    foreach ($m in [regex]::Matches($body, 'Updates\s+`([^`]+)`\s+from\s+(\S+)\s+to\s+(\S+)'))
    {
        $lines += "``$($m.Groups[1].Value)`` $($m.Groups[2].Value) -> $($m.Groups[3].Value)"
    }
    if ($lines.Count -eq 0 -and $Pr.title -match '^Bump\s+(.+?)\s+from\s+(\S+)\s+to\s+(\S+)')
    {
        $lines += "``$($Matches[1])`` $($Matches[2]) -> $($Matches[3])"
    }
    if ($lines.Count -eq 0) { $lines += [string]$Pr.title }
    return @($lines | Select-Object -Unique)
}



function Get-DependabotFragmentText
{
    param($Pr)
    $bumps = Get-DependencyLines $Pr
    $scope = if ($Pr.title -match '^Bump the (\S+) group') { "the $($Matches[1]) group: " } else { '' }
    return "type: dependencies`n`n$scope$($bumps -join '; ')."
}



function Invoke-Dependabot
{
    if (-not (Test-GhAvailable)) { throw 'gh is required for the dependabot command' }
    $prs = @(Get-DependabotPrs -State open)
    if ($prs.Count -eq 0) { Write-Host 'No open Dependabot PRs.'; return }
    $slug = Get-RepositorySlug
    foreach ($pr in $prs)
    {
        $name = "dependabot-$($pr.number).md"
        $text = Get-DependabotFragmentText $pr
        # Already carries a fragment? (any file added under the fragment dir on that branch)
        & git fetch --quiet origin "$($pr.headRefName)" 2>$null
        $has = & git ls-tree --name-only "origin/$($pr.headRefName)" -- "$FragmentDir/$name" 2>$null
        if ($has) { Write-Host "#$($pr.number): $name already present, skipping"; continue }
        Write-Host "#$($pr.number) $($pr.title)"
        Write-Host "  $FragmentDir/$name :"
        foreach ($l in ($text -split "`n")) { Write-Host "    $l" }
        if (-not $Apply) { continue }
        $wt = Join-Path ([System.IO.Path]::GetTempPath()) "changelog-dependabot-$($pr.number)"
        if (Test-Path $wt) { & git worktree remove --force $wt *> $null }
        & git worktree add --quiet --detach $wt "origin/$($pr.headRefName)"
        if ($LASTEXITCODE -ne 0) { throw "could not check out $($pr.headRefName)" }
        try
        {
            $dir = Join-Path $wt $FragmentDir
            New-Item -ItemType Directory -Force -Path $dir | Out-Null
            Set-Content -Path (Join-Path $dir $name) -Value $text -Encoding utf8NoBOM -NoNewline
            Add-Content -Path (Join-Path $dir $name) -Value ''
            & git -C $wt add -- "$FragmentDir/$name"
            & git -C $wt commit --quiet -m "docs: changelog fragment for the Dependabot update (#$($pr.number))"
            if ($LASTEXITCODE -ne 0) { throw "commit failed for #$($pr.number)" }
            & git -C $wt push --quiet origin "HEAD:refs/heads/$($pr.headRefName)"
            if ($LASTEXITCODE -ne 0) { throw "push failed for #$($pr.number)" }
            Write-Host "  pushed to $($pr.headRefName) ($slug#$($pr.number))"
        }
        finally
        {
            & git worktree remove --force $wt *> $null
        }
    }
    if (-not $Apply) { Write-Host 'Dry run; pass -Apply to commit the fragments onto the PR branches.' }
}



function Get-PreviousReleaseDate
{
    # The date of the newest "## [x.y.z] - yyyy-MM-dd" heading; the Dependabot backstop lists merges after it.
    if (-not (Test-Path $ChangelogPath)) { return $null }
    foreach ($line in Get-Content $ChangelogPath)
    {
        if ($line -match '^## \[\d+\.\d+\.\d+[^\]]*\]\s*-\s*(\d{4}-\d{2}-\d{2})') { return $Matches[1] }
    }
    return $null
}



function Get-DependabotBackstopLines
{
    # Dependabot PRs merged since the previous release that no fragment mentions: Dependabot cannot write a
    # fragment and is exempt from the check, so the release lists them from the merge history instead.
    param([object[]]$Fragments)
    if (-not (Test-GhAvailable)) { Write-Warning 'gh not available; Dependabot merges without a fragment are not listed'; return @() }
    $since = Get-PreviousReleaseDate
    if (-not $since) { return @() }
    $prs = @()
    try { $prs = @(Get-DependabotPrs -State merged -MergedSince $since) }
    catch { Write-Warning "could not list merged Dependabot PRs: $_"; return @() }
    $covered = @($Fragments | Where-Object { $_.Name -match '^dependabot-(\d+)\.md$' } | ForEach-Object { [int]$Matches[1] })
    $lines = @()
    foreach ($pr in $prs)
    {
        if ($covered -contains [int]$pr.number) { continue }
        $text = (Get-DependabotFragmentText $pr) -split "`n" | Select-Object -Skip 2
        $lines += "- $(($text -join ' ').Trim()) (#$($pr.number))"
    }
    return $lines
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
    # Files under src/ that cannot change what the library does for a consumer, so they cannot
    # need a release note: analyzer configuration (a nested .editorconfig / .globalconfig /
    # .ruleset / .DotSettings) and the PublicAPI baselines, whose content is the mechanical
    # record of a surface change that its own PR already describes. Excluding them matters
    # because such a PR usually CANNOT carry a fragment: the protected-file guard fails a PR
    # that mixes a protected file (a nested .editorconfig is one) with anything else, so the
    # only way through was the 'no-changelog' label on a PR that never needed a note.
    $configOnlyUnderSrc = '(^|/)\.editorconfig$|\.(globalconfig|ruleset|DotSettings)$|(^|/)PublicAPI\.(Shipped|Unshipped)\.txt$'
    $srcChanged = @($changed | Where-Object { $_ -match '^src/' -and $_ -notmatch $configOnlyUnderSrc })
    # Only files ADDED by this PR count as its fragment; editing or deleting an existing fragment does not.
    $added = @(& git diff --name-only --diff-filter=A "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "git diff --diff-filter=A against $BaseRef failed" }
    $addedFragments = @($added | Where-Object { $_ -match "^$([regex]::Escape($FragmentDir))/" -and $_ -notmatch '/README\.md$' })
    $waived = ($Labels -split ',' | ForEach-Object { $_.Trim() }) -contains 'no-changelog'

    # A release PR assembles the fragments rather than adding one: it deletes every file
    # under the fragment directory and writes them into CHANGELOG.md. It also necessarily
    # touches src/ (the csproj <Version>), so without this it fails the gate and the only
    # way through is the 'no-changelog' label - which exists for changes that never needed
    # a note, not for the one PR that carries all of them.
    $deleted = @(& git diff --name-only --diff-filter=D "$BaseRef...HEAD")
    if ($LASTEXITCODE -ne 0) { throw "git diff --diff-filter=D against $BaseRef failed" }
    $deletedFragments = @($deleted | Where-Object { $_ -match "^$([regex]::Escape($FragmentDir))/" -and $_ -notmatch '/README\.md$' })
    # -ChangelogPath may point somewhere other than the repo root, and git reports paths
    # repo-relative with forward slashes, so normalise before comparing.
    $changelogRel = $ChangelogPath.Replace('\', '/')
    if ($changelogRel.StartsWith('./')) { $changelogRel = $changelogRel.Substring(2) }
    # All three conditions, so a non-release PR cannot escape the gate by deleting one stale
    # fragment and touching CHANGELOG.md: assembly leaves the fragment directory empty.
    # $fragments is read from the checked-out tree (the PR merge result in CI).
    $assembled = ($changed -contains $changelogRel) -and $deletedFragments.Count -gt 0 -and $fragments.Count -eq 0

    $srcConfigChanged = @($changed | Where-Object { $_ -match '^src/' -and $_ -match $configOnlyUnderSrc })
    Write-Host "src/ files changed: $($srcChanged.Count) (plus $($srcConfigChanged.Count) analyzer-config/PublicAPI file(s), which never need a fragment); fragments added: $($addedFragments.Count); fragments deleted: $($deletedFragments.Count) (assembles $changelogRel : $assembled); no-changelog label: $waived"

    $failed = $bad.Count -gt 0
    if ($srcChanged.Count -gt 0 -and $addedFragments.Count -eq 0 -and -not $waived -and -not $assembled)
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
    $backstop = @(Get-DependabotBackstopLines $fragments)
    foreach ($kind in $kinds.Keys)
    {
        $group = @($fragments | Where-Object { $_.Type -eq $kind })
        $extra = @(if ($kind -eq 'dependencies') { $backstop } else { @() })
        if ($group.Count -eq 0 -and $extra.Count -eq 0) { continue }
        [void]$sb.AppendLine()
        [void]$sb.AppendLine("### $($kinds[$kind])")
        [void]$sb.AppendLine()
        foreach ($g in $group) { [void]$sb.AppendLine("- $($g.Description)$(Get-PrSuffix $g.RelPath)") }
        foreach ($e in $extra) { [void]$sb.AppendLine($e) }
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
    'dependabot' { Invoke-Dependabot }
}
