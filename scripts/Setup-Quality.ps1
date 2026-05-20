#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates the per-repo parent "Quality" issue that anchors the Quality framework.

.DESCRIPTION
    The Quality framework tracks ongoing improvement work (security, performance, testing,
    cleanup, docs, api, cicd) across all Chris-Wolfgang .NET code repos. Each repo has
    one parent Quality issue (this script creates it) that documents candidate work by
    category. Actual tracked work lives in sub-issues labeled `quality-task` plus a
    `quality:<category>` label, and rolls up into a cross-repo GitHub Projects v2 board.

    This script is idempotent — if a `Quality: <repo>` issue with the `quality` label
    already exists in the target repository, the script reports it and exits 0.

    Requires that the labels `quality` and `quality-task` (plus the 7 category labels)
    already exist in the target repo. Run Setup-Labels.ps1 first.

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.PARAMETER QualityProjectUrl
    The URL of the cross-repo Quality Projects v2 board (e.g.
    https://github.com/users/Chris-Wolfgang/projects/N). Substituted into the issue body.

.EXAMPLE
    .\Setup-Quality.ps1 -QualityProjectUrl 'https://github.com/users/Chris-Wolfgang/projects/5'
    Creates the parent Quality issue for the current repository.

.EXAMPLE
    .\Setup-Quality.ps1 -Repository 'Chris-Wolfgang/my-repo' -QualityProjectUrl 'https://github.com/users/Chris-Wolfgang/projects/5'
    Creates the parent Quality issue for a specific repository.

.NOTES
    Requires: GitHub CLI (gh) authenticated with sufficient permissions.
    Install gh: https://cli.github.com/
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository,

    [Parameter(Mandatory = $true)]
    [string]$QualityProjectUrl
)

# Check gh CLI
try {
    $null = gh --version
} catch {
    Write-Error "❌ GitHub CLI (gh) is not installed or not in PATH."
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

try {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Not authenticated with GitHub CLI."
        Write-Host "Run: gh auth login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Error "❌ Failed to check GitHub CLI authentication status."
    exit 1
}

# Determine repository
if (-not $Repository) {
    Write-Host "🔍 Detecting current repository..." -ForegroundColor Cyan
    try {
        $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $Repository = $repoInfo.nameWithOwner
        Write-Host "✅ Using repository: $Repository" -ForegroundColor Green
    } catch {
        Write-Error "❌ Could not detect repository. Please run from within a git repository or specify -Repository parameter."
        exit 1
    }
}

# Repository's bare name (after the /)
$repoName = ($Repository -split '/')[-1]
$issueTitle = "Quality: $repoName"

# Idempotency: check if a parent Quality issue already exists.
# Limit is large (1000) so accidental over-use of the `quality` label can't cause
# the check to miss the actual parent and create a duplicate. After fetching,
# filter to exact title match.
Write-Host "`n🔍 Checking for existing parent Quality issue..." -ForegroundColor Cyan
# Capture stdout and stderr separately so JSON parsing isn't corrupted by
# any warnings gh emits to stderr. Only stdout is fed to ConvertFrom-Json.
$stderrFile = Join-Path ([IO.Path]::GetTempPath()) "setup-quality-stderr-$([guid]::NewGuid()).txt"
try {
    $existing = gh issue list `
        --repo $Repository `
        --label 'quality' `
        --state all `
        --json number,title,state `
        --limit 1000 2> $stderrFile

    if ($LASTEXITCODE -ne 0) {
        Write-Error "❌ Failed to query existing issues. Verify the 'quality' label exists in $Repository (run Setup-Labels.ps1 first)."
        if (Test-Path $stderrFile) { Write-Host (Get-Content $stderrFile -Raw) -ForegroundColor Red }
        exit 1
    }
} finally {
    Remove-Item -Path $stderrFile -ErrorAction SilentlyContinue
}

$matches = $existing | ConvertFrom-Json | Where-Object { $_.title -eq $issueTitle }
if ($matches) {
    $match = $matches | Select-Object -First 1
    Write-Host "⏭️  Parent Quality issue already exists: #$($match.number) [$($match.state)]" -ForegroundColor Gray
    Write-Host "    https://github.com/$Repository/issues/$($match.number)" -ForegroundColor Gray
    exit 0
}

# Read canonical body template
$scriptDir   = Split-Path -Parent $PSCommandPath
$templatePath = Join-Path $scriptDir 'templates/quality-parent-body.md'

if (-not (Test-Path $templatePath)) {
    Write-Error "❌ Canonical body template not found at: $templatePath"
    Write-Host "Expected the file at scripts/templates/quality-parent-body.md relative to this script." -ForegroundColor Yellow
    exit 1
}

$body = Get-Content -Path $templatePath -Raw

# Literal string replacement (.Replace) rather than -replace, since
# -replace's right-hand-side honors regex tokens like '$' and we don't want
# to alter the URL the caller passed in.
$body = $body.Replace('{{QUALITY_PROJECT_URL}}', $QualityProjectUrl)

# Write body to a temp file to avoid command-line length / quoting issues.
# Use [IO.Path]::GetTempPath() so this works on Linux/macOS (where $env:TEMP
# can be unset) as well as Windows.
$bodyFile = Join-Path ([IO.Path]::GetTempPath()) "quality-parent-body-$([guid]::NewGuid()).md"
Set-Content -Path $bodyFile -Value $body -Encoding utf8NoBOM

try {
    Write-Host "`n📝 Creating parent Quality issue in $Repository..." -ForegroundColor Cyan
    $createResult = gh issue create `
        --repo $Repository `
        --title $issueTitle `
        --body-file $bodyFile `
        --label 'quality' 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ Created: $createResult" -ForegroundColor Green
    } else {
        Write-Error "❌ Failed to create parent Quality issue."
        Write-Host $createResult -ForegroundColor Red
        exit 1
    }
} finally {
    Remove-Item -Path $bodyFile -ErrorAction SilentlyContinue
}
