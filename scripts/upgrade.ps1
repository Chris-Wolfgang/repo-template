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

    "Identical" ignores the version comment after a SHA-pinned action (`@<sha> # v7` vs
    `@<sha> # v7.0.1`): same SHA is the same action. The template's comment is what -Apply writes.

    Only files the template owns are considered (workflows, analyzer config, scripts, hooks,
    license-audit and pip pins, docs/ guides). Files that are this repository's after setup -
    README, CONTRIBUTING, SECURITY, CODEOWNERS, docfx_project, LICENSE - are never compared.
    The few managed files that carry setup placeholders (BannedSymbols.txt, benchmarks.yaml)
    are compared and applied with the placeholders substituted from the values setup.ps1
    recorded in .template-version, so they still flow.

    Files the template has removed since the base are reported as "removed"; -Apply deletes
    them only when the local copy still equals the template's last version and nothing else in
    the repository (solution file, docs, workflows) still names the path.

    Without .template-version (a repository set up before stamping existed) every differing file
    is reported as review, since there is no base to tell "template moved" from "we customised".
    Pass -Since <template commit> to supply the base by hand; placeholder-bearing files then
    stay in review because there are no recorded values to substitute.

.PARAMETER Template
    owner/repo of the template. Default: the value stamped in .template-version, else
    Chris-Wolfgang/repo-template.
.PARAMETER Since
    Template commit to treat as the base instead of the stamped one.
.PARAMETER Apply
    Overwrite the files in the safe bucket with the template's current content and update
    .template-version. Review files still only get a <name>.template sidecar; an existing
    sidecar is never overwritten (finish or delete it first). Default is a dry run.
.PARAMETER Merge
    With -Apply: three-way merge each review file instead of only writing a sidecar - base is
    the template's version at the stamped commit, ours is this repository's file, theirs is the
    template's current file (`git merge-file`). A merge with no conflicts is written in place and
    reported as "merged"; a conflicting one is written to the <name>.template sidecar WITH the
    conflict markers, so the manual work left is exactly the conflicting hunks. Local changes
    that mirror the template's (a fan-out that landed the same edit here) merge cleanly. Needs a
    base (.template-version or -Since); without one review files get a plain sidecar as before.
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

    [Parameter()]
    [switch]$Merge,
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
$placeholders = @{}
if ($stamp -and $stamp.PSObject.Properties['placeholders'] -and $stamp.placeholders)
{
    foreach ($prop in $stamp.placeholders.PSObject.Properties) { $placeholders[$prop.Name] = [string]$prop.Value }
}

# Files the template owns. Anything else is the repository's after setup.
$managedPrefixes = @('.github/workflows/', '.github/license-audit/', '.github/requirements/', '.githooks/', 'scripts/')
$managedFiles = @('.editorconfig', '.globalconfig', 'BannedSymbols.txt', 'coverlet.runsettings', 'Directory.Build.props',
                  '.gitleaks.toml', '.gitattributes', '.gitignore', '.github/dependabot.yml', '.github/pull_request_template.md',
                  '.github/ISSUE_TEMPLATE/BUG_REPORT.yaml', '.github/ISSUE_TEMPLATE/feature_request.yaml',
                  '.github/ISSUE_TEMPLATE/maintenance-task.yaml', 'changelog/unreleased/README.md')
if ($IncludeDocs) { $managedPrefixes += 'docs/' }
# Template-only files that never belong in a generated repository, plus the one-time setup
# scripts that delete themselves after a successful run (their absence is expected).
$templateOnly = @('scripts/setup.ps1', 'scripts/audit-repos.ps1', 'scripts/upgrade.ps1', 'scripts/templates/', 'docs/repository-baseline.md',
                  'scripts/Setup-GitHubPages.ps1', 'scripts/Setup-Maintenance.ps1')
# Setup-BranchRuleset.ps1 self-deletes after its first run, but Fix-BranchRuleset.ps1 calls it
# again later, so a repository that still has it needs the current version: managed while
# present, never re-added once gone.
if (-not (Test-Path 'scripts/Setup-BranchRuleset.ps1')) { $templateOnly += 'scripts/Setup-BranchRuleset.ps1' }

function Test-Managed([string]$Path)
{
    if ($templateOnly | Where-Object { $Path -eq $_ -or $Path.StartsWith($_) }) { return $false }
    if ($Path -in $managedFiles) { return $true }
    foreach ($p in $managedPrefixes) { if ($Path.StartsWith($p)) { return $true } }
    return $false
}

function Get-TemplateFile([string]$Path, [string]$Ref)
{
    # Raw content at a ref; $null only when the file does not exist there (HTTP 404). Any other
    # failure (rate limit, auth, network) throws: treating it as "absent" would misclassify
    # files as new-in-template or skip them, and -Apply would then advance the stamp past them.
    $tmp = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    try
    {
        & gh api "repos/$Template/contents/${Path}?ref=${Ref}" -H 'Accept: application/vnd.github.raw' > $tmp 2> $errFile
        if ($LASTEXITCODE -ne 0)
        {
            $err = Get-Content $errFile -Raw -ErrorAction SilentlyContinue
            if ($err -match 'HTTP 404') { return $null }
            throw "gh api repos/$Template/contents/$Path@$Ref failed (exit $LASTEXITCODE): $err"
        }
        return [System.IO.File]::ReadAllText($tmp)
    }
    finally { Remove-Item $tmp, $errFile -Force -ErrorAction SilentlyContinue }
}

function Get-TemplateContent([string]$Path, [string]$Ref)
{
    # Template content with setup placeholders substituted from the stamp, normalised.
    $text = Get-TemplateFile $Path $Ref
    if ($null -eq $text) { return $null }
    foreach ($k in $placeholders.Keys) { $text = $text.Replace('{{' + $k + '}}', $placeholders[$k]) }
    return Get-Normalized $text
}

function Get-Normalized($Text)
{
    # Untyped on purpose: a [string] parameter turns $null (file absent at that ref) into ''.
    if ($null -eq $Text) { return $null }
    return ([string]$Text -replace "`r`n", "`n").TrimEnd("`n")
}

function Get-PathReferences([string]$Path)
{
    # Tracked files (other than the file itself) whose text mentions the path. git grep exits
    # 1 for "no match"; anything else is an error and fails closed - an unknown answer must not
    # turn into "unreferenced, safe to delete".
    $errFile = [System.IO.Path]::GetTempFileName()
    try
    {
        $hits = & git grep -l -F -- $Path 2> $errFile
        if ($LASTEXITCODE -gt 1) { throw "git grep failed while checking references to ${Path}: $(Get-Content $errFile -Raw)" }
    }
    finally { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }
    return @($hits | Where-Object { $_ -and $_ -ne $Path })
}

function Get-CompareKey($Text)
{
    # Equality is decided on this key, never on the raw text. The one thing it hides is the
    # version comment Dependabot writes after a SHA-pinned action (`@<sha> # v7` here vs
    # `@<sha>  # v7.0.1` upstream): same SHA is the same action, and the template's
    # full-precision comment is what gets written when the file is applied.
    if ($null -eq $Text) { return $null }
    return [regex]::Replace([string]$Text, '(@[0-9a-f]{40})[ \t]*#[ \t]*v?\d[^\n]*', '$1')
}

$head = (& gh api "repos/$Template/commits/main" --jq '.sha')
if ($LASTEXITCODE -ne 0 -or -not $head) { throw "could not read $Template main" }
Write-Host "Template: $Template @ $($head.Substring(0, 7))" -ForegroundColor Cyan
Write-Host "Base:     $(if ($base) { $base.Substring(0, [Math]::Min(7, $base.Length)) + ' (' + $(if ($Since) { '-Since' } else { '.template-version' }) + ')' } else { 'none - no .template-version; every difference is reported as review' })" -ForegroundColor Cyan
Write-Host ''

$executableInTemplate = @{}   # path -> $true when the template HEAD tree marks it 100755

function Get-ManagedPaths([string]$Ref, [switch]$RecordModes)
{
    # Modes are recorded for the head tree only: what -Apply writes is head content, so
    # head's mode is the only one that matters (a file that was +x at the base but not
    # at head must not come back executable).
    $tree = (& gh api "repos/$Template/git/trees/${Ref}?recursive=1" --jq '.tree[] | select(.type == "blob") | "\(.mode) \(.path)"')
    if ($LASTEXITCODE -ne 0) { throw "could not list $Template tree at $Ref" }
    $paths = @()
    foreach ($line in $tree)
    {
        $mode, $path = $line -split ' ', 2
        if (-not (Test-Managed $path)) { continue }
        if ($RecordModes -and $mode -eq '100755') { $executableInTemplate[$path] = $true }
        $paths += $path
    }
    return $paths
}

# Candidate files: everything managed at the template head, plus anything managed at the
# base that the template has since removed (so deletions are reported, not silently kept).
$headPaths = Get-ManagedPaths $head -RecordModes
$basePaths = if ($base) { Get-ManagedPaths $base } else { @() }
$candidates = @($headPaths + $basePaths | Sort-Object -Unique)

$safe = @(); $review = @(); $inSync = @(); $missing = @(); $removed = @()
foreach ($path in $candidates)
{
    $templateNow = if ($path -in $headPaths) { Get-TemplateContent $path $head } else { $null }
    $local = if (Test-Path $path) { Get-Normalized ([System.IO.File]::ReadAllText($path)) } else { $null }

    if ($null -eq $templateNow)
    {
        # Removed from the template since the base. Deleting is safe only when the local copy
        # is still exactly what the template last shipped AND nothing else in the repository
        # names it (a solution file, a doc, a workflow); otherwise leave it for a human.
        if ($null -eq $local) { continue }
        $templateThen = Get-TemplateContent $path $base
        $unmodified = $null -ne $templateThen -and (Get-CompareKey $local) -eq (Get-CompareKey $templateThen)
        $refs = @(Get-PathReferences $path)
        $removed += [pscustomobject]@{ Path = $path; Safe = ($unmodified -and $refs.Count -eq 0); References = $refs }
        continue
    }

    if ($null -eq $local)
    {
        # New in the template since setup, or deliberately deleted here. New-in-template is
        # safe to add when the base did not have it either; otherwise it is a local deletion.
        # A new file that still carries {{PLACEHOLDERS}} (no values in the stamp) is not safe:
        # it would land verbatim, so it goes to review instead.
        $templateThen = if ($base) { Get-TemplateContent $path $base } else { $null }
        if ($base -and $null -eq $templateThen)
        {
            if ($templateNow -match '\{\{[A-Z_]+\}\}') { $review += [pscustomobject]@{ Path = $path; Content = $templateNow; Reason = 'new in template but carries setup placeholders and .template-version has no values - fill placeholders in .template-version, or merge by hand' } }
            else { $safe += [pscustomobject]@{ Path = $path; Reason = 'new in template'; Content = $templateNow } }
        }
        else { $missing += $path }
        continue
    }
    if ((Get-CompareKey $local) -eq (Get-CompareKey $templateNow)) { $inSync += $path; continue }

    $templateThen = if ($base) { Get-TemplateContent $path $base } else { $null }
    if ($base -and $null -ne $templateThen -and (Get-CompareKey $local) -eq (Get-CompareKey $templateThen))
    {
        $safe += [pscustomobject]@{ Path = $path; Reason = 'template changed, local untouched since setup'; Content = $templateNow }
    }
    else
    {
        $review += [pscustomobject]@{ Path = $path; Content = $templateNow; Base = $templateThen; Reason = $(if ($base) { 'changed in both the template and this repository' } else { 'differs from the template (no base to compare)' }) }
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
if ($removed.Count -gt 0)
{
    Write-Host "Removed : $($removed.Count) file(s) no longer in the template$(if (-not $Apply) { ' - -Apply deletes the unmodified ones' })" -ForegroundColor Yellow
    foreach ($d in $removed)
    {
        $why = if ($d.Safe) { 'unmodified since setup; deleted by -Apply' }
               elseif ($d.References.Count -gt 0) { "still referenced by $($d.References -join ', '); update those, then delete by hand" }
               else { 'modified locally; delete by hand' }
        Write-Host "    $($d.Path)  ($why)"
    }
}

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
    if ($executableInTemplate[$s.Path])
    {
        # Set-Content cannot carry a mode and Windows checkouts have core.fileMode off, so the
        # template's +x (git hooks) would be committed as 100644 and never run on Linux/macOS.
        $chmodOut = & git update-index --add --chmod=+x -- $s.Path 2>&1
        if ($LASTEXITCODE -ne 0) { throw "could not mark $($s.Path) executable: $chmodOut" }
    }
    Write-Host "  applied  $($s.Path)" -ForegroundColor Green
}
$mergedClean = 0; $mergedConflict = 0
foreach ($r in $review)
{
    $sidecar = "$($r.Path).template"
    if (Test-Path $sidecar)
    {
        # A sidecar from an earlier run may hold half-finished merge work; never clobber it.
        Write-Host "  kept     $sidecar (already exists - finish or delete it, then re-run)" -ForegroundColor Yellow
        continue
    }
    if ($Merge -and $r.PSObject.Properties['Base'] -and $null -ne $r.Base)
    {
        # Three-way merge: ours = local, base = template at the stamp, theirs = template now.
        # git merge-file exits with the number of conflicts (0 = clean), negative on error.
        $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("upgrade-merge-" + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $tmp | Out-Null
        try
        {
            $ours = Join-Path $tmp 'ours'; $baseFile = Join-Path $tmp 'base'; $theirs = Join-Path $tmp 'theirs'
            [System.IO.File]::WriteAllText($ours, ([System.IO.File]::ReadAllText($r.Path) -replace "`r`n", "`n"))
            [System.IO.File]::WriteAllText($baseFile, $r.Base + "`n")
            [System.IO.File]::WriteAllText($theirs, $r.Content + "`n")
            $merged = & git merge-file -p -L "this repository" -L "template $($base.Substring(0, 7))" -L "template $($head.Substring(0, 7))" $ours $baseFile $theirs 2>&1
            $conflicts = $LASTEXITCODE
            if ($conflicts -lt 0) { throw "git merge-file failed for $($r.Path): $($merged -join ' ')" }
            $text = ($merged -join "`n") + "`n"
            if ($conflicts -eq 0)
            {
                Set-Content -Path $r.Path -Value $text -Encoding utf8NoBOM -NoNewline
                Write-Host "  merged   $($r.Path) (three-way, no conflicts)" -ForegroundColor Green
                $mergedClean++
            }
            else
            {
                Set-Content -Path $sidecar -Value $text -Encoding utf8NoBOM -NoNewline
                Write-Host "  conflict $sidecar ($conflicts conflicting hunk(s) marked; resolve, then move over $($r.Path))" -ForegroundColor Yellow
                $mergedConflict++
            }
        }
        finally { Remove-Item -Path $tmp -Recurse -Force -ErrorAction SilentlyContinue }
        continue
    }
    Set-Content -Path $sidecar -Value ($r.Content + "`n") -Encoding utf8NoBOM -NoNewline
    Write-Host "  sidecar  $sidecar" -ForegroundColor Yellow
}
if ($Merge) { Write-Host "  three-way merge: $mergedClean clean, $mergedConflict with conflicts" -ForegroundColor $(if ($mergedConflict) { 'Yellow' } else { 'Green' }) }
foreach ($d in $removed)
{
    if ($d.Safe) { Remove-Item -Path $d.Path -Force; Write-Host "  removed  $($d.Path)" -ForegroundColor Green }
    else { Write-Host "  left     $($d.Path) ($(if ($d.References.Count -gt 0) { "still referenced by $($d.References -join ', ')" } else { 'modified locally' }); template removed it)" -ForegroundColor Yellow }
}

$newStamp = [ordered]@{
    template     = $Template
    commit       = $head
    updated      = (Get-Date).ToString('yyyy-MM-dd')
    placeholders = $(if ($placeholders.Count) { [ordered]@{} + $placeholders } else { $null })
    note         = 'Written by scripts/setup.ps1 and scripts/upgrade.ps1; the template commit this repository last took template-managed files from, and the placeholder values setup used.'
}
$newStamp | ConvertTo-Json | Set-Content -Path $stampPath -Encoding utf8NoBOM
Write-Host ''
Write-Host "Stamped $stampPath at $($head.Substring(0, 7)). Review the diff, resolve any *.template sidecars, and open a PR." -ForegroundColor Cyan
if ($review.Count -gt 0 -and -not $Merge) { Write-Host 'Delete each .template sidecar once merged; do not commit them.' -ForegroundColor Yellow }
if ($Merge -and $mergedConflict -gt 0) { Write-Host 'Resolve the <<<<<<< hunks in each .template sidecar, move it over the file, delete the sidecar; do not commit sidecars.' -ForegroundColor Yellow }
