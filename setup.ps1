#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Automated setup script for .NET repository template
.DESCRIPTION
    This script automates the process of configuring a new repository created from this template.
    It prompts for project information, replaces placeholders, sets up the license, and validates changes.
.NOTES
    Requires PowerShell Core 7.0 or later (cross-platform)
#>

[CmdletBinding()]
param()

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

function Write-TemplateWarning {
    param([string]$Message)
    Write-Host "⚠️  $Message" -ForegroundColor Yellow
}

function Write-TemplateError {
    param([string]$Message)
    Write-Host "❌ $Message" -ForegroundColor Red
}

function Write-Step {
    param([string]$Message)
    Write-Host "`n🔧 $Message" -ForegroundColor Magenta
}

# Banner
function Show-Banner {
    Write-Host @"

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║        .NET Repository Template - Automated Setup              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan
}

# Auto-detect git information
function Get-GitInfo {
    $gitInfo = @{
        RemoteUrl = ''
        RepoName = ''
        Username = ''
        UserEmail = ''
        FullName = ''
    }
    
    try {
        # Get remote URL
        $remoteUrl = git remote get-url origin 2>$null
        if ($remoteUrl) {
            $gitInfo.RemoteUrl = $remoteUrl -replace '\.git$', ''
            
            # Extract repo name
            if ($remoteUrl -match '/([^/]+?)(?:\.git)?$') {
                $gitInfo.RepoName = $matches[1]
            }
            
            # Extract username (for GitHub URLs)
            if ($remoteUrl -match 'github\.com[:/]([^/]+)/') {
                $gitInfo.Username = "@$($matches[1])"
            }
        }
        
        # Get git user name
        $userName = git config user.name 2>$null
        if ($userName) {
            $gitInfo.FullName = $userName
        }
        
        # Get git user email
        $userEmail = git config user.email 2>$null
        if ($userEmail) {
            $gitInfo.UserEmail = $userEmail
        }
    }
    catch {
        Write-Warning "Could not auto-detect git information"
    }
    
    return $gitInfo
}

# Prompt for input with default and example
function Read-Input {
    param(
        [string]$Prompt,
        [string]$Default = '',
        [string]$Example = '',
        [switch]$Required
    )
    
    $message = $Prompt
    if ($Example) {
        $message += "`n   Example: $Example"
    }
    if ($Default) {
        $message += "`n   Default: $Default"
    }
    $message += "`n   > "
    
    do {
        Write-Host $message -NoNewline -ForegroundColor Yellow
        $userInput = Read-Host
        
        if ([string]::IsNullOrWhiteSpace($userInput) -and $Default) {
            return $Default
        }
        
        if ([string]::IsNullOrWhiteSpace($userInput) -and $Required) {
            Write-TemplateError "This field is required. Please enter a value."
            continue
        }
        
        return $userInput
    } while ($true)
}

# Replace placeholders in a file
function Replace-Placeholders {
    param(
        [string]$FilePath,
        [hashtable]$Replacements
    )
    
    if (-not (Test-Path $FilePath)) {
        Write-Warning "File not found: $FilePath"
        return
    }
    
    $content = Get-Content $FilePath -Raw
    $modified = $false
    
    foreach ($key in $Replacements.Keys) {
        $placeholder = "{{$key}}"
        if ($content -match [regex]::Escape($placeholder)) {
            $pattern = [regex]::Escape($placeholder)
            $content = [regex]::Replace(
                $content,
                $pattern,
                [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $Replacements[$key] }
            )
            $modified = $true
        }
    }
    
    if ($modified) {
        Set-Content -Path $FilePath -Value $content
        Write-Success "Updated: $FilePath"
    }
}

# Main setup function
function Start-Setup {
    Show-Banner
    
    Write-Info "This script will configure your new repository."
    Write-Info "It will prompt you for project information and replace all placeholders."
    Write-Host ""
    
    # Auto-detect git info
    Write-Step "Auto-detecting git repository information..."
    $gitInfo = Get-GitInfo
    
    if ($gitInfo.RemoteUrl) {
        Write-Success "Detected repository: $($gitInfo.RemoteUrl)"
    }
    
    # Collect project information
    Write-Step "Collecting project information..."
    Write-Host ""
    
    $projectName = Read-Input `
        -Prompt "Project Name (e.g., Wolfgang.Extensions.IAsyncEnumerable)" `
        -Example "MyCompany.MyLibrary" `
        -Required
    
    $projectDescription = Read-Input `
        -Prompt "Project Description (one-line description)" `
        -Example "High-performance extension methods for IAsyncEnumerable<T>" `
        -Required
    
    $packageName = Read-Input `
        -Prompt "NuGet Package Name" `
        -Default $projectName `
        -Example $projectName
    
    $githubRepoUrl = Read-Input `
        -Prompt "GitHub Repository URL" `
        -Default $gitInfo.RemoteUrl `
        -Example "https://github.com/username/repo-name" `
        -Required
    
    # Extract repo name from URL if not already detected
    $repoName = $gitInfo.RepoName
    if ([string]::IsNullOrWhiteSpace($repoName) -and $githubRepoUrl -match '/([^/]+?)(?:\.git)?$') {
        $repoName = $matches[1]
    }
    if ([string]::IsNullOrWhiteSpace($repoName)) {
        $repoName = Read-Input `
            -Prompt "Repository Name" `
            -Example "my-repo-name" `
            -Required
    }
    
    $githubUsername = Read-Input `
        -Prompt "GitHub Username (with @)" `
        -Default $gitInfo.Username `
        -Example "@YourUsername" `
        -Required
    
    # Ensure @ prefix
    if ($githubUsername -notmatch '^@') {
        $githubUsername = "@$githubUsername"
    }
    
    # Normalize GitHub URL and generate docs URL
    # Handle SSH URLs (git@github.com:org/repo.git) and HTTPS URLs
    # Remove trailing .git and normalize to https://github.com/<owner>/<repo>
    $normalizedUrl = $githubRepoUrl
    
    # Convert SSH URL to HTTPS format
    if ($normalizedUrl -match '^git@github\.com:(.+)$') {
        $normalizedUrl = "https://github.com/$($matches[1])"
    }
    
    # Remove trailing .git
    $normalizedUrl = $normalizedUrl -replace '\.git$', ''
    
    # Extract owner and repo from normalized HTTPS URL
    $docsUrl = $normalizedUrl -replace 'https://github\.com/([^/]+)/([^/]+).*', 'https://$1.github.io/$2/'
    
    $docsUrl = Read-Input `
        -Prompt "Documentation URL (GitHub Pages)" `
        -Default $docsUrl `
        -Example "https://username.github.io/repo-name/"
    
    # Get copyright holder
    $copyrightHolder = Read-Input `
        -Prompt "Copyright Holder Name" `
        -Default $gitInfo.FullName `
        -Example "John Doe" `
        -Required
    
    $currentYear = (Get-Date).Year
    $year = Read-Input `
        -Prompt "Copyright Year" `
        -Default $currentYear.ToString() `
        -Example $currentYear.ToString()
    
    $nugetStatus = Read-Input `
        -Prompt "NuGet Package Status" `
        -Default "Coming soon to NuGet.org" `
        -Example "Available on NuGet.org"
    
    # License selection
    Write-Step "Selecting License..."
    Write-Host ""
    Write-Host "Available licenses:" -ForegroundColor Yellow
    Write-Host "  1) MIT - Most permissive, simple, business-friendly"
    Write-Host "  2) Apache-2.0 - Permissive with patent grant"
    Write-Host "  3) MPL-2.0 - Weak copyleft, file-level"
    Write-Host ""
    Write-Host "For detailed comparison, see LICENSE-SELECTION.md" -ForegroundColor Cyan
    Write-Host ""
    
    do {
        Write-Host "Select license (1-3): " -NoNewline -ForegroundColor Yellow
        $licenseChoice = Read-Host
        
        switch ($licenseChoice) {
            '1' { 
                $licenseType = 'MIT'
                $licenseFile = 'LICENSE-MIT.txt'
                break
            }
            '2' { 
                $licenseType = 'Apache-2.0'
                $licenseFile = 'LICENSE-APACHE-2.0.txt'
                break
            }
            '3' { 
                $licenseType = 'MPL-2.0'
                $licenseFile = 'LICENSE-MPL-2.0.txt'
                break
            }
            default {
                Write-TemplateError "Invalid choice. Please enter 1, 2, or 3."
                continue
            }
        }
        break
    } while ($true)
    
    Write-Success "Selected: $licenseType License"
    
    # Template repository info (for REPO-INSTRUCTIONS.md)
    $templateRepoOwner = Read-Input `
        -Prompt "Template Repository Owner" `
        -Default "Chris-Wolfgang" `
        -Example "YourUsername"
    
    $templateRepoName = Read-Input `
        -Prompt "Template Repository Name" `
        -Default "repo-template" `
        -Example "my-template"
    
    # Summary
    Write-Step "Configuration Summary"
    Write-Host ""
    Write-Host "Project Information:" -ForegroundColor Cyan
    Write-Host "  Project Name:        $projectName"
    Write-Host "  Description:         $projectDescription"
    Write-Host "  Package Name:        $packageName"
    Write-Host "  Repository URL:      $githubRepoUrl"
    Write-Host "  Repository Name:     $repoName"
    Write-Host "  GitHub Username:     $githubUsername"
    Write-Host "  Documentation URL:   $docsUrl"
    Write-Host "  License:             $licenseType"
    Write-Host "  Copyright Holder:    $copyrightHolder"
    Write-Host "  Copyright Year:      $year"
    Write-Host "  NuGet Status:        $nugetStatus"
    Write-Host "  Template Owner:      $templateRepoOwner"
    Write-Host "  Template Name:       $templateRepoName"
    Write-Host ""
    
    Write-Host "Proceed with configuration? (Y/n): " -NoNewline -ForegroundColor Yellow
    $confirm = Read-Host
    if ($confirm -and $confirm -ne 'Y' -and $confirm -ne 'y') {
        Write-Warning "Setup cancelled."
        exit 0
    }
    
    # Create replacements hashtable
    $replacements = @{
        'PROJECT_NAME' = $projectName
        'PROJECT_DESCRIPTION' = $projectDescription
        'PACKAGE_NAME' = $packageName
        'GITHUB_REPO_URL' = $githubRepoUrl
        'REPO_NAME' = $repoName
        'GITHUB_USERNAME' = $githubUsername
        'DOCS_URL' = $docsUrl
        'LICENSE_TYPE' = $licenseType
        'YEAR' = $year
        'COPYRIGHT_HOLDER' = $copyrightHolder
        'NUGET_STATUS' = $nugetStatus
        'TEMPLATE_REPO_OWNER' = $templateRepoOwner
        'TEMPLATE_REPO_NAME' = $templateRepoName
    }
    
    # Perform setup
    Write-Step "Performing setup..."
    Write-Host ""
    
    # Step 1: README swap
    Write-Info "Step 1/4: Swapping README files..."
    if (Test-Path 'README.md') {
        Remove-Item 'README.md' -Force
        Write-Success "Deleted template README.md"
    }
    
    if (Test-Path 'README-TEMPLATE.md') {
        Rename-Item 'README-TEMPLATE.md' 'README.md'
        Write-Success "Renamed README-TEMPLATE.md → README.md"
    }
    else {
        Write-Error "README-TEMPLATE.md not found!"
        exit 1
    }
    
    # Step 2: Replace placeholders
    Write-Info "Step 2/4: Replacing placeholders in files..."
    
    $filesToUpdate = @(
        'README.md',
        'CONTRIBUTING.md',
        '.github/CODEOWNERS',
        'REPO-INSTRUCTIONS.md',
        'scripts/Setup-BranchRuleset.ps1',
        'docfx_project/docfx.json',
        'docfx_project/index.md',
        'docfx_project/api/index.md',
        'docfx_project/api/README.md',
        'docfx_project/docs/toc.yml',
        'docfx_project/docs/introduction.md',
        'docfx_project/docs/getting-started.md'
    )
    
    foreach ($file in $filesToUpdate) {
        Replace-Placeholders -FilePath $file -Replacements $replacements
    }
    
    # Step 3: Set up LICENSE
    Write-Info "Step 3/4: Setting up LICENSE file..."
    
    if (Test-Path $licenseFile) {
        # Read license template
        $licenseContent = Get-Content $licenseFile -Raw
        
        # Replace placeholders using safe regex replacement with MatchEvaluator
        $licenseContent = [regex]::Replace(
            $licenseContent,
            [regex]::Escape('{{YEAR}}'),
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $year }
        )
        $licenseContent = [regex]::Replace(
            $licenseContent,
            [regex]::Escape('{{COPYRIGHT_HOLDER}}'),
            [System.Text.RegularExpressions.MatchEvaluator]{ param($m) $copyrightHolder }
        )
        
        # Save as LICENSE
        Set-Content -Path 'LICENSE' -Value $licenseContent -NoNewline
        Write-Success "Created LICENSE file ($licenseType)"
        
        # Delete all license templates
        Remove-Item 'LICENSE-MIT.txt' -Force -ErrorAction SilentlyContinue
        Remove-Item 'LICENSE-APACHE-2.0.txt' -Force -ErrorAction SilentlyContinue
        Remove-Item 'LICENSE-MPL-2.0.txt' -Force -ErrorAction SilentlyContinue
        Write-Success "Removed license template files"
    }
    else {
        Write-Error "License template file not found: $licenseFile"
        exit 1
    }
    
    # Step 4: Validation
    Write-Info "Step 4/4: Validating changes..."
    
    $remainingPlaceholders = @()
    foreach ($file in $filesToUpdate) {
        if (Test-Path $file) {
            $content = Get-Content $file -Raw
            $matches = [regex]::Matches($content, '\{\{[A-Z_]+\}\}')
            if ($matches.Count -gt 0) {
                $remainingPlaceholders += "$file : $($matches.Value -join ', ')"
            }
        }
    }
    
    if ($remainingPlaceholders.Count -eq 0) {
        Write-Success "All required placeholders replaced successfully!"
    }
    else {
        Write-Warning "Some placeholders were not replaced:"
        foreach ($placeholder in $remainingPlaceholders) {
            Write-Host "  - $placeholder" -ForegroundColor Yellow
        }
        Write-Info "These may be optional content placeholders for you to fill in later."
    }
    
    # Optional cleanup
    Write-Step "Cleanup"
    Write-Host ""
    Write-Host "Remove template-specific files? (y/N)" -ForegroundColor Yellow
    Write-Host "  Files to remove:" -ForegroundColor Gray
    Write-Host "    - setup.ps1 (this script)" -ForegroundColor Gray
    Write-Host "    - setup.sh" -ForegroundColor Gray
    Write-Host "    - LICENSE-SELECTION.md" -ForegroundColor Gray
    Write-Host "    - README-FORMATTING.md" -ForegroundColor Gray
    Write-Host "    - REPO-INSTRUCTIONS.md" -ForegroundColor Gray
    Write-Host ""
    Write-Host "Remove template files? (y/N): " -NoNewline -ForegroundColor Yellow
    $cleanup = Read-Host
    
    if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
        $filesToRemove = @(
            'setup.ps1',
            'setup.sh',
            'LICENSE-SELECTION.md',
            'README-FORMATTING.md',
            'REPO-INSTRUCTIONS.md'
        )
        
        foreach ($file in $filesToRemove) {
            if (Test-Path $file) {
                Remove-Item $file -Force
                Write-Success "Removed: $file"
            }
        }
    }
    else {
        Write-Info "Keeping template files. You can remove them manually later."
    }
    
    # Success!
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║                                                                ║" -ForegroundColor Green
    Write-Host "║                    🎉 Setup Complete! 🎉                       ║" -ForegroundColor Green
    Write-Host "║                                                                ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    
    Write-Host "✅ Next Steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Review the changes:" -ForegroundColor Yellow
    Write-Host "   git status" -ForegroundColor Gray
    Write-Host "   git diff" -ForegroundColor Gray
    Write-Host ""
    Write-Host "2. Commit the changes:" -ForegroundColor Yellow
    Write-Host "   git add ." -ForegroundColor Gray
    Write-Host "   git commit -m ""Configure repository from template""" -ForegroundColor Gray
    Write-Host ""
    Write-Host "3. Push to GitHub:" -ForegroundColor Yellow
    Write-Host "   git push" -ForegroundColor Gray
    Write-Host ""
    Write-Host "4. Configure branch protection (see REPO-INSTRUCTIONS.md if kept)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "5. Start developing!" -ForegroundColor Yellow
    Write-Host "   dotnet new sln -n $projectName" -ForegroundColor Gray
    Write-Host "   # Add your projects to src/ and tests/" -ForegroundColor Gray
    Write-Host ""
    
    Write-Info "Your repository is now configured and ready for development!"
    Write-Host ""
}

# Run setup
try {
    Start-Setup
}
catch {
    Write-Error "Setup failed: $_"
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}
