<#
.SYNOPSIS
    Creates custom GitHub labels for the repository.

.DESCRIPTION
    This script uses the GitHub CLI (gh) to create labels used by Dependabot and
    other workflows. Run this locally once after creating a new repo from the template.
    
    Labels created:
    - dependabot - security  (red)
    - dependabot-dependencies (orange)
    - dependencies           (blue)
    - dotnet                 (purple)

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
    @{ name = "dependabot - security";    color = "b60205"; description = "Security update from Dependabot" },
    @{ name = "dependabot-dependencies";  color = "d93f0b"; description = "Dependency update from Dependabot" },
    @{ name = "dependencies";             color = "0366d6"; description = "Pull requests that update a dependency file" },
    @{ name = "dotnet";                   color = "512bd4"; description = ".NET related changes" }
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
