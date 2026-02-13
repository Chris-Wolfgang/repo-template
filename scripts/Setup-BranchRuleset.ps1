<#
.SYNOPSIS
    Creates a branch protection ruleset for the main branch in the current repository.

.DESCRIPTION
    This script uses the GitHub CLI (gh) to create a repository ruleset that protects
    the main branch with pull request requirements, required status checks, security
    scanning rules, and automatic Copilot code review.
    Run this locally after creating a new repo from the template.
    
    The script will prompt you to choose between single-developer or multi-developer 
    repository settings:
    - Single Developer: No PR approvals required (you can merge your own PRs)
    - Multi-Developer: Requires 1+ approval and code owner review
    
    The ruleset includes:
    - Pull request reviews with configurable approval requirements
    - Required status checks (tests, security scans)
    - CodeQL code scanning enforcement (High+ severity)
    - Automatic Copilot code review for pull requests
    - Copilot review of new pushes and draft PRs
    - CodeQL standard queries integration with Copilot reviews
    - Force push and deletion protection

.PARAMETER Repository
    The repository in owner/repo format. If not provided, uses the current repository.

.PARAMETER BranchName
    The branch to protect. Default is "main".

.EXAMPLE
    .\Setup-BranchRuleset.ps1
    Creates the ruleset for the current repository with interactive prompts

.EXAMPLE
    .\Setup-BranchRuleset.ps1 -Repository "Chris-Wolfgang/my-repo"
    Creates the ruleset for a specific repository

.NOTES
    Requires: GitHub CLI (gh) authenticated with sufficient permissions
    Install gh: https://cli.github.com/
    
    Note: The copilot_code_review ruleset type requires GitHub Copilot access
    and may require GitHub Enterprise or specific subscription plans. Verify your organization has the
    necessary subscriptions before running this script.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$Repository = "{{GITHUB_USERNAME}}/{{REPO_NAME}}",
    
    [Parameter()]
    [string]$BranchName = "main"
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
if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}" -or -not $Repository) {
    # Placeholders not replaced or no repository specified - auto-detect
    Write-Host "🔍 Detecting current repository..." -ForegroundColor Cyan
    try {
        $repoInfo = gh repo view --json nameWithOwner | ConvertFrom-Json
        $Repository = $repoInfo.nameWithOwner
        Write-Host "✅ Using repository: $Repository" -ForegroundColor Green
    } catch {
        if ($Repository -eq "{{GITHUB_USERNAME}}/{{REPO_NAME}}") {
            Write-Error "❌ Could not detect repository. Please run the setup script (scripts/setup.ps1 or scripts/setup.sh) first to replace placeholders, or specify -Repository parameter."
        } else {
            Write-Error "❌ Could not detect repository. Please run from within a git repository or specify -Repository parameter."
        }
        exit 1
    }
} else {
    Write-Host "✅ Using specified repository: $Repository" -ForegroundColor Green
}

Write-Host "`n🛡️  Setting up branch protection ruleset for: $Repository" -ForegroundColor Cyan
Write-Host "📌 Protected branch: $BranchName`n" -ForegroundColor Cyan

# Check if ruleset already exists
Write-Host "🔍 Checking for existing rulesets..." -ForegroundColor Yellow
try {
    $matchingRulesets = gh api `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repository/rulesets" `
        --paginate `
        --jq '.[] | select(.name == "Protect main branch")' | ConvertFrom-Json
    
    $existingRuleset = $matchingRulesets | Select-Object -First 1
    
    if ($existingRuleset) {
        Write-Host "✅ Ruleset 'Protect main branch' already exists!" -ForegroundColor Green
        Write-Host "   View it at: https://github.com/$Repository/settings/rules" -ForegroundColor Cyan
        $response = Read-Host "`nDo you want to continue anyway? This may fail. (y/N)"
        if ($response -ne 'y' -and $response -ne 'Y') {
            Write-Host "Exiting." -ForegroundColor Yellow
            exit 0
        }
    } else {
        Write-Host "ℹ️  Ruleset 'Protect main branch' does not exist yet." -ForegroundColor Gray
    }
} catch {
    Write-Warning "⚠️  Could not check for existing rulesets. Continuing..."
}

# Prompt for repository type
Write-Host "`n👥 Repository Type Configuration" -ForegroundColor Cyan
Write-Host ""
Write-Host "Is this a single-developer or multi-developer repository?" -ForegroundColor Yellow
Write-Host ""
Write-Host "  [1] Single Developer  - No PR approvals required (you can merge your own PRs)" -ForegroundColor Gray
Write-Host "  [2] Multi-Developer   - Requires 1+ approval and code owner review" -ForegroundColor Gray
Write-Host ""
$repoTypeChoice = Read-Host "Enter your choice (1 or 2) [default: 1]"

# Set defaults based on choice
$requireApprovals = 0
$requireCodeOwnerReview = $false

if ($repoTypeChoice -eq "2") {
    $requireApprovals = 1
    $requireCodeOwnerReview = $true
    Write-Host "✅ Configured for multi-developer repository (1 approval required)" -ForegroundColor Green
} else {
    Write-Host "✅ Configured for single-developer repository (no approvals required)" -ForegroundColor Green
}

# Create ruleset configuration
Write-Host "`n📝 Creating ruleset configuration..." -ForegroundColor Cyan

$rulesetConfig = @{
    name = "Protect main branch"
    target = "branch"
    enforcement = "active"
    conditions = @{
        ref_name = @{
            include = @("refs/heads/$BranchName")
            exclude = @()
        }
    }
    # Allow repository admins to bypass branch protection rules
    # Repository role IDs: 1 = read, 2 = write, 5 = admin
    # Using 5 (admin) ensures only users with admin permissions can bypass
    bypass_actors = @(
        @{
            actor_id = 5
            actor_type = "RepositoryRole"
            bypass_mode = "always"
        }
    )
    rules = @(
        @{
            type = "pull_request"
            parameters = @{
                required_approving_review_count = $requireApprovals
                dismiss_stale_reviews_on_push = $true
                require_code_owner_review = $requireCodeOwnerReview
                require_last_push_approval = $false
                required_review_thread_resolution = $true
            }
        },
        @{
            type = "required_status_checks"
            parameters = @{
                strict_required_status_checks_policy = $true
                # IMPORTANT: Workflows providing these required checks (specifically .github/workflows/pr.yaml)
                # must NOT have path filters (paths/paths-ignore). If a workflow is path-filtered
                # and doesn't run for a PR, GitHub will treat the required check as missing and
                # block the merge. All required status checks must run on every PR.
                # This also applies to the CodeQL workflow (codeql.yml) which provides the code_scanning
                # rule below - see that section for details on how CodeQL handles graceful skipping.
                required_status_checks = @(
                    @{ context = "Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate" },
                    @{ context = "Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)" },
                    @{ context = "Stage 3: macOS Tests (.NET 6.0-10.0)" },
                    @{ context = "Security Scan (DevSkim)" },
                    @{ context = "Security Scan (CodeQL)" }
                )
            }
        },
        @{
            type = "code_scanning"
            parameters = @{
                # NOTE: CodeQL uses the 'code_scanning' ruleset type instead of 'required_status_checks'
                # because it has built-in intelligence to handle cases where scans don't run
                # The workflow (.github/workflows/codeql.yml) has no path filters to ensure
                # GitHub can properly evaluate this rule. The workflow runs on all PRs and gracefully
                # skips analysis when there's no C# code, preventing false merge blocks while still
                # enforcing security scanning when needed.
                code_scanning_tools = @(
                    @{
                        tool = "CodeQL"
                        security_alerts_threshold = "high_or_higher"
                        alerts_threshold = "errors"
                    }
                )
            }
        },
        @{
            type = "copilot_code_review"
            parameters = @{
                # Automatically request Copilot code review for new pull requests
                # if the author has Copilot access and hasn't reached their review request limit
                auto_request_copilot_review = $true
                # Review new pushes to the pull request automatically
                review_new_pushes = $true
                # Review draft pull requests before they are marked as ready
                review_draft_pull_requests = $true
                # Static analysis tools to include in Copilot code review
                static_analysis_tools = @("CodeQL")
                # Query suite for CodeQL
                codeql_query_suite = "standard"
            }
        },
        @{
            type = "non_fast_forward"
        },
        @{
            type = "deletion"
        },
        @{
            type = "update"
        }
    )
}

# Convert to JSON
$jsonConfig = $rulesetConfig | ConvertTo-Json -Depth 10

# Save to temporary file
$tempFile = [System.IO.Path]::GetTempFileName()
$jsonConfig | Out-File -FilePath $tempFile -Encoding UTF8

try {
    Write-Host "🚀 Creating branch ruleset..." -ForegroundColor Cyan
    
    # Create the ruleset
    $response = gh api `
        --method POST `
        -H "Accept: application/vnd.github+json" `
        -H "X-GitHub-Api-Version: 2022-11-28" `
        "/repos/$Repository/rulesets" `
        --input $tempFile 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host "`n✅ Successfully created branch ruleset 'Protect main branch'!" -ForegroundColor Green
        Write-Host "`n🛡️  Protection Rules Enabled:" -ForegroundColor Cyan
        Write-Host "   ✅ Pull requests required before merging" -ForegroundColor Gray
        if ($requireApprovals -gt 0) {
            Write-Host "   ✅ Required approvals: $requireApprovals" -ForegroundColor Gray
            Write-Host "   ✅ Code owner review required" -ForegroundColor Gray
        } else {
            Write-Host "   ✅ No approvals required (single-developer mode)" -ForegroundColor Gray
        }
        Write-Host "   ✅ Required status checks (must pass before merging):" -ForegroundColor Gray
        Write-Host "      - Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate" -ForegroundColor DarkGray
        Write-Host "      - Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)" -ForegroundColor DarkGray
        Write-Host "      - Stage 3: macOS Tests (.NET 6.0-10.0)" -ForegroundColor DarkGray
        Write-Host "      - Security Scan (DevSkim)" -ForegroundColor DarkGray
        Write-Host "      - Security Scan (CodeQL)" -ForegroundColor DarkGray
        Write-Host "   ✅ Branches must be up to date before merging" -ForegroundColor Gray
        Write-Host "   ✅ Conversation resolution required before merging" -ForegroundColor Gray
        Write-Host "   ✅ Stale reviews dismissed when new commits are pushed" -ForegroundColor Gray
        Write-Host "   ✅ CodeQL code scanning enforcement (blocks on High+ severity findings)" -ForegroundColor Gray
        Write-Host "   ✅ Automatic Copilot code review enabled:" -ForegroundColor Gray
        Write-Host "      - Auto-request for new pull requests" -ForegroundColor DarkGray
        Write-Host "      - Review new pushes automatically" -ForegroundColor DarkGray
        Write-Host "      - Review draft pull requests" -ForegroundColor DarkGray
        Write-Host "      - Static analysis tools: CodeQL (standard queries)" -ForegroundColor DarkGray
        Write-Host "   ✅ Force pushes blocked on $BranchName branch" -ForegroundColor Gray
        Write-Host "   ✅ Branch deletion prevented for $BranchName" -ForegroundColor Gray
        Write-Host "   ✅ Repository admins can bypass these rules" -ForegroundColor Gray
        
        Write-Host "`n🔗 View ruleset at:" -ForegroundColor Cyan
        Write-Host "   https://github.com/$Repository/settings/rules" -ForegroundColor Blue
    } else {
        Write-Error "❌ Failed to create ruleset"
        Write-Host $response -ForegroundColor Red
        
        if ($response -like "*403*" -or $response -like "*Resource not accessible*") {
            Write-Host "`n💡 This error usually means:" -ForegroundColor Yellow
            Write-Host "   1. You don't have admin access to this repository, OR" -ForegroundColor Yellow
            Write-Host "   2. Your GitHub authentication doesn't have the required scopes" -ForegroundColor Yellow
            Write-Host "`n🔧 Try re-authenticating with:" -ForegroundColor Cyan
            Write-Host "   gh auth login" -ForegroundColor Gray
            Write-Host "   For more information about required scopes, see: https://cli.github.com/manual/gh_auth_login" -ForegroundColor Gray
        }
        
        if ($response -like "*422*" -or $response -like "*Validation Failed*") {
            Write-Host "`n💡 This validation error usually means:" -ForegroundColor Yellow
            Write-Host "   1. The repository doesn't meet the requirements for rulesets (e.g., needs to be a GitHub Pro/Team/Enterprise repo)" -ForegroundColor Yellow
            Write-Host "   2. Some configuration in the ruleset is invalid for this repository type" -ForegroundColor Yellow
            Write-Host "   3. Required workflows or status checks might not exist yet" -ForegroundColor Yellow
            Write-Host "`n🔧 Possible solutions:" -ForegroundColor Cyan
            Write-Host "   - Verify this is a GitHub Pro, Team, or Enterprise repository" -ForegroundColor Gray
            Write-Host "   - Check that the required workflows exist in .github/workflows/" -ForegroundColor Gray
            Write-Host "   - Ensure you have admin permissions on the repository" -ForegroundColor Gray
        }
        
        exit 1
    }
} catch {
    Write-Error "❌ An error occurred: $_"
    exit 1
} finally {
    # Clean up temp file
    if (Test-Path $tempFile) {
        Remove-Item $tempFile -Force
    }
}

Write-Host "`n🎉 Setup complete!" -ForegroundColor Green
