#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Rebases a stack of pull-request branches after the bottom PR was squash- or rebase-merged.
.DESCRIPTION
    With "require linear history" every PR is squash- or rebase-merged, which puts NEW commits on the
    base branch. The next PR in a stack still carries the merged PR's ORIGINAL commits, so GitHub's
    "Update branch" replays those too and often conflicts. This script replays only each PR's own
    commits, bottom to top:

        git rebase --onto <new base> <old cut point> <branch>
        git push --force-with-lease=<branch>:<old tip> origin <branch>

    The cut point for the first branch is the merged PR's head SHA (detected from the most recently
    merged PR whose head is an ancestor of that branch, or given with -MergedTip). For every later
    branch it is the previous branch's tip as it was BEFORE this run.

    Only feature branches are force-pushed, each with an explicit lease, so a concurrent push is
    refused rather than overwritten. The base branch is never touched. After each push the PR's base
    on GitHub is verified and corrected (main for the first branch, the previous branch for the rest).

    Run it from a clone of the repository. Stops at the first rebase conflict with instructions.
.PARAMETER Stack
    Branch names in merge order, bottom first: the next PR to merge, then the one stacked on it, etc.
    Comma-separated or repeated.
.PARAMETER Base
    The branch the bottom PR merges into. Default main.
.PARAMETER MergedTip
    Head SHA of the PR that was just merged (its branch is usually already deleted). Detected via gh
    when omitted.
.PARAMETER Remote
    Default origin.
.PARAMETER DryRun
    Print the plan and exit without rebasing or pushing.
.EXAMPLE
    pwsh ./scripts/restack.ps1 -Stack feat/pick-list,feat/pick-confirm
    After squash-merging the PR below feat/pick-list: rebases feat/pick-list onto main, then
    feat/pick-confirm onto the new feat/pick-list, and pushes both.
.EXAMPLE
    pwsh ./scripts/restack.ps1 -Stack feat/b,feat/c -MergedTip 3f2a9c1 -DryRun
#>

[CmdletBinding()]
param
(
    [Parameter(Mandatory)]
    [string[]]$Stack,
    [string]$Base = 'main',
    [string]$MergedTip,
    [string]$Remote = 'origin',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$Stack = @($Stack | ForEach-Object { $_ -split ',' } | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($Stack.Count -eq 0) { throw 'Stack is empty' }



function Invoke-Git
{
    param([string[]]$Arguments, [switch]$AllowFailure)

    $out = & git @Arguments 2>&1
    if ($LASTEXITCODE -ne 0 -and -not $AllowFailure) { throw "git $($Arguments -join ' ') failed:`n$($out | Out-String)" }
    return ($out | Out-String).Trim()
}



function Get-Sha
{
    param([string]$Ref)

    return Invoke-Git @('rev-parse', '--verify', '--quiet', "$Ref^{commit}")
}



function Test-Ancestor
{
    param([string]$Ancestor, [string]$Descendant)

    & git merge-base --is-ancestor $Ancestor $Descendant 2>$null
    return $LASTEXITCODE -eq 0
}



function Find-MergedTip
{
    # The most recently merged PR whose head commit is an ancestor of the bottom branch.
    param([string]$Bottom)

    $raw = & gh pr list --state merged --base $Base --limit 30 --json number,headRefOid,headRefName,mergedAt 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh pr list failed (pass -MergedTip instead): $raw" }
    $prs = @(($raw | Out-String) | ConvertFrom-Json) | Sort-Object mergedAt -Descending
    foreach ($pr in $prs)
    {
        if (Test-Ancestor $pr.headRefOid $Bottom)
        {
            Write-Host "merged PR #$($pr.number) ($($pr.headRefName)) head $($pr.headRefOid.Substring(0, 10)) is the cut point for $Bottom"
            return $pr.headRefOid
        }
    }
    throw "no recently merged PR into $Base has a head commit in $Bottom's history; pass -MergedTip <sha>"
}



function Set-PrBase
{
    param([string]$Branch, [string]$ExpectedBase)

    $raw = & gh pr list --head $Branch --state open --json number,baseRefName 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warning "could not read PR for ${Branch}: $raw"; return }
    $pr = @(($raw | Out-String) | ConvertFrom-Json) | Select-Object -First 1
    if (-not $pr) { Write-Host "  no open PR for $Branch"; return }
    if ($pr.baseRefName -eq $ExpectedBase) { Write-Host "  PR #$($pr.number) base is $ExpectedBase"; return }
    if ($DryRun) { Write-Host "  DRY-RUN would retarget PR #$($pr.number) from $($pr.baseRefName) to $ExpectedBase"; return }
    & gh pr edit $pr.number --base $ExpectedBase | Out-Null
    Write-Host "  PR #$($pr.number) retargeted $($pr.baseRefName) -> $ExpectedBase"
}

# ---------------------------------------------------------------------------
if (Invoke-Git @('status', '--porcelain')) { throw 'working tree is not clean; commit or stash first' }
Invoke-Git @('fetch', '--prune', $Remote) | Out-Null

foreach ($b in $Stack) { if (-not (Get-Sha "$Remote/$b")) { throw "branch $b not found on $Remote" } }

# Snapshot every branch's tip BEFORE anything moves; these are the cut points and the push leases.
$oldTip = @{}
foreach ($b in $Stack) { $oldTip[$b] = Get-Sha "$Remote/$b" }

if (-not $MergedTip) { $MergedTip = Find-MergedTip "$Remote/$($Stack[0])" }
$MergedTip = Get-Sha $MergedTip
if (-not (Test-Ancestor $MergedTip "$Remote/$($Stack[0])")) { throw "MergedTip $MergedTip is not in $($Stack[0])'s history" }

Write-Host ''
Write-Host "Plan (base $Base):"
$cut = $MergedTip; $onto = "$Remote/$Base"
foreach ($b in $Stack)
{
    $own = (Invoke-Git @('rev-list', '--count', "$cut..$($oldTip[$b])"))
    Write-Host ("  {0,-40} replay {1,3} commit(s) after {2} onto {3}" -f $b, $own, $cut.Substring(0, 10), $onto)
    $cut = $oldTip[$b]; $onto = $b
}
if ($DryRun) { Write-Host ''; Write-Host 'dry run: nothing changed'; exit 0 }

$current = Invoke-Git @('branch', '--show-current')
$cut = $MergedTip; $onto = "$Remote/$Base"; $prBase = $Base
try
{
    foreach ($b in $Stack)
    {
        Write-Host ''
        Write-Host "== $b"
        Invoke-Git @('checkout', '--quiet', '-B', $b, $oldTip[$b]) | Out-Null
        $out = & git rebase --onto $onto $cut $b 2>&1
        if ($LASTEXITCODE -ne 0)
        {
            Write-Host ($out | Out-String)
            Write-Host "::error::rebase of $b stopped on a conflict."
            Write-Host "Resolve it, run 'git rebase --continue' until it finishes, push with"
            Write-Host "  git push --force-with-lease=${b}:$($oldTip[$b]) $Remote $b"
            Write-Host "then re-run this script with the remaining branches: -Stack $((@($Stack) | Select-Object -Skip ([array]::IndexOf($Stack, $b) + 1)) -join ',') -MergedTip $($oldTip[$b])"
            exit 1
        }
        $newTip = Get-Sha $b
        if ($newTip -eq $oldTip[$b]) { Write-Host "  already up to date" }
        else
        {
            Invoke-Git @('push', "--force-with-lease=${b}:$($oldTip[$b])", $Remote, $b) | Out-Null
            Write-Host "  pushed $($oldTip[$b].Substring(0, 10)) -> $($newTip.Substring(0, 10))"
        }
        Set-PrBase $b $prBase
        $cut = $oldTip[$b]; $onto = $b; $prBase = $b
    }
}
finally
{
    if ($current) { & git checkout --quiet $current 2>$null }
}
Write-Host ''
Write-Host "restacked $($Stack.Count) branch(es); merge $($Stack[0]) next, then run again with -Stack $((@($Stack) | Select-Object -Skip 1) -join ',')"
