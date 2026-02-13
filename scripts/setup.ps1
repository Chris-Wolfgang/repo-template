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
    
    # Ask if creating NuGet package
    Write-Host "Will this project be published as a NuGet package? (Y/n): " -NoNewline -ForegroundColor Yellow
    $createNugetPackage = Read-Host
    if ([string]::IsNullOrEmpty($createNugetPackage) -or $createNugetPackage -eq 'Y' -or $createNugetPackage -eq 'y') {
        $isNugetPackage = $true
    }
    else {
        $isNugetPackage = $false
    }
    Write-Host ""
    
    $projectName = Read-Input `
        -Prompt "Project Name (e.g., Wolfgang.Extensions.IAsyncEnumerable)" `
        -Example "MyCompany.MyLibrary" `
        -Required
    
    $projectDescription = Read-Input `
        -Prompt "Project Description (one-line description)" `
        -Example "High-performance extension methods for IAsyncEnumerable<T>" `
        -Required
    
    if ($isNugetPackage) {
        $packageName = Read-Input `
            -Prompt "NuGet Package Name" `
            -Default $projectName `
            -Example $projectName
    }
    else {
        $packageName = $projectName
    }
    
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
    
    if ($isNugetPackage) {
        $nugetStatus = Read-Input `
            -Prompt "NuGet Package Status" `
            -Default "Coming soon to NuGet.org" `
            -Example "Available on NuGet.org"
    }
    else {
        $nugetStatus = "Not applicable"
    }
    
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
        -Prompt "Template Repository Owner (the GitHub user/org that owns the template you used)" `
        -Default "Chris-Wolfgang" `
        -Example "YourUsername"
    
    $templateRepoName = Read-Input `
        -Prompt "Template Repository Name (the name of the template repository you used)" `
        -Default "repo-template" `
        -Example "my-template"
    
    # Solution creation
    Write-Step "Solution Creation"
    Write-Host ""
    Write-Host "Create a default solution? (y/N): " -NoNewline -ForegroundColor Yellow
    $createSolution = Read-Host
    
    $solutionName = ''
    if ($createSolution -eq 'y' -or $createSolution -eq 'Y') {
        $isValidSolutionName = $false
        while (-not $isValidSolutionName) {
            $solutionName = Read-Input `
                -Prompt "Solution Name" `
                -Default $repoName `
                -Example $repoName `
                -Required

            $invalidFileNameChars = [System.IO.Path]::GetInvalidFileNameChars()
            if ($solutionName.IndexOfAny($invalidFileNameChars) -ne -1) {
                $invalidCharsDisplay = -join $invalidFileNameChars
                Write-Error "Solution name contains invalid characters. Please avoid any of: $invalidCharsDisplay" -ErrorAction Continue
            }
            else {
                $isValidSolutionName = $true
            }
        }
    }
    
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
    if ($solutionName) {
        Write-Host "  Solution Name:       $solutionName"
    }
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
    
    $totalSteps = if ($solutionName) { 5 } else { 4 }
    
    # Step 1: README swap
    Write-Info "Step 1/$totalSteps: Swapping README files..."
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
    Write-Info "Step 2/$totalSteps: Replacing placeholders in files..."
    
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
    Write-Info "Step 3/$totalSteps: Setting up LICENSE file..."
    
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
    
    # Step 4: Create solution (if requested)
    if ($solutionName) {
        Write-Info "Step 4/$totalSteps: Creating solution file..."
        
        # Create blank solution in .slnx format
        # Note: .slnx format requires Visual Studio 2022 version 17.10 or later
        $solutionFileName = "$solutionName.slnx"
        
        # Build the solution XML structure
        $xmlBuilder = New-Object System.Text.StringBuilder
        [void]$xmlBuilder.AppendLine('<Solution>')
        
        # Build .root folder with all remaining files
        # Exclude files and directories that have their own solution folders or are build artifacts
        # Note: .git directory is excluded separately below
        $excludePatterns = @(
            'obj',                # Build output
            'bin',                # Build output
            'TestResults',        # Test artifacts
            'CoverageReport',     # Coverage artifacts
            'node_modules',       # Node dependencies
            '*.user',             # User-specific files
            '*.suo',              # Visual Studio user options
            '*.sln',              # Solution files (prevent including solution in itself)
            '*.slnx',             # Solution files (prevent including solution in itself)
            '*.env',              # Environment files (may contain secrets)
            '*.key',              # Key files (may contain secrets)
            '*.pem',              # Certificate files (may contain secrets)
            'secrets*',           # Secret files
            'benchmarks',         # Has its own solution folder
            'examples',           # Has its own solution folder
            'src',                # Has its own solution folder
            'tests',              # Has its own solution folder
            'docfx_project'       # Documentation source (built separately)
        )
        
        # Get current directory for relative path calculation
        $currentDir = Get-Location
        
        # Helper function to get relative path safely
        function Get-SafeRelativePath {
            param($FullPath)
            try {
                # Use Resolve-Path with -Relative for safe relative path calculation
                $rel = Resolve-Path -Path $FullPath -Relative -ErrorAction Stop
                # Remove leading .\ or ./ prefix properly
                if ($rel.StartsWith('.\')) {
                    $rel = $rel.Substring(2)
                }
                elseif ($rel.StartsWith('./')) {
                    $rel = $rel.Substring(2)
                }
                return $rel.Replace('\', '/')
            }
            catch {
                # Fallback: manual calculation
                $path = $FullPath
                if ($path.StartsWith($currentDir.Path, [System.StringComparison]::OrdinalIgnoreCase)) {
                    $baseLength = $currentDir.Path.Length
                    # Ensure we only strip the base path when it's a complete directory component
                    if ($path.Length -eq $baseLength -or
                        ($path.Length -gt $baseLength -and
                         ($path[$baseLength] -eq [System.IO.Path]::DirectorySeparatorChar -or
                          $path[$baseLength] -eq [System.IO.Path]::AltDirectorySeparatorChar))) {
                        # Remove the base path and any leading separator
                        $path = $path.Substring($baseLength)
                        if ($path.StartsWith('\') -or $path.StartsWith('/')) {
                            $path = $path.Substring(1)
                        }
                    }
                }
                return $path.Replace('\', '/')
            }
        }
        
        # Get all files in the repository
        $allFiles = Get-ChildItem -Recurse -File -Force | Where-Object {
            # Get relative path safely
            $relativePath = Get-SafeRelativePath $_.FullName
            
            # Exclude files under .git directory specifically (not .github)
            if ($relativePath -like '.git/*') {
                return $false
            }
            
            # Exclude hidden files (starting with .) except those in .github directory
            $fileName = [System.IO.Path]::GetFileName($relativePath)
            $isInGitHubDir = $relativePath -like '.github/*'
            if ($fileName.StartsWith('.') -and -not $isInGitHubDir) {
                return $false
            }
            
            # Exclude files matching patterns using precise matching
            $shouldExclude = $false
            $pathSegments = $relativePath -split '[\\/]+'
            $fileExtension = [System.IO.Path]::GetExtension($relativePath)
            
            foreach ($pattern in $excludePatterns) {
                # Handle extension patterns like '*.user' or '*.suo'
                if ($pattern.StartsWith('*.')) {
                    $ext = $pattern.Substring(1)
                    if ($fileExtension -ieq $ext) {
                        $shouldExclude = $true
                        break
                    }
                }
                # Handle wildcard patterns like 'secrets*'
                elseif ($pattern.Contains('*')) {
                    if ($relativePath -like $pattern) {
                        $shouldExclude = $true
                        break
                    }
                }
                # Treat as a path segment name and match against segments
                else {
            # Split the relative path into segments for precise matching
            $pathSegments = $relativePath -split '[\\/]+'
            foreach ($pattern in $excludePatterns) {
                # Handle simple extension patterns like '*.user' or '*.suo'
                if ($pattern.StartsWith('*.') -and -not ($pattern.Substring(1) -like '*[*?]*')) {
                    $ext = [System.IO.Path]::GetExtension($relativePath)
                    if ($ext -ieq $pattern.Substring(1)) {
                        $shouldExclude = $true
                        break
                    }
                }
                else {
                    # Treat the pattern as a path segment name and match against segments
                    if ($pathSegments -contains $pattern) {
                        $shouldExclude = $true
                        break
                    }
                }
            }
            -not $shouldExclude
        }
        
        # Group files by directory for .root structure
        # Cache relative paths to avoid recalculating
        $filesByDirectory = @{}
        $relativePathCache = @{}
        
        foreach ($file in $allFiles) {
            # Get relative path safely (use cached if available)
            if (-not $relativePathCache.ContainsKey($file.FullName)) {
                $relativePathCache[$file.FullName] = Get-SafeRelativePath $file.FullName
            }
            $relativePath = $relativePathCache[$file.FullName]
            $directory = Split-Path $relativePath -Parent
            if ([string]::IsNullOrEmpty($directory)) {
                $directory = '.'
            }
            else {
                $directory = $directory.Replace('\', '/')
            }
            
            if (-not $filesByDirectory.ContainsKey($directory)) {
                $filesByDirectory[$directory] = @()
            }
            $filesByDirectory[$directory] += $relativePath
        }
        
        # Sort directories to ensure proper nesting order
        $sortedDirectories = $filesByDirectory.Keys | Sort-Object
        
        # Build folder structure with XML escaping
        foreach ($directory in $sortedDirectories) {
            if ($directory -eq '.') {
                # Root files
                [void]$xmlBuilder.AppendLine('  <Folder Name="/.root/">')
                foreach ($filePath in ($filesByDirectory[$directory] | Sort-Object)) {
                    $escapedPath = [System.Security.SecurityElement]::Escape($filePath)
                    [void]$xmlBuilder.AppendLine("    <File Path=""$escapedPath"" />")
                }
                [void]$xmlBuilder.AppendLine('  </Folder>')
            }
            else {
                # Subdirectory files
                $folderName = "/.root/$directory/"
                $escapedFolderName = [System.Security.SecurityElement]::Escape($folderName)
                [void]$xmlBuilder.AppendLine("  <Folder Name=""$escapedFolderName"">")
                foreach ($filePath in ($filesByDirectory[$directory] | Sort-Object)) {
                    $escapedPath = [System.Security.SecurityElement]::Escape($filePath)
                    [void]$xmlBuilder.AppendLine("    <File Path=""$escapedPath"" />")
                }
                [void]$xmlBuilder.AppendLine('  </Folder>')
            }
        }
        
        # Add solution folders for benchmarks, examples, src, tests (only if directories exist)
        # These are added after .root to prioritize configuration files in solution explorer
        $solutionFolders = @('benchmarks', 'examples', 'src', 'tests')
        foreach ($folder in $solutionFolders) {
            if (Test-Path -Path $folder -PathType Container) {
                [void]$xmlBuilder.AppendLine("  <Folder Name=""/$folder/"" />")
            }
        }
        
        [void]$xmlBuilder.AppendLine('</Solution>')
        
        # Write solution file with error handling
        try {
            Set-Content -Path $solutionFileName -Value $xmlBuilder.ToString() -ErrorAction Stop
            Write-Success "Created solution file: $solutionFileName"
            
            # Show summary
            $fileCount = $allFiles.Count
            $folderCount = $filesByDirectory.Keys.Count
            Write-Info "Added $fileCount files in $folderCount folders to .root/"
        }
        catch {
            Write-TemplateWarning "Failed to create solution file '$solutionFileName'. Repository setup will continue."
            Write-TemplateWarning "Error: $($_.Exception.Message)"
            # Clear solutionFileName so Next Steps won't reference it
            $solutionFileName = ''
        }
    }
    
    # Step 5: Validation
    Write-Info "Step $totalSteps/$totalSteps: Validating changes..."
    
    # Core placeholders that should have been replaced by the script
    # Note: YEAR and COPYRIGHT_HOLDER are handled in LICENSE file generation, not in FILES_TO_UPDATE
    $corePlaceholders = @(
        'PROJECT_NAME', 'PROJECT_DESCRIPTION', 'PACKAGE_NAME',
        'GITHUB_REPO_URL', 'REPO_NAME', 'GITHUB_USERNAME',
        'DOCS_URL', 'LICENSE_TYPE',
        'NUGET_STATUS', 'TEMPLATE_REPO_OWNER', 'TEMPLATE_REPO_NAME'
    )
    
    # Optional placeholders that users fill in manually as they develop
    $optionalPlaceholderDescriptions = @{
        'QUICK_START_EXAMPLE' = 'Code example showing basic usage'
        'FEATURES_TABLE' = 'Markdown table listing features'
        'FEATURE_EXAMPLES' = 'Code examples demonstrating features'
        'TARGET_FRAMEWORKS' = 'List of supported .NET frameworks'
        'ACKNOWLEDGMENTS' = 'Credits for libraries/tools used'
    }
    
    # Collect placeholders grouped by placeholder name
    $corePlaceholdersByName = @{}
    $optionalPlaceholdersByName = @{}
    
    foreach ($file in $filesToUpdate) {
        if (Test-Path $file) {
            $content = Get-Content $file -Raw
            $matches = [regex]::Matches($content, '\{\{([A-Z_]+)\}\}')
            foreach ($match in $matches) {
                $placeholderName = $match.Groups[1].Value
                
                # Categorize placeholder
                if ($corePlaceholders -contains $placeholderName) {
                    if (-not $corePlaceholdersByName.ContainsKey($placeholderName)) {
                        $corePlaceholdersByName[$placeholderName] = @()
                    }
                    if ($corePlaceholdersByName[$placeholderName] -notcontains $file) {
                        $corePlaceholdersByName[$placeholderName] += $file
                    }
                }
                elseif ($optionalPlaceholderDescriptions.ContainsKey($placeholderName)) {
                    if (-not $optionalPlaceholdersByName.ContainsKey($placeholderName)) {
                        $optionalPlaceholdersByName[$placeholderName] = @()
                    }
                    if ($optionalPlaceholdersByName[$placeholderName] -notcontains $file) {
                        $optionalPlaceholdersByName[$placeholderName] += $file
                    }
                }
            }
        }
    }
    
    # Report core placeholders that weren't replaced (this is an error)
    if ($corePlaceholdersByName.Count -gt 0) {
        Write-TemplateError "Error: The following required placeholders were not replaced:"
        Write-Host ""
        foreach ($placeholderName in ($corePlaceholdersByName.Keys | Sort-Object)) {
            Write-Host "  {{$placeholderName}}" -ForegroundColor Red
            Write-Host "    Found in:" -ForegroundColor Gray
            foreach ($file in $corePlaceholdersByName[$placeholderName]) {
                Write-Host "      - $file" -ForegroundColor Gray
            }
            Write-Host ""
        }
        Write-Warning "This indicates the script did not replace all required placeholders. Please review the files and replace these manually."
        Write-Host ""
        exit 1
    }
    else {
        Write-Success "All required placeholders replaced successfully!"
    }
    
    # Report optional placeholders that need manual updates
    if ($optionalPlaceholdersByName.Count -gt 0) {
        Write-Host ""
        Write-Info "Optional content placeholders to fill in as you develop your project:"
        Write-Host ""
        
        foreach ($placeholderName in ($optionalPlaceholdersByName.Keys | Sort-Object)) {
            $description = $optionalPlaceholderDescriptions[$placeholderName]
            
            Write-Host "  {{$placeholderName}}" -ForegroundColor Yellow
            Write-Host "    Description: $description" -ForegroundColor Gray
            Write-Host "    Found in:" -ForegroundColor Gray
            foreach ($file in $optionalPlaceholdersByName[$placeholderName]) {
                Write-Host "      - $file" -ForegroundColor Gray
            }
            Write-Host ""
        }
        Write-Info "See TEMPLATE-PLACEHOLDERS.md for details on each placeholder."
    }
    
    # Optional cleanup
    Write-Step "Cleanup"
    Write-Host ""
    Write-Host "Remove template-specific files? (y/N)" -ForegroundColor Yellow
    Write-Host "  Files to remove:" -ForegroundColor Gray
    Write-Host "    - scripts/setup.ps1 (this script)" -ForegroundColor Gray
    Write-Host "    - scripts/setup.sh" -ForegroundColor Gray
    Write-Host "    - LICENSE-SELECTION.md" -ForegroundColor Gray
    Write-Host "    - README-FORMATTING.md" -ForegroundColor Gray
    Write-Host "    - REPO-INSTRUCTIONS.md" -ForegroundColor Gray
    Write-Host ""
    Write-Host "  Note: TEMPLATE-PLACEHOLDERS.md will remain for your reference." -ForegroundColor Cyan
    Write-Host "        Delete it manually when you've reviewed it and no longer need it." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Remove template files? (y/N): " -NoNewline -ForegroundColor Yellow
    $cleanup = Read-Host
    
    if ($cleanup -eq 'y' -or $cleanup -eq 'Y') {
        $filesToRemove = @(
            'scripts/setup.ps1',
            'scripts/setup.sh',
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
    
    # Git operations
    Write-Step "Git Operations"
    Write-Host ""
    
    # Step 1: Create branch and commit changes
    Write-Host "Create a branch and commit these changes? (Y/n): " -NoNewline -ForegroundColor Yellow
    $commitChanges = Read-Host
    if ([string]::IsNullOrEmpty($commitChanges) -or $commitChanges -eq 'Y' -or $commitChanges -eq 'y') {
        # Generate branch name
        $branchName = "setup/configure-from-template-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        
        Write-Info "Step 1/4: Creating branch '$branchName'..."
        git checkout -b $branchName
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Branch created successfully!"
            Write-Host ""
            
            Write-Info "Step 2/4: Committing changes..."
            git add .
            if ($LASTEXITCODE -eq 0) {
                git commit -m "Configure repository from template"
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "Changes committed successfully!"
                    Write-Host ""
                    
                    # Step 3: Push to GitHub
                    Write-Info "Step 3/4: Pushing branch to GitHub..."
                    git push -u origin $branchName
                    if ($LASTEXITCODE -eq 0) {
                        Write-Success "Branch pushed to GitHub successfully!"
                        Write-Host ""
                        
                        # Step 4: Create Pull Request
                        Write-Info "Step 4/4: Creating pull request..."
                        
                        # Check if gh command is available
                        try {
                            $null = Get-Command gh -ErrorAction Stop
                            
                            gh pr create --title "Configure repository from template" --body "This PR contains the initial repository configuration from the template setup script.`n`nPlease review the changes, make any necessary adjustments, and merge to main when ready." --base main --head $branchName
                            if ($LASTEXITCODE -eq 0) {
                                Write-Success "Pull request created successfully!"
                                Write-Host ""
                                
                                # Get PR URL (best-effort; fall back to generic instruction on failure)
                                $prUrl = gh pr view $branchName --json url --jq .url 2>$null
                                if ($LASTEXITCODE -eq 0 -and $prUrl) {
                                    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                                    Write-Host "║                                                                ║" -ForegroundColor Cyan
                                    Write-Host "║                       📋 Review Required                       ║" -ForegroundColor Cyan
                                    Write-Host "║                                                                ║" -ForegroundColor Cyan
                                    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                                    Write-Host ""
                                    Write-Host "Branch: $branchName" -ForegroundColor Yellow
                                    Write-Host "Pull Request: $prUrl" -ForegroundColor Yellow
                                    Write-Host ""
                                    Write-Info "Please review the pull request, make any necessary changes, and merge it to main before continuing with development."
                                    Write-Host ""
                                }
                                else {
                                    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
                                    Write-Host "║                                                                ║" -ForegroundColor Cyan
                                    Write-Host "║                       📋 Review Required                       ║" -ForegroundColor Cyan
                                    Write-Host "║                                                                ║" -ForegroundColor Cyan
                                    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
                                    Write-Host ""
                                    Write-Host "Branch: $branchName" -ForegroundColor Yellow
                                    Write-Host ""
                                    Write-Info "Please review the pull request, make any necessary changes, and merge it to main before continuing with development."
                                    Write-Info "You can view the pull request with: gh pr view $branchName --web"
                                    Write-Host ""
                                }
                            }
                            else {
                                Write-TemplateWarning "Failed to create pull request. You can create it manually with:"
                                Write-Host "  gh pr create --title ""Configure repository from template"" --body ""Initial setup"" --base main --head $branchName" -ForegroundColor Gray
                                Write-Host ""
                            }
                        }
                        catch {
                            Write-TemplateWarning "GitHub CLI (gh) is not installed or not available in PATH."
                            Write-TemplateWarning "Please install it from https://cli.github.com/ to enable automatic PR creation."
                            Write-Host ""
                            Write-Info "You can create the pull request manually with:"
                            Write-Host "  gh pr create --title ""Configure repository from template"" --body ""Initial setup"" --base main --head $branchName" -ForegroundColor Gray
                            Write-Host ""
                        }
                    }
                    else {
                        Write-TemplateWarning "Push failed. You can push manually later with:"
                        Write-Host "  git push -u origin $branchName" -ForegroundColor Gray
                        Write-Host ""
                    }
                }
                else {
                    Write-TemplateWarning "Commit failed. You can commit manually later with:"
                    Write-Host "  git commit -m ""Configure repository from template""" -ForegroundColor Gray
                    Write-Host "  git push -u origin $branchName" -ForegroundColor Gray
                    Write-Host ""
                }
            }
            else {
                Write-TemplateWarning "Git add failed. You can commit manually later with:"
                Write-Host "  git add ." -ForegroundColor Gray
                Write-Host "  git commit -m ""Configure repository from template""" -ForegroundColor Gray
                Write-Host "  git push -u origin $branchName" -ForegroundColor Gray
                Write-Host ""
            }
        }
        else {
            Write-TemplateWarning "Failed to create branch. You can create it manually with:"
            Write-Host "  git checkout -b $branchName" -ForegroundColor Gray
            Write-Host "  git add ." -ForegroundColor Gray
            Write-Host "  git commit -m ""Configure repository from template""" -ForegroundColor Gray
            Write-Host "  git push -u origin $branchName" -ForegroundColor Gray
            Write-Host ""
        }
    }
    else {
        Write-Info "Skipping branch creation and commit. You can do this manually later with:"
        Write-Host "  git checkout -b setup/configure-from-template-<timestamp>" -ForegroundColor Gray
        Write-Host "  git add ." -ForegroundColor Gray
        Write-Host "  git commit -m ""Configure repository from template""" -ForegroundColor Gray
        Write-Host "  git push -u origin setup/configure-from-template-<timestamp>" -ForegroundColor Gray
        Write-Host "  gh pr create --title ""Configure repository from template"" --base main" -ForegroundColor Gray
        Write-Host ""
    }
    
    # Next steps
    Write-Host "✅ Next Steps:" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "1. Configure branch protection (see REPO-INSTRUCTIONS.md if kept)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "2. Start developing!" -ForegroundColor Yellow
    if ($solutionName) {
        Write-Host "   # Solution file created: $solutionName.slnx" -ForegroundColor Gray
        Write-Host "   # Add your projects to src/ and tests/" -ForegroundColor Gray
    }
    else {
        Write-Host "   dotnet new sln -n $projectName" -ForegroundColor Gray
        Write-Host "   # Add your projects to src/ and tests/" -ForegroundColor Gray
    }
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
