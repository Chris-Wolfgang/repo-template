<#
.SYNOPSIS
    Fixes branch rulesets by disabling existing ones and recreating with the correct configuration.

.DESCRIPTION
    This script inspects the existing branch rulesets for a repository, disables all of them,
    and renames any ruleset named "Protect main branch" to "Protect main branch (old)" so that
    Setup-BranchRuleset.ps1 can create a fresh ruleset without conflicts.

    The script presents a plan of all changes before executing and prompts for confirmation.

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.PARAMETER Force
    Skip the confirmation prompt and proceed automatically. Alias: -y

.EXAMPLE
    .\Fix-BranchRuleset.ps1
    Inspects and fixes rulesets for the current repository with interactive confirmation

.EXAMPLE
    .\Fix-BranchRuleset.ps1 -Force
    Inspects and fixes rulesets without prompting for confirmation

.EXAMPLE
    .\Fix-BranchRuleset.ps1 -Repository "Chris-Wolfgang/my-repo"
    Inspects and fixes rulesets for a specific repository

.NOTES
    Requires: GitHub CLI (gh) authenticated with admin permissions
    Install gh: https://cli.github.com/
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository = "{{GITHUB_USERNAME}}/{{REPO_NAME}}",

    [Parameter()]
    [Alias("y")]
    [switch]$Force
)

# Check if gh CLI is installed
try {
    $null = gh --version
} catch {
    Write-Error "GitHub CLI (gh) is not installed or not in PATH."
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Check if authenticated
try {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not authenticated with GitHub CLI."
        Write-Host "Run: gh auth login" -ForegroundColor Yellow
        exit 1
    }
} catch {
    Write-Error "Failed to check GitHub CLI authentication status."
    exit 1
}

# Determine repository
if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}" -or -not $Repository) {
    Write-Host "Detecting current repository..." -ForegroundColor Cyan
    try {
        $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $Repository = $repoInfo.nameWithOwner
        Write-Host "Using repository: $Repository" -ForegroundColor Green
    } catch {
        if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}") {
            Write-Error "Could not detect repository. Please run the setup script first to replace placeholders, or specify -Repository parameter."
        } else {
            Write-Error "Could not detect repository. Please run from within a git repository or specify -Repository parameter."
        }
        exit 1
    }
} else {
    Write-Host "Using specified repository: $Repository" -ForegroundColor Green
}

# Fetch all rulesets
Write-Host "`nFetching existing rulesets..." -ForegroundColor Cyan

try {
    $rulesetsJson = gh api `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repository/rulesets" `
        --paginate 2>&1

    if ($LASTEXITCODE -ne 0) {
        Write-Error "Failed to fetch rulesets: $rulesetsJson"
        exit 1
    }

    $rulesets = $rulesetsJson | ConvertFrom-Json
} catch {
    Write-Error "Failed to fetch rulesets: $($_.Exception.Message)"
    exit 1
}

if (-not $rulesets -or $rulesets.Count -eq 0) {
    Write-Host "No rulesets found for $Repository. Nothing to fix." -ForegroundColor Green
    exit 0
}

# Build the plan
$plan = @()
$targetRulesetName = "Protect main branch"

Write-Host "`nFound $($rulesets.Count) ruleset(s):" -ForegroundColor Cyan
Write-Host ""

foreach ($ruleset in $rulesets) {
    $status = if ($ruleset.enforcement -eq "disabled") { "disabled" } else { $ruleset.enforcement }
    Write-Host "  [$($ruleset.id)] $($ruleset.name) (enforcement: $status)" -ForegroundColor Gray

    $actions = @()

    # If this is the target name, rename it
    if ($ruleset.name -eq $targetRulesetName) {
        $actions += @{
            type        = "rename"
            description = "Rename '$($ruleset.name)' -> '$($ruleset.name) (old)'"
            newName     = "$($ruleset.name) (old)"
        }
    }

    # If not already disabled, disable it
    if ($ruleset.enforcement -ne "disabled") {
        $actions += @{
            type        = "disable"
            description = "Disable '$($ruleset.name)' (currently: $status)"
        }
    }

    if ($actions.Count -gt 0) {
        $plan += @{
            ruleset = $ruleset
            actions = $actions
        }
    }
}

Write-Host ""

# Present the plan
if ($plan.Count -eq 0) {
    Write-Host "All rulesets are already disabled and none need renaming. Nothing to do." -ForegroundColor Green
    exit 0
}

Write-Host "Planned changes:" -ForegroundColor Yellow
Write-Host ""

$stepNumber = 1
foreach ($item in $plan) {
    foreach ($action in $item.actions) {
        Write-Host "  $stepNumber. $($action.description)" -ForegroundColor White
        $stepNumber++
    }
}

Write-Host ""

# Prompt for confirmation
if ($Force) {
    Write-Host "Auto-confirmed via -Force flag." -ForegroundColor Green
} else {
    $response = Read-Host "Proceed with these changes? (y/N)"
    if ($response -ne 'y' -and $response -ne 'Y') {
        Write-Host "Cancelled. No changes were made." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Execute the plan
$errors = 0

foreach ($item in $plan) {
    $ruleset = $item.ruleset
    $rulesetId = $ruleset.id

    # Build the update payload — apply rename and disable together in one API call
    $updatePayload = @{}

    foreach ($action in $item.actions) {
        switch ($action.type) {
            "rename" {
                $updatePayload["name"] = $action.newName
            }
            "disable" {
                $updatePayload["enforcement"] = "disabled"
            }
        }
    }

    if ($updatePayload.Count -gt 0) {
        $descriptions = ($item.actions | ForEach-Object { $_.description }) -join " + "
        Write-Host "  Updating ruleset [$rulesetId]: $descriptions..." -ForegroundColor Cyan

        $jsonPayload = $updatePayload | ConvertTo-Json -Depth 5
        $tempFile = [System.IO.Path]::GetTempFileName()
        $jsonPayload | Out-File -FilePath $tempFile -Encoding utf8NoBOM

        try {
            $result = gh api `
                --method PUT `
                -H "Accept: application/vnd.github+json" `
                -H "X-GitHub-Api-Version: 2022-11-28" `
                "/repos/$Repository/rulesets/$rulesetId" `
                --input $tempFile 2>&1

            if ($LASTEXITCODE -eq 0) {
                Write-Host "  Done." -ForegroundColor Green
            } else {
                Write-Host "  Failed: $result" -ForegroundColor Red
                $errors++
            }
        } catch {
            Write-Host "  Error: $($_.Exception.Message)" -ForegroundColor Red
            $errors++
        } finally {
            if (Test-Path $tempFile) {
                Remove-Item $tempFile -Force
            }
        }
    }
}

Write-Host ""

if ($errors -gt 0) {
    Write-Host "$errors action(s) failed. Review the errors above." -ForegroundColor Red
    exit 1
} else {
    Write-Host "All changes applied successfully." -ForegroundColor Green
    Write-Host ""

    # Invoke Setup-BranchRuleset.ps1 to create a fresh ruleset
    $setupScript = Join-Path $PSScriptRoot "Setup-BranchRuleset.ps1"
    if (Test-Path $setupScript) {
        Write-Host "Running Setup-BranchRuleset.ps1 to create a fresh ruleset..." -ForegroundColor Cyan
        Write-Host ""
        & $setupScript -Repository $Repository
    } else {
        Write-Host "Setup-BranchRuleset.ps1 not found. Run it manually to create a fresh ruleset." -ForegroundColor Yellow
        Write-Host "View rulesets at: https://github.com/$Repository/settings/rules" -ForegroundColor Cyan
    }
}
