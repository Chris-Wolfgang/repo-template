#!/usr/bin/env pwsh
#Requires -Version 7.0
<#
.SYNOPSIS
    Pins every `uses:` in .github/workflows to a commit SHA with an exact `# vMAJOR.MINOR.PATCH` comment.

.DESCRIPTION
    Two drifts recur fleet-wide (repo-template#447, baseline item 11):

      - a SHA-pinned action whose trailing comment names only the major (`@<sha> # v7`), which
        zizmor's ref-version-mismatch flags as soon as the vMAJOR tag moves on; and
      - an action still referenced by tag (`@v7`), which is not pinned at all.

    For each `uses: owner/repo[/path]@ref` the script asks the action's repository for its tags
    (one `git ls-remote --tags` per action, annotated tags peeled, no API budget) and:

      - ref is a 40-hex SHA  -> comment becomes the most specific tag that points at that commit
                                (v7.0.1 over v7.0 over v7). No tag -> left alone, reported.
      - ref is a tag         -> with -PinTags, rewritten to `@<commit sha> # <exact tag>`; the exact
                                tag is again the most specific one on that commit. Without -PinTags,
                                reported only.
      - ref is a branch, `./local`, `docker://` -> skipped.

    Only the ref/comment text changes; everything else on the line is preserved. Dependabot keeps
    whatever precision the comment already has, so once a repository is converted it stays converted.

.PARAMETER Path
    Repository root. Default: current directory.
.PARAMETER Apply
    Write the changes. Default is a dry run that prints every line it would change.
.PARAMETER PinTags
    Also convert tag references to SHA pins. Off by default so a comment-only pass stays comment-only.

.EXAMPLE
    pwsh ./scripts/pin-actions.ps1
.EXAMPLE
    pwsh ./scripts/pin-actions.ps1 -PinTags -Apply
.NOTES
    Workflow files are protected by pr.yaml's Detect .NET Projects guard: the resulting PR needs
    the admin bypass. Requires git; gh is not used.
#>
[CmdletBinding()]
param
(
    [string]$Path = '.',
    [switch]$Apply,
    [switch]$PinTags
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# The value may be quoted ('actions/checkout@v7' or "..."); the quote is captured and put back.
$usesRe = [regex]'^(?<lead>\s*-?\s*uses:\s*)(?<q>["'']?)(?<action>[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+(?:/[^@\s"'']+)?)@(?<ref>[^\s#"'']+)\k<q>(?<gap>[ \t]*)(?:#[ \t]*(?<comment>[^\r\n]*))?(?<eol>\r?)$'
$tagCache = @{}

function Get-ActionTags([string]$Repo)
{
    # @{ '<commit sha>' = @('v7.0.1','v7.0','v7') } for the action's repository, annotated tags peeled.
    if ($tagCache.ContainsKey($Repo)) { return $tagCache[$Repo] }
    $errFile = [System.IO.Path]::GetTempFileName()
    try
    {
        $lines = & git ls-remote --tags "https://github.com/$Repo" 2> $errFile
        if ($LASTEXITCODE -ne 0) { throw "git ls-remote failed for ${Repo}: $(Get-Content $errFile -Raw)" }
    }
    finally { Remove-Item $errFile -Force -ErrorAction SilentlyContinue }

    $byTag = @{}   # tag -> commit sha (peeled entry wins over the annotated tag object)
    foreach ($l in $lines)
    {
        if ($l -notmatch '^([0-9a-f]{40})\s+refs/tags/(\S+?)(\^\{\})?$') { continue }
        $sha, $tag, $peeled = $Matches[1], $Matches[2], [bool]$Matches[3]
        if ($peeled -or -not $byTag.ContainsKey($tag)) { $byTag[$tag] = $sha }
    }
    $byCommit = @{}
    foreach ($kv in $byTag.GetEnumerator())
    {
        if (-not $byCommit.ContainsKey($kv.Value)) { $byCommit[$kv.Value] = @() }
        $byCommit[$kv.Value] += $kv.Key
    }
    $tagCache[$Repo] = $byCommit
    return $byCommit
}

function Select-ExactTag([string[]]$Tags)
{
    # Most specific semver-looking tag: more dots first, then a 'v' prefix, then plain sort.
    $ranked = $Tags |
        Where-Object { $_ -match '^v?\d+(\.\d+)*(-[\w.]+)?$' } |
        Sort-Object -Property @{ Expression = { ($_ -split '\.').Count }; Descending = $true },
                              @{ Expression = { $_.StartsWith('v') }; Descending = $true },
                              @{ Expression = { $_ } }
    return ($ranked | Select-Object -First 1)
}

$root = (Resolve-Path $Path).Path
$files = @(Get-ChildItem -Path (Join-Path $root '.github/workflows') -File -Include '*.yml', '*.yaml' -Recurse -ErrorAction SilentlyContinue)
if ($files.Count -eq 0) { Write-Host 'no workflow files'; exit 0 }

$changed = 0; $unpinned = 0; $untagged = 0; $ok = 0
foreach ($f in $files)
{
    $text = [System.IO.File]::ReadAllText($f.FullName)
    $lines = $text -split '(?<=\n)'
    $fileChanged = $false
    for ($i = 0; $i -lt $lines.Count; $i++)
    {
        $m = $usesRe.Match($lines[$i].TrimEnd("`n"))
        if (-not $m.Success) { continue }
        $action = $m.Groups['action'].Value
        $ref = $m.Groups['ref'].Value
        $comment = $m.Groups['comment'].Value.Trim()
        $rel = $f.FullName.Substring($root.Length + 1).Replace('\', '/')
        if ($action.StartsWith('./') -or $action.StartsWith('docker://')) { continue }
        $repo = ($action -split '/')[0..1] -join '/'
        $tags = Get-ActionTags $repo

        $newRef = $ref; $newComment = $comment
        if ($ref -match '^[0-9a-f]{40}$')
        {
            if (-not $tags.ContainsKey($ref)) { Write-Host "  ?  ${rel}: $action@$($ref.Substring(0,7)) has no tag on that commit (comment '$comment' kept)" -ForegroundColor DarkYellow; $untagged++; continue }
            $exact = Select-ExactTag $tags[$ref]
            if (-not $exact) { $untagged++; continue }
            $newComment = $exact
        }
        else
        {
            # A tag (or branch) reference: find the commit it points at.
            $hit = $tags.GetEnumerator() | Where-Object { $_.Value -contains $ref } | Select-Object -First 1
            if (-not $hit) { Write-Host "  ?  ${rel}: $action@$ref is not a tag (branch?) - skipped" -ForegroundColor DarkYellow; continue }
            $unpinned++
            if (-not $PinTags) { Write-Host "  !  ${rel}: $action@$ref is a tag reference (use -PinTags)" -ForegroundColor Yellow; continue }
            $newRef = $hit.Key
            $newComment = Select-ExactTag $tags[$hit.Key]
        }

        if ($newRef -eq $ref -and $newComment -eq $comment) { $ok++; continue }
        $q = $m.Groups['q'].Value
        $newLine = "$($m.Groups['lead'].Value)$q$action@$newRef$q # $newComment$($m.Groups['eol'].Value)" + $(if ($lines[$i].EndsWith("`n")) { "`n" } else { '' })
        Write-Host "  ~  ${rel}: $action@$(if ($ref.Length -eq 40) { $ref.Substring(0,7) } else { $ref }) # $(if ($comment) { $comment } else { '(none)' })  ->  @$($newRef.Substring(0,7)) # $newComment" -ForegroundColor Cyan
        $lines[$i] = $newLine
        $fileChanged = $true
        $changed++
    }
    if ($fileChanged -and $Apply)
    {
        [System.IO.File]::WriteAllText($f.FullName, ($lines -join ''), [System.Text.UTF8Encoding]::new($false))
    }
}

Write-Host ''
Write-Host "$ok already exact, $changed line(s) $(if ($Apply) { 'rewritten' } else { 'would change' }), $unpinned tag reference(s)$(if (-not $PinTags -and $unpinned) { ' left (no -PinTags)' }), $untagged pinned SHA(s) with no tag" -ForegroundColor $(if ($changed -or ($unpinned -and -not $PinTags)) { 'Yellow' } else { 'Green' })
if (-not $Apply -and $changed) { Write-Host 'Dry run - nothing written. Re-run with -Apply.' -ForegroundColor Cyan }
