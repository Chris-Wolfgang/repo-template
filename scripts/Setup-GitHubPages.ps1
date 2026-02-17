#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Sets up GitHub Pages with DocFX for automatic documentation publishing on tag creation.

.DESCRIPTION
    This script automates the setup of GitHub Pages for a .NET repository using DocFX.
    It performs the following tasks:
    1. Creates a gh-pages branch if it doesn't already exist
    2. Configures GitHub Pages settings to serve from the gh-pages branch
    3. Ensures the DocFX workflow is configured to trigger on tag pushes (v*.*.* pattern)
    
    Run this script locally after creating a new repository from the template.

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.PARAMETER EnablePages
    If specified, automatically enables GitHub Pages without prompting.

.EXAMPLE
    .\Setup-GitHubPages.ps1
    Sets up GitHub Pages for the current repository with interactive prompts

.EXAMPLE
    .\Setup-GitHubPages.ps1 -Repository "Chris-Wolfgang/my-repo"
    Sets up GitHub Pages for a specific repository

.EXAMPLE
    .\Setup-GitHubPages.ps1 -EnablePages
    Sets up GitHub Pages and automatically enables it without prompting

.NOTES
    Requires: 
    - GitHub CLI (gh) authenticated with sufficient permissions
    - Git installed and available in PATH
    Install gh: https://cli.github.com/
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository = "{{GITHUB_USERNAME}}/{{REPO_NAME}}",
    
    [Parameter()]
    [switch]$EnablePages
)

# Enable strict mode
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Color output functions
function Write-Success {
    param([string]$Message)
    Write-Host "✅ $Message" -ForegroundColor Green
}

function Write-Info {
    param([string]$Message)
    Write-Host "ℹ️  $Message" -ForegroundColor Cyan
}

function Write-Warning-Custom {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-Error-Custom {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n🔧 $Message" -ForegroundColor Magenta
}

# Banner
Write-Host @"

╔═══════════════════════════════════════════════════════════════════╗
║                                                                   ║
║        GitHub Pages Setup - DocFX Documentation Publishing        ║
║                                                                   ║
╚═══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

# Check if gh CLI is installed
Write-Step "Checking prerequisites..."
try {
    $null = gh --version
    Write-Success "GitHub CLI (gh) is installed"
} catch {
    Write-Error-Custom "GitHub CLI (gh) is not installed or not in PATH."
    Write-Host "Install from: https://cli.github.com/" -ForegroundColor Yellow
    exit 1
}

# Check if git is installed
try {
    $null = git --version
    Write-Success "Git is installed"
} catch {
    Write-Error-Custom "Git is not installed or not in PATH."
    Write-Host "Install from: https://git-scm.com/" -ForegroundColor Yellow
    exit 1
}

# Check if authenticated
try {
    $null = gh auth status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Not authenticated with GitHub CLI."
        Write-Host "Run: gh auth login" -ForegroundColor Yellow
        exit 1
    }
    Write-Success "Authenticated with GitHub CLI"
} catch {
    Write-Error-Custom "Failed to check GitHub CLI authentication status."
    exit 1
}

# Determine repository
if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}" -or -not $Repository) {
    # Placeholders not replaced or no repository specified - auto-detect
    Write-Info "Detecting current repository..."
    try {
        $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $Repository = $repoInfo.nameWithOwner
        Write-Success "Using repository: $Repository"
    } catch {
        if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}") {
            Write-Error-Custom "Could not detect repository. Please run the setup script (scripts/setup.ps1 or scripts/setup.sh) first to replace placeholders, or specify -Repository parameter."
        } else {
            Write-Error-Custom "Could not detect repository. Please run from within a git repository or specify -Repository parameter."
        }
        exit 1
    }
} else {
    Write-Success "Using specified repository: $Repository"
}

Write-Host "`n📚 Setting up GitHub Pages for: $Repository" -ForegroundColor Cyan

# Check if gh-pages branch exists
Write-Step "Checking for gh-pages branch..."
try {
    $branches = git ls-remote --heads origin gh-pages 2>&1
    
    if ($LASTEXITCODE -ne 0) {
        Write-Error-Custom "Error checking for gh-pages branch. Git exited with code $LASTEXITCODE.`nOutput:`n$branches"
        exit 1
    }
    
    $ghPagesBranchExists = -not [string]::IsNullOrWhiteSpace($branches)
    
    if ($ghPagesBranchExists) {
        Write-Success "gh-pages branch already exists"
    } else {
        Write-Info "gh-pages branch does not exist yet"
        
        # Check for uncommitted changes before creating gh-pages branch
        $gitStatus = git status --porcelain 2>&1
        if (-not [string]::IsNullOrWhiteSpace($gitStatus)) {
            Write-Warning-Custom "You have uncommitted changes in your working directory."
            Write-Info "Please commit or stash your changes before proceeding."
            Write-Info "Uncommitted changes:`n$gitStatus"
            $response = Read-Host "Do you want to continue anyway? This may cause data loss. (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Info "Aborting gh-pages branch creation."
                exit 0
            }
        }
        
        # Store the current branch name before switching
        $originalBranch = git rev-parse --abbrev-ref HEAD 2>&1
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($originalBranch) -or 
            $originalBranch -match '(fatal|error|warning|usage:)') {
            Write-Warning-Custom "Could not determine current branch name. Will attempt to return to 'main' after creating gh-pages."
            $originalBranch = "main"  # Default fallback
        }
        
        # Create gh-pages branch
        Write-Step "Creating gh-pages branch..."
        
        # Create an orphan branch (no history)
        $checkoutOutput = git checkout --orphan gh-pages 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to create orphan gh-pages branch. Git output:`n$checkoutOutput"
            throw "Git checkout --orphan failed"
        }
        
        # Remove all files from staging
        $rmOutput = git rm -rf . 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to remove files from staging. Git output:`n$rmOutput"
            throw "Git rm failed"
        }
        
        # Create a placeholder index.html
        $placeholderHtml = @"
<!DOCTYPE html>
<html>
<head>
    <meta charset="utf-8">
    <title>Documentation</title>
</head>
<body>
    <h1>Documentation Coming Soon</h1>
    <p>This site will contain the project documentation once it is generated.</p>
    <p>Documentation is automatically published when you push a version tag (e.g., v1.0.0).</p>
</body>
</html>
"@
        Set-Content -Path "index.html" -Value $placeholderHtml -Encoding UTF8
        
        # Commit and push
        $addOutput = git add index.html 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to stage index.html. Git output:`n$addOutput"
            throw "Git add failed"
        }
        
        $commitOutput = git commit -m "Initialize gh-pages branch" 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to commit gh-pages branch. Git output:`n$commitOutput"
            throw "Git commit failed"
        }
        
        $pushOutput = git push origin gh-pages 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Error-Custom "Failed to push gh-pages branch. Git output:`n$pushOutput"
            throw "Git push failed"
        }
        
        # Switch back to original branch
        try {
            $checkoutBackOutput = git checkout $originalBranch 2>&1
            if ($LASTEXITCODE -ne 0) {
                Write-Warning-Custom "Failed to switch back to original branch '$originalBranch'. Git output:`n$checkoutBackOutput"
                # Try to detect the default branch as fallback
                $defaultBranchOutput = git symbolic-ref refs/remotes/origin/HEAD 2>&1
                if ($LASTEXITCODE -eq 0 -and $defaultBranchOutput -and 
                    $defaultBranchOutput -notmatch '(fatal|error|warning|usage:)') {
                    $defaultBranch = $defaultBranchOutput | ForEach-Object { $_ -replace '^refs/remotes/origin/', '' }
                    $checkoutDefaultOutput = git checkout $defaultBranch 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Warning-Custom "Failed to checkout default branch '$defaultBranch'. Git output:`n$checkoutDefaultOutput"
                    }
                } else {
                    # Try main then master as last resort
                    $checkoutMainOutput = git checkout main 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        $checkoutMasterOutput = git checkout master 2>&1
                        if ($LASTEXITCODE -ne 0) {
                            Write-Warning-Custom "Could not switch back to any default branch. You may need to manually switch branches."
                        }
                    }
                }
            }
        } catch {
            Write-Warning-Custom "Could not switch back to original branch. You may need to manually switch branches."
        }
        
        Write-Success "Created and pushed gh-pages branch"
    }
} catch {
    Write-Error-Custom "Failed to check or create gh-pages branch: $_"
    Write-Host "You may need to create the gh-pages branch manually." -ForegroundColor Yellow
}

# Check and enable GitHub Pages
Write-Step "Configuring GitHub Pages settings..."
try {
    # Get current Pages configuration
    $pagesInfo = gh api "/repos/$Repository/pages" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        $pagesConfig = $pagesInfo | ConvertFrom-Json
        Write-Success "GitHub Pages is already enabled"
        Write-Info "   Source: $($pagesConfig.source.branch)/$($pagesConfig.source.path)"
        if ($pagesConfig.html_url) {
            Write-Info "   URL: $($pagesConfig.html_url)"
        }
        
        # Check if it's configured to use gh-pages branch
        if ($pagesConfig.source.branch -ne "gh-pages") {
            Write-Warning-Custom "GitHub Pages is not configured to use the gh-pages branch"
            if (-not $EnablePages) {
                $response = Read-Host "Would you like to update it to use gh-pages branch? (y/N)"
                if ($response -ne 'y' -and $response -ne 'Y') {
                    Write-Info "Skipping GitHub Pages branch update"
                } else {
                    $EnablePages = $true
                }
            }
            
            if ($EnablePages) {
                # Update Pages to use gh-pages branch
                $pagesConfigUpdate = @{
                    source = @{
                        branch = "gh-pages"
                        path = "/"
                    }
                } | ConvertTo-Json
                
                $tempFile = [System.IO.Path]::GetTempFileName()
                $pagesConfigUpdate | Out-File -FilePath $tempFile -Encoding UTF8
                
                try {
                    $updateOutput = gh api --method PUT "/repos/$Repository/pages" --input $tempFile 2>&1
                    if ($LASTEXITCODE -ne 0) {
                        Write-Error-Custom "Failed to update GitHub Pages configuration. GitHub CLI output:`n$updateOutput"
                    } else {
                        Write-Success "Updated GitHub Pages to use gh-pages branch"
                    }
                } catch {
                    Write-Error-Custom "Failed to update GitHub Pages configuration: $_"
                } finally {
                    if (Test-Path $tempFile) {
                        Remove-Item $tempFile -Force
                    }
                }
            }
        }
    } else {
        # Pages not enabled, try to enable it
        Write-Info "GitHub Pages is not enabled yet"
        
        if (-not $EnablePages) {
            $response = Read-Host "Would you like to enable GitHub Pages now? (y/N)"
            if ($response -ne 'y' -and $response -ne 'Y') {
                Write-Info "Skipping GitHub Pages setup"
                Write-Info "You can enable it later in: Settings → Pages"
            } else {
                $EnablePages = $true
            }
        }
        
        if ($EnablePages) {
            # Enable Pages with gh-pages branch
            $pagesConfig = @{
                source = @{
                    branch = "gh-pages"
                    path = "/"
                }
            } | ConvertTo-Json
            
            $tempFile = [System.IO.Path]::GetTempFileName()
            $pagesConfig | Out-File -FilePath $tempFile -Encoding utf8NoBOM
            
            try {
                $enableOutput = gh api --method POST "/repos/$Repository/pages" --input $tempFile 2>&1
                if ($LASTEXITCODE -ne 0) {
                    Write-Error-Custom "Failed to enable GitHub Pages. GitHub CLI output:`n$enableOutput"
                    Write-Host "You may need to enable it manually in: Settings → Pages" -ForegroundColor Yellow
                } else {
                    Write-Success "Enabled GitHub Pages with gh-pages branch"
                    
                    # Get the Pages URL
                    Start-Sleep -Seconds 2
                    $pagesUrlInfo = gh api "/repos/$Repository/pages" 2>&1
                    if ($LASTEXITCODE -eq 0) {
                        $pagesUrlData = $pagesUrlInfo | ConvertFrom-Json
                        if ($pagesUrlData.html_url) {
                            Write-Info "   URL: $($pagesUrlData.html_url)"
                        }
                    }
                }
            } catch {
                Write-Error-Custom "Failed to enable GitHub Pages: $_"
                Write-Host "You may need to enable it manually in: Settings → Pages" -ForegroundColor Yellow
            } finally {
                if (Test-Path $tempFile) {
                    Remove-Item $tempFile -Force
                }
            }
        }
    }
} catch {
    Write-Warning-Custom "Could not check GitHub Pages configuration"
    Write-Info "You may need to enable GitHub Pages manually in: Settings → Pages"
}

# Verify DocFX workflow configuration
Write-Step "Verifying DocFX workflow configuration..."
$workflowPath = ".github/workflows/docfx.yaml"

if (Test-Path $workflowPath) {
    $workflowContent = Get-Content $workflowPath -Raw
    $normalizedWorkflowContent = $workflowContent -replace "`r`n", "`n"
    
    # Check if workflow triggers on tags (looking for tag patterns like v*.*.* or v1.0.0)
    # Uses simple patterns that work with various YAML formats
    # Pattern 1: Matches 'v' followed by digits or asterisks in version format
    # Pattern 2: Matches the specific glob pattern v*.*.*
    # Pattern 3: Matches specific version numbers like v1.0.0
    $hasTagTrigger = $normalizedWorkflowContent -match 'tags:.*\n.*-.*v[0-9*]' -or
                     $normalizedWorkflowContent -match 'tags:.*v\*\.\*\.\*' -or
                     $normalizedWorkflowContent -match 'tags:.*v\d+\.\d+\.\d+'
    
    if ($hasTagTrigger) {
        Write-Success "DocFX workflow is configured to trigger on version tags"
    } else {
        Write-Warning-Custom "DocFX workflow may not be configured to trigger on version tags (v*.*.*)"
        Write-Info "The workflow currently triggers on:"
        if ($normalizedWorkflowContent -match 'on:\s*\n\s*push:\s*\n\s*branches:') {
            Write-Info "   - Push to branches"
        }
        Write-Info ""
        Write-Info "To enable automatic documentation publishing on version tags:"
        Write-Info "   1. Edit $workflowPath"
        Write-Info "   2. Update the 'on:' section to include:"
        Write-Info ""
        Write-Host @"
      on:
        push:
          tags:
            - 'v*.*.*'  # GitHub Actions tag pattern: matches v1.0.0, v2.1.3, etc.
          branches:
            - main
"@ -ForegroundColor DarkGray
        Write-Info ""
    }
} else {
    Write-Warning-Custom "DocFX workflow not found at $workflowPath"
    Write-Info "Ensure you have a DocFX workflow configured"
}

# Summary
Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "📋 Setup Summary" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

Write-Host "`n✅ Completed Tasks:" -ForegroundColor Green
Write-Host "   • Verified/Created gh-pages branch" -ForegroundColor Gray
if ($EnablePages) {
    Write-Host "   • Configured GitHub Pages settings" -ForegroundColor Gray
}
Write-Host "   • Verified DocFX workflow configuration" -ForegroundColor Gray

Write-Host "`n📝 Next Steps:" -ForegroundColor Yellow
Write-Host "   1. Ensure docfx_project/docfx.json is configured for your project" -ForegroundColor Gray
Write-Host "   2. Update .github/workflows/docfx.yaml to trigger on tags if needed" -ForegroundColor Gray
Write-Host "   3. Create a version tag to test: git tag v1.0.0 && git push origin v1.0.0" -ForegroundColor Gray
Write-Host "   4. Check the Actions tab to see the documentation build" -ForegroundColor Gray

Write-Host "`n🔗 Useful Links:" -ForegroundColor Cyan
Write-Host "   • Repository: https://github.com/$Repository" -ForegroundColor Blue
Write-Host "   • Actions: https://github.com/$Repository/actions" -ForegroundColor Blue
Write-Host "   • Settings → Pages: https://github.com/$Repository/settings/pages" -ForegroundColor Blue

# Get Pages URL if available
try {
    $pagesUrlOutput = gh api "/repos/$Repository/pages" 2>&1
    if ($LASTEXITCODE -eq 0) {
        $pagesUrlInfo = $pagesUrlOutput | ConvertFrom-Json
        if ($pagesUrlInfo.html_url) {
            Write-Host "   • Documentation: $($pagesUrlInfo.html_url)" -ForegroundColor Blue
        }
    }
} catch {
    # Silently ignore if we can't get the URL
}

Write-Host "`n🎉 GitHub Pages setup complete!" -ForegroundColor Green
Write-Host ""
