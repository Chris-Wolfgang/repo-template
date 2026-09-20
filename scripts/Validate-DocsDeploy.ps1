#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Validates the gh-pages branch contents after a DocFX deployment.

.DESCRIPTION
    Checks that the root of origin/gh-pages contains index.html, versions.json and
    .nojekyll, that versions.json is correctly structured, that every referenced
    version folder exists with an index.html, and that no known stale DocFX root
    artifacts remain.

    Inspects a detached temporary worktree of origin/gh-pages so it validates what
    is actually deployed, not a stale local branch.

.EXAMPLE
    pwsh ./scripts/Validate-DocsDeploy.ps1

.NOTES
    Requirements: git. Exit code 1 when any check fails.
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$script:Pass = 0
$script:Fail = 0

function Write-Pass { param([string]$Message) Write-Host "  ✅ $Message"; $script:Pass++ }
function Write-Fail { param([string]$Message) Write-Host "  ❌ $Message"; $script:Fail++ }

# realpath equivalent: walk the path from the root and, whenever a segment is a
# symlink/junction, continue from its resolved target - so a link anywhere in
# the chain cannot smuggle a path outside the tree past a textual prefix check.
# Segments that do not exist yet are appended textually (the caller checks
# existence separately).
function Resolve-RealPath {
    param([string]$Path)
    $full = [System.IO.Path]::GetFullPath($Path)
    $root = [System.IO.Path]::GetPathRoot($full)
    $current = $root
    foreach ($segment in $full.Substring($root.Length) -split '[\\/]' | Where-Object { $_ }) {
        $current = Join-Path $current $segment
        if (-not (Test-Path -LiteralPath $current)) { continue }
        $item = Get-Item -LiteralPath $current -Force
        if ($item.LinkType) {
            $target = $item.ResolveLinkTarget($true)
            if (-not $target) { return '<unresolvable link>' }
            $current = $target.FullName
        }
    }
    return $current
}
function Write-Warn { param([string]$Message) Write-Host "  ⚠️  $Message" }
function Write-Skip { param([string]$Message) Write-Host "  ⏭️  $Message" }

# Case-SENSITIVE property read. PowerShell's `$obj.name` is case-insensitive,
# but the browser consumer (docfx_project/public/version-picker.js) reads
# `v.version` / `v.url` exactly, so `"Version"` / `"URL"` would pass a naive
# check here and still be ignored by the picker.
function Get-ExactProperty {
    param([object]$Object, [string]$Name)
    $prop = $Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1
    if ($prop) { return $prop.Value }
    return $null
}

function Write-Summary {
    Write-Host ""
    Write-Host "────────────────────────────────────────────────────────"
    Write-Host "  Results: $script:Pass passed, $script:Fail failed"
    Write-Host "────────────────────────────────────────────────────────"
    Write-Host ""
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗"
Write-Host "║        DocFX Deployment Validation                   ║"
Write-Host "╚══════════════════════════════════════════════════════╝"
Write-Host ""

# ------------------------------------------------------------------
# 1. Verify the gh-pages branch exists on the remote
# ------------------------------------------------------------------
Write-Host "1. Checking gh-pages branch..."
$lsRemote = git ls-remote --heads origin gh-pages 2>&1
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Could not query 'origin' for the gh-pages branch - git ls-remote exited $LASTEXITCODE"
    Write-Host "    $lsRemote"
    Write-Summary
    exit 1
}
if (-not ($lsRemote -match 'gh-pages')) {
    Write-Fail "gh-pages branch does not exist on remote"
    Write-Summary
    exit 1
}
Write-Pass "gh-pages branch exists on remote"

# ------------------------------------------------------------------
# 2. Set up a temporary worktree to inspect the branch contents
# ------------------------------------------------------------------
# Reserve a unique path that does NOT exist at the moment of worktree-add
# (git errors with "already exists" otherwise).
$workDir = Join-Path ([System.IO.Path]::GetTempPath()) ("gh-pages-validate." + [System.IO.Path]::GetRandomFileName())

try {
    # Always fetch the latest gh-pages from origin so we validate what's actually
    # deployed. A detached worktree on origin/gh-pages neither depends on nor
    # updates any local gh-pages branch the caller might have.
    git fetch origin gh-pages
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to fetch origin gh-pages"
        Write-Summary
        exit 1
    }
    git worktree add --detach $workDir origin/gh-pages
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Failed to create a worktree for origin/gh-pages"
        Write-Summary
        exit 1
    }

    Write-Host ""
    Write-Host "2. Checking required root files..."

    if (Test-Path (Join-Path $workDir 'index.html') -PathType Leaf) {
        Write-Pass "index.html exists at root"
    }
    else {
        Write-Fail "index.html is MISSING from root"
    }

    $versionsPath = Join-Path $workDir 'versions.json'
    if (Test-Path $versionsPath -PathType Leaf) {
        Write-Pass "versions.json exists at root"
    }
    else {
        Write-Fail "versions.json is MISSING from root (version picker will not work)"
    }

    if (Test-Path (Join-Path $workDir '.nojekyll') -PathType Leaf) {
        Write-Pass ".nojekyll exists (Jekyll processing disabled)"
    }
    else {
        # The canonical DocFX deploy workflow always creates .nojekyll; missing
        # means the deploy was botched, not a soft warning.
        Write-Fail ".nojekyll is MISSING from root (GitHub Pages will apply Jekyll processing)"
    }

    # ------------------------------------------------------------------
    # 3. Validate versions.json structure
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host "3. Validating versions.json..."

    $versions = $null
    $step3Ok = $false
    if (Test-Path $versionsPath -PathType Leaf) {
        $problem = $null
        try {
            # -NoEnumerate keeps a one-element array an array instead of unwrapping it.
            $versions = Get-Content $versionsPath -Raw | ConvertFrom-Json -NoEnumerate
        }
        catch {
            $problem = "versions.json is not valid JSON: $($_.Exception.Message)"
        }

        if (-not $problem -and $versions -isnot [System.Array]) {
            $problem = "versions.json must be a JSON array"
        }
        if (-not $problem) {
            for ($i = 0; $i -lt $versions.Count -and -not $problem; $i++) {
                $entry = $versions[$i]
                if ($entry -isnot [System.Management.Automation.PSCustomObject]) {
                    $problem = "Entry [$i] is not a JSON object: $($entry | ConvertTo-Json -Compress)"
                }
                elseif ((Get-ExactProperty $entry 'version') -isnot [string] -or -not (Get-ExactProperty $entry 'version')) {
                    $problem = "Entry [$i] has missing or non-string 'version' (exact, lower-case key): $($entry | ConvertTo-Json -Compress)"
                }
                elseif ((Get-ExactProperty $entry 'url') -isnot [string] -or -not (Get-ExactProperty $entry 'url')) {
                    $problem = "Entry [$i] has missing or non-string 'url' (exact, lower-case key): $($entry | ConvertTo-Json -Compress)"
                }
            }
        }

        if ($problem) {
            Write-Fail $problem
        }
        else {
            Write-Pass "versions.json is valid ($($versions.Count) version(s))"
            foreach ($v in $versions) {
                Write-Host ("       {0,-20}  ->  {1}" -f (Get-ExactProperty $v 'version'), (Get-ExactProperty $v 'url'))
            }
            $step3Ok = $true
        }
    }

    # ------------------------------------------------------------------
    # 4. Verify every version entry has a matching folder with index.html
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host "4. Checking version folders match versions.json..."

    # Derive the repository name from the origin remote URL so the project-Pages
    # prefix ('/<repo>/') can be stripped from versions.json URLs before mapping
    # them to folders under gh-pages. A user/org root Pages site has no prefix.
    # Handles HTTPS (https://github.com/owner/repo) and SSH (git@github.com:owner/repo).
    $repoName = ''
    $repoUrl = git remote get-url origin 2>$null
    if ($repoUrl) {
        $repoUrl = $repoUrl -replace '\.git$', ''
        $repoName = ($repoUrl -split '[/:]')[-1]
    }

    if (-not (Test-Path $versionsPath -PathType Leaf)) {
        Write-Skip "Skipped - no versions.json present (step 3 did not run)"
    }
    elseif (-not $step3Ok) {
        Write-Skip "Skipped - versions.json failed validation in step 3"
    }
    else {
        $realRoot = [System.IO.Path]::GetFullPath($workDir)
        $missing = @()
        foreach ($v in $versions) {
            $ver = Get-ExactProperty $v 'version'
            $url = Get-ExactProperty $v 'url'
            if (-not $url -or $url -eq '/') {
                # Root-level alias (typically 'latest' on a user/org Pages site);
                # the root index.html is already validated in step 2.
                continue
            }
            if ($repoName -and $url.StartsWith("/$repoName/")) {
                $url = $url.Substring("/$repoName/".Length)
            }
            $folderName = $url.Trim('/')
            if (-not $folderName) { continue }

            # Reject anything that could escape the gh-pages root via parent-dir
            # traversal, backslash injection or absolute paths - defence against a
            # malformed (or hostile) versions.json on the deployed site.
            $parts = $folderName -split '/'
            if ($parts | Where-Object { $_ -in @('', '..', '.') -or $_.Contains('\') }) {
                $missing += "$ver  (url '$url' would escape gh-pages root - rejected)"
                continue
            }
            $folder = Join-Path $workDir $folderName
            # Belt-and-braces: the resolved full path must still be under the root.
            # GetFullPath only normalises text; a symlink/junction committed to
            # gh-pages - as the final segment OR anywhere above it - could still
            # point outside the worktree, so canonicalise segment by segment
            # before comparing (the .sh used realpath for this).
            $realFolder = Resolve-RealPath $folder
            # Match the comparison to the filesystem, not the OS: Windows is case-insensitive,
            # Linux is not, macOS is either (APFS/HFS+ default insensitive). Probe the worktree
            # root itself - if its upper-cased path resolves, the volume ignores case.
            $cmp = if (Test-Path -LiteralPath $realRoot.ToUpperInvariant()) { [System.StringComparison]::OrdinalIgnoreCase } else { [System.StringComparison]::Ordinal }
            if (-not $realFolder.StartsWith($realRoot + [System.IO.Path]::DirectorySeparatorChar, $cmp)) {
                $missing += "$ver  (resolved path '$realFolder' is outside gh-pages root - rejected)"
                continue
            }
            if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
                $missing += "$ver  (folder '$folderName/' not found)"
            }
            elseif (-not (Test-Path -LiteralPath (Join-Path $folder 'index.html') -PathType Leaf)) {
                $missing += "$ver  (index.html missing in '$folderName/')"
            }
        }

        if ($missing.Count -gt 0) {
            foreach ($m in $missing) { Write-Host "  ❌ $m" }
            $script:Fail++
        }
        else {
            Write-Pass "All versioned folders exist and contain index.html"
        }
    }

    # ------------------------------------------------------------------
    # 5. Check for known stale DocFX root artifacts
    # ------------------------------------------------------------------
    Write-Host ""
    Write-Host "5. Checking for stale DocFX root artifacts..."

    # 'public/' is a DocFX build artifact that should never appear at the
    # gh-pages root; its presence means a previous deploy did not clean up.
    # A hard failure (the .sh this replaced only warned): a botched deploy
    # must not validate as good.
    $stalePatterns = @('public')
    $foundStale = $false
    foreach ($p in $stalePatterns) {
        if (Test-Path (Join-Path $workDir $p)) {
            Write-Fail "Stale DocFX artifact at the gh-pages root: '$p' - a previous deploy did not clean up"
            $foundStale = $true
        }
    }
    if (-not $foundStale) {
        Write-Pass "No known stale DocFX artifacts found at root"
    }
}
finally {
    git worktree remove $workDir --force 2>$null | Out-Null
    if (Test-Path $workDir) {
        Remove-Item $workDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
Write-Summary

if ($script:Fail -gt 0) {
    Write-Host "❌ Validation FAILED - review the issues listed above."
    exit 1
}
Write-Host "✅ Validation PASSED"
exit 0
