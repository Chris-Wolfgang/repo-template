#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Creates custom GitHub labels for the repository.

.DESCRIPTION
    This script uses the GitHub CLI (gh) to create labels used by Dependabot and
    other workflows. Run this locally once after creating a new repo from the template.
    
    Labels created:
    - dependencies             (blue)   — applied automatically by Dependabot to every update PR
    - maintenance              (steel)  — kind label, applied to the per-repo parent Maintenance issue
    - maintenance-task         (steel)  — kind label, applied to every Maintenance sub-issue
    - maintenance - security   (red)    — category: scans, finding fixes, dependency vuln audit
    - maintenance - performance (green) — category: profile, benchmark, optimize, validate
    - maintenance - testing    (gold)   — category: coverage, integration/smoke/mutation tests
    - maintenance - cleanup    (brown)  — category: refactor for reuse / quality / efficiency
    - maintenance - docs       (blue)   — category: XML docs, README, CHANGELOG, samples
    - maintenance - API        (orange) — category: public/internal surface audit
    - maintenance - CI/CD      (pink)   — category: Docker, CI workflow, build/publish pipeline

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.EXAMPLE
    .\Setup-Labels.ps1
    Creates the labels for the current repository

.EXAMPLE
    .\Setup-Labels.ps1 -Repository "Chris-Wolfgang/my-repo"
    Creates the labels for a specific repository

.NOTES
    Requires: GitHub CLI (gh) authenticated with sufficient permissions
    Install gh: https://cli.github.com/
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository
)

# Check if gh CLI is installed
try {
    $null = gh --version
} catch {
    Write-Error "❌ GitHub CLI (gh) is not installed or not in PATH."
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Check if authenticated
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
} else {
    Write-Host "✅ Using specified repository: $Repository" -ForegroundColor Green
}

Write-Host "`n🏷️  Creating labels for: $Repository`n" -ForegroundColor Cyan

$labels = @(
    # Dependabot — applies `dependencies` automatically per .github/dependabot.yml
    @{ name = "dependencies";             color = "0366d6"; description = "Pull requests that update a dependency file" },

    # Maintenance framework — kind labels (neutral steel: the meta is colorless)
    @{ name = "maintenance";              color = "9aa7b3"; description = "Per-repo parent Maintenance issue (living improvement menu)" },
    @{ name = "maintenance-task";         color = "5a6c7d"; description = "A Maintenance sub-issue — actionable improvement work" },

    # Maintenance framework — category labels (applied to sub-issues)
    @{ name = "maintenance - security";    color = "c4161c"; description = "Maintenance: scans, finding fixes, dependency vulnerability audit" },
    @{ name = "maintenance - performance"; color = "2cbe4e"; description = "Maintenance: profile, benchmark, optimize, validate gains" },
    @{ name = "maintenance - testing";     color = "f9c513"; description = "Maintenance: coverage %, integration/smoke/mutation tests, fixtures" },
    @{ name = "maintenance - cleanup";     color = "a2845e"; description = "Maintenance: refactor for reuse, quality, efficiency" },
    @{ name = "maintenance - docs";        color = "0075ca"; description = "Maintenance: XML doc coverage, README, CHANGELOG, samples" },
    @{ name = "maintenance - API";         color = "ed7d31"; description = "Maintenance: public/internal surface audit, breaking-change vigilance" },
    @{ name = "maintenance - CI/CD";       color = "ec6cb9"; description = "Maintenance: Docker, CI workflow, build/publish pipeline" }
)

$created = 0
$skipped = 0
$failed  = 0

foreach ($label in $labels) {
    $response = gh api `
        --method POST `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repository/labels" `
        -f "name=$($label.name)" `
        -f "color=$($label.color)" `
        -f "description=$($label.description)" 2>&1

    if ($LASTEXITCODE -eq 0) {
        Write-Host "   ✅ Created label: $($label.name)" -ForegroundColor Green
        $created++
    } elseif ($response -like "*already_exists*") {
        Write-Host "   ⏭️  Label already exists, skipping: $($label.name)" -ForegroundColor Gray
        $skipped++
    } else {
        Write-Host "   ❌ Failed to create label: $($label.name)" -ForegroundColor Red
        Write-Host "      $response" -ForegroundColor Red
        $failed++
    }
}

Write-Host ""
if ($failed -eq 0) {
    Write-Host "🎉 Done! Created: $created, Skipped (already existed): $skipped" -ForegroundColor Green
} else {
    Write-Host "⚠️  Done with errors. Created: $created, Skipped: $skipped, Failed: $failed" -ForegroundColor Yellow
    exit 1
}
