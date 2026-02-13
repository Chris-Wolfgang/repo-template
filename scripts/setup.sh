#!/usr/bin/env bash

# Automated setup script for .NET repository template
# Requires: Bash 4.0+, git
# Compatible with: Linux, macOS (with Homebrew bash)

set -euo pipefail

# Check Bash version (requires 4.0+ for associative arrays)
check_bash_version() {
    local required_major=4
    local required_minor=0
    
    if [[ -z "${BASH_VERSINFO[0]:-}" ]] || \
       [[ "${BASH_VERSINFO[0]}" -lt $required_major ]] || \
       { [[ "${BASH_VERSINFO[0]}" -eq $required_major ]] && [[ "${BASH_VERSINFO[1]}" -lt $required_minor ]]; }; then
        echo -e "\033[0;31m❌ Error: This script requires Bash ${required_major}.${required_minor} or later.\033[0m" >&2
        echo -e "\033[1;33mYour current version: ${BASH_VERSION}\033[0m" >&2
        echo "" >&2
        
        if [[ "$(uname -s)" == "Darwin" ]]; then
            echo -e "\033[0;36mℹ️  macOS ships with Bash 3.2 by default.\033[0m" >&2
            echo -e "\033[0;36mTo install a newer version using Homebrew:\033[0m" >&2
            echo "" >&2
            echo -e "  \033[1;32mbrew install bash\033[0m" >&2
            echo "" >&2
            echo -e "\033[0;36mThen run this script with the updated bash:\033[0m" >&2
            echo -e "  \033[1;32m\$(brew --prefix)/bin/bash scripts/setup.sh\033[0m" >&2
        else
            echo -e "\033[0;36mℹ️  Please upgrade Bash to version ${required_major}.${required_minor} or later.\033[0m" >&2
        fi
        echo "" >&2
        exit 1
    fi
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    check_bash_version
fi

# Color codes
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly CYAN='\033[0;36m'
readonly MAGENTA='\033[0;35m'
readonly NC='\033[0m' # No Color

# Output functions
success() {
    echo -e "${GREEN}✅ $1${NC}"
}

info() {
    echo -e "${CYAN}ℹ️  $1${NC}"
}

warn() {
    echo -e "${YELLOW}⚠️  $1${NC}" >&2
}

error() {
    echo -e "${RED}❌ $1${NC}" >&2
}

step() {
    echo -e "\n${MAGENTA}🔧 $1${NC}"
}

# Banner
show_banner() {
    echo -e "${CYAN}"
    cat << "EOF"

╔════════════════════════════════════════════════════════════════╗
║                                                                ║
║        .NET Repository Template - Automated Setup              ║
║                                                                ║
╚════════════════════════════════════════════════════════════════╝

EOF
    echo -e "${NC}"
}

# Auto-detect git information
get_git_remote_url() {
    git remote get-url origin 2>/dev/null | sed 's/\.git$//' || echo ""
}

get_git_repo_name() {
    local url="$1"
    echo "$url" | sed -E 's|.*/([^/]+)$|\1|'
}

get_git_username() {
    local url="$1"
    if [[ "$url" =~ github\.com[:/]([^/]+)/ ]]; then
        echo "@${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

get_git_user_name() {
    git config user.name 2>/dev/null || echo ""
}

get_git_user_email() {
    git config user.email 2>/dev/null || echo ""
}

# Prompt for input with default and example
read_input() {
    local prompt="$1"
    local default="$2"
    local example="$3"
    local required="$4"
    local input=""
    
    while true; do
        echo -e "${YELLOW}${prompt}${NC}" >&2
        if [[ -n "$example" ]]; then
            echo -e "   Example: $example" >&2
        fi
        if [[ -n "$default" ]]; then
            echo -e "   Default: $default" >&2
        fi
        echo -n "   > " >&2
        read -r input
        
        # Use default if input is empty
        if [[ -z "$input" ]] && [[ -n "$default" ]]; then
            echo "$default"
            return 0
        fi
        
        # Check if required
        if [[ -z "$input" ]] && [[ "$required" == "true" ]]; then
            error "This field is required. Please enter a value."
            continue
        fi
        
        echo "$input"
        return 0
    done
}

# Escape special characters for sed replacement
# Escapes backslashes, ampersands, and forward slashes in the correct order
escape_for_sed() {
    printf '%s\n' "$1" | sed 's/\\/\\\\/g; s/&/\\&/g; s:/:\\/:g'
}

# Replace placeholders in a file
# Expects REPLACEMENTS to be defined in the caller's scope (e.g., main) to avoid Bash 4.3+ nameref requirement
replace_placeholders() {
    local file="$1"
    
    if [[ ! -f "$file" ]]; then
        warn "File not found (skipping): $file"
        return 0
    fi
    
    local modified=false
    local temp_file="${file}.tmp"
    cp "$file" "$temp_file"
    
    # Iterate over keys in the REPLACEMENTS array
    for key in "${!REPLACEMENTS[@]}"; do
        local placeholder="{{$key}}"
        local value="${REPLACEMENTS[$key]}"
        
        # Escape special characters for sed (/, &, and \)
        local escaped_value=$(escape_for_sed "$value")
        local escaped_placeholder=$(escape_for_sed "$placeholder")
        
        if grep -q "$placeholder" "$temp_file"; then
            sed -i.bak "s/$escaped_placeholder/$escaped_value/g" "$temp_file"
            rm -f "${temp_file}.bak"
            modified=true
        fi
    done
    
    if [[ "$modified" == "true" ]]; then
        mv "$temp_file" "$file"
        success "Updated: $file"
    else
        rm -f "$temp_file"
    fi
}

# Main setup function
main() {
    show_banner
    
    info "This script will configure your new repository."
    info "It will prompt you for project information and replace all placeholders."
    echo ""
    
    # Auto-detect git info
    step "Auto-detecting git repository information..."
    
    local git_remote_url=$(get_git_remote_url)
    local git_repo_name=$(get_git_repo_name "$git_remote_url")
    local git_username=$(get_git_username "$git_remote_url")
    local git_user_name=$(get_git_user_name)
    
    if [[ -n "$git_remote_url" ]]; then
        success "Detected repository: $git_remote_url"
    fi
    
    # Collect project information
    step "Collecting project information..."
    echo ""
    
    # Ask if creating NuGet package
    echo -en "${YELLOW}Will this project be published as a NuGet package? (Y/n): ${NC}" >&2
    read -r create_nuget_package
    if [[ -z "$create_nuget_package" ]] || [[ "$create_nuget_package" == "Y" ]] || [[ "$create_nuget_package" == "y" ]]; then
        is_nuget_package=true
    else
        is_nuget_package=false
    fi
    echo ""
    
    PROJECT_NAME=$(read_input \
        "Project Name (e.g., Wolfgang.Extensions.IAsyncEnumerable)" \
        "" \
        "MyCompany.MyLibrary" \
        "true")
    
    PROJECT_DESCRIPTION=$(read_input \
        "Project Description (one-line description)" \
        "" \
        "High-performance extension methods for IAsyncEnumerable<T>" \
        "true")
    
    if [[ "$is_nuget_package" == true ]]; then
        PACKAGE_NAME=$(read_input \
            "NuGet Package Name" \
            "$PROJECT_NAME" \
            "$PROJECT_NAME" \
            "false")
    else
        PACKAGE_NAME="$PROJECT_NAME"
    fi
    
    GITHUB_REPO_URL=$(read_input \
        "GitHub Repository URL" \
        "$git_remote_url" \
        "https://github.com/username/repo-name" \
        "true")
    
    # Extract repo name from URL
    REPO_NAME="$git_repo_name"
    if [[ -z "$REPO_NAME" ]] && [[ "$GITHUB_REPO_URL" =~ /([^/]+)$ ]]; then
        REPO_NAME="${BASH_REMATCH[1]}"
        # Strip optional .git suffix
        REPO_NAME="${REPO_NAME%.git}"
    fi
    if [[ -z "$REPO_NAME" ]]; then
        REPO_NAME=$(read_input \
            "Repository Name" \
            "" \
            "my-repo-name" \
            "true")
    fi
    
    GITHUB_USERNAME=$(read_input \
        "GitHub Username (with @)" \
        "$git_username" \
        "@YourUsername" \
        "true")
    
    # Ensure @ prefix
    if [[ ! "$GITHUB_USERNAME" =~ ^@ ]]; then
        GITHUB_USERNAME="@$GITHUB_USERNAME"
    fi
    
    # Generate docs URL from repo URL
    # Normalize SSH URLs to HTTPS and strip .git suffix
    local normalized_url="$GITHUB_REPO_URL"
    # Convert SSH format (git@github.com:org/repo) to HTTPS
    if [[ "$normalized_url" =~ ^git@github\.com:(.+)$ ]]; then
        normalized_url="https://github.com/${BASH_REMATCH[1]}"
    fi
    # Strip .git suffix if present
    normalized_url="${normalized_url%.git}"
    
    local default_docs_url=$(echo "$normalized_url" | sed -E 's|https://github.com/([^/]+)/([^/]+).*|https://\1.github.io/\2/|')
    DOCS_URL=$(read_input \
        "Documentation URL (GitHub Pages)" \
        "$default_docs_url" \
        "https://username.github.io/repo-name/" \
        "false")
    
    COPYRIGHT_HOLDER=$(read_input \
        "Copyright Holder Name" \
        "$git_user_name" \
        "John Doe" \
        "true")
    
    YEAR=$(date +%Y)
    YEAR=$(read_input \
        "Copyright Year" \
        "$YEAR" \
        "$YEAR" \
        "false")
    
    if [[ "$is_nuget_package" == true ]]; then
        NUGET_STATUS=$(read_input \
            "NuGet Package Status" \
            "Coming soon to NuGet.org" \
            "Available on NuGet.org" \
            "false")
    else
        NUGET_STATUS="Not applicable"
    fi
    
    # License selection
    step "Selecting License..."
    echo ""
    echo -e "${YELLOW}Available licenses:${NC}"
    echo "  1) MIT - Most permissive, simple, business-friendly"
    echo "  2) Apache-2.0 - Permissive with patent grant"
    echo "  3) MPL-2.0 - Weak copyleft, file-level"
    echo ""
    echo -e "${CYAN}For detailed comparison, see LICENSE-SELECTION.md${NC}"
    echo ""
    
    while true; do
        echo -en "${YELLOW}Select license (1-3): ${NC}"
        read -r license_choice
        
        case "$license_choice" in
            1)
                LICENSE_TYPE="MIT"
                LICENSE_FILE="LICENSE-MIT.txt"
                break
                ;;
            2)
                LICENSE_TYPE="Apache-2.0"
                LICENSE_FILE="LICENSE-APACHE-2.0.txt"
                break
                ;;
            3)
                LICENSE_TYPE="MPL-2.0"
                LICENSE_FILE="LICENSE-MPL-2.0.txt"
                break
                ;;
            *)
                error "Invalid choice. Please enter 1, 2, or 3."
                continue
                ;;
        esac
    done
    
    success "Selected: $LICENSE_TYPE License"
    
    # Template repository info
    TEMPLATE_REPO_OWNER=$(read_input \
        "Template Repository Owner (the GitHub user/org that owns the template you used)" \
        "Chris-Wolfgang" \
        "YourUsername" \
        "false")
    
    TEMPLATE_REPO_NAME=$(read_input \
        "Template Repository Name (the name of the template repository you used)" \
        "repo-template" \
        "my-template" \
        "false")
    
    # Summary
    step "Configuration Summary"
    echo ""
    echo -e "${CYAN}Project Information:${NC}"
    echo "  Project Name:        $PROJECT_NAME"
    echo "  Description:         $PROJECT_DESCRIPTION"
    echo "  Package Name:        $PACKAGE_NAME"
    echo "  Repository URL:      $GITHUB_REPO_URL"
    echo "  Repository Name:     $REPO_NAME"
    echo "  GitHub Username:     $GITHUB_USERNAME"
    echo "  Documentation URL:   $DOCS_URL"
    echo "  License:             $LICENSE_TYPE"
    echo "  Copyright Holder:    $COPYRIGHT_HOLDER"
    echo "  Copyright Year:      $YEAR"
    echo "  NuGet Status:        $NUGET_STATUS"
    echo "  Template Owner:      $TEMPLATE_REPO_OWNER"
    echo "  Template Name:       $TEMPLATE_REPO_NAME"
    echo ""
    
    echo -en "${YELLOW}Proceed with configuration? (Y/n): ${NC}"
    read -r confirm
    if [[ -n "$confirm" ]] && [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        warn "Setup cancelled."
        exit 0
    fi
    
    # Create associative array for replacements
    declare -A REPLACEMENTS=(
        ["PROJECT_NAME"]="$PROJECT_NAME"
        ["PROJECT_DESCRIPTION"]="$PROJECT_DESCRIPTION"
        ["PACKAGE_NAME"]="$PACKAGE_NAME"
        ["GITHUB_REPO_URL"]="$GITHUB_REPO_URL"
        ["REPO_NAME"]="$REPO_NAME"
        ["GITHUB_USERNAME"]="$GITHUB_USERNAME"
        ["DOCS_URL"]="$DOCS_URL"
        ["LICENSE_TYPE"]="$LICENSE_TYPE"
        ["YEAR"]="$YEAR"
        ["COPYRIGHT_HOLDER"]="$COPYRIGHT_HOLDER"
        ["NUGET_STATUS"]="$NUGET_STATUS"
        ["TEMPLATE_REPO_OWNER"]="$TEMPLATE_REPO_OWNER"
        ["TEMPLATE_REPO_NAME"]="$TEMPLATE_REPO_NAME"
    )
    
    # Perform setup
    step "Performing setup..."
    echo ""
    
    # Step 1: README swap
    info "Step 1/4: Swapping README files..."
    if [[ -f "README.md" ]]; then
        rm -f "README.md"
        success "Deleted template README.md"
    fi
    
    if [[ -f "README-TEMPLATE.md" ]]; then
        mv "README-TEMPLATE.md" "README.md"
        success "Renamed README-TEMPLATE.md → README.md"
    else
        error "README-TEMPLATE.md not found!"
        exit 1
    fi
    
    # Step 2: Replace placeholders
    info "Step 2/4: Replacing placeholders in files..."
    
    FILES_TO_UPDATE=(
        "README.md"
        "CONTRIBUTING.md"
        ".github/CODEOWNERS"
        "REPO-INSTRUCTIONS.md"
        "scripts/Setup-BranchRuleset.ps1"
        "docfx_project/docfx.json"
        "docfx_project/index.md"
        "docfx_project/api/index.md"
        "docfx_project/api/README.md"
        "docfx_project/docs/toc.yml"
        "docfx_project/docs/introduction.md"
        "docfx_project/docs/getting-started.md"
    )
    
    for file in "${FILES_TO_UPDATE[@]}"; do
        replace_placeholders "$file"
    done
    
    # Step 3: Set up LICENSE
    info "Step 3/4: Setting up LICENSE file..."
    
    if [[ -f "$LICENSE_FILE" ]]; then
        # Replace placeholders in license
        cp "$LICENSE_FILE" "LICENSE"
        
        # Escape special characters for sed (/, &, and \)
        local escaped_year=$(escape_for_sed "$YEAR")
        local escaped_holder=$(escape_for_sed "$COPYRIGHT_HOLDER")
        
        sed -i.bak "s/{{YEAR}}/$escaped_year/g" "LICENSE"
        sed -i.bak "s/{{COPYRIGHT_HOLDER}}/$escaped_holder/g" "LICENSE"
        rm -f "LICENSE.bak"
        success "Created LICENSE file ($LICENSE_TYPE)"
        
        # Delete all license templates
        rm -f LICENSE-MIT.txt LICENSE-APACHE-2.0.txt LICENSE-MPL-2.0.txt
        success "Removed license template files"
    else
        error "License template file not found: $LICENSE_FILE"
        exit 1
    fi
    
    # Step 4: Validation
    info "Step 4/4: Validating changes..."
    
    # Core placeholders that should have been replaced by the script
    # Note: YEAR and COPYRIGHT_HOLDER are handled in LICENSE file generation, not in FILES_TO_UPDATE
    local core_placeholders=(
        "PROJECT_NAME" "PROJECT_DESCRIPTION" "PACKAGE_NAME"
        "GITHUB_REPO_URL" "REPO_NAME" "GITHUB_USERNAME"
        "DOCS_URL" "LICENSE_TYPE"
        "NUGET_STATUS" "TEMPLATE_REPO_OWNER" "TEMPLATE_REPO_NAME"
    )
    
    # Optional placeholders that users fill in manually as they develop
    declare -A optional_placeholder_descriptions=(
        ["QUICK_START_EXAMPLE"]="Code example showing basic usage"
        ["FEATURES_TABLE"]="Markdown table listing features"
        ["FEATURE_EXAMPLES"]="Code examples demonstrating features"
        ["TARGET_FRAMEWORKS"]="List of supported .NET frameworks"
        ["ACKNOWLEDGMENTS"]="Credits for libraries/tools used"
    )
    
    # Collect placeholders grouped by placeholder name
    declare -A core_placeholders_by_name
    declare -A optional_placeholders_by_name
    
    for file in "${FILES_TO_UPDATE[@]}"; do
        if [[ -f "$file" ]]; then
            # Extract placeholder names (without braces)
            while IFS= read -r placeholder_full; do
                # Extract just the placeholder name
                placeholder_name="${placeholder_full//\{/}"
                placeholder_name="${placeholder_name//\}/}"
                
                # Categorize placeholder
                local is_core=0
                for core_ph in "${core_placeholders[@]}"; do
                    if [[ "$placeholder_name" == "$core_ph" ]]; then
                        is_core=1
                        break
                    fi
                done
                
                if [[ $is_core -eq 1 ]]; then
                    # Add to core placeholders
                    if [[ -z "${core_placeholders_by_name[$placeholder_name]:-}" ]]; then
                        core_placeholders_by_name[$placeholder_name]="$file"
                    else
                        # Check if file is already in the list (literal string match)
                        local already_added=0
                        IFS='|' read -ra existing_files <<< "${core_placeholders_by_name[$placeholder_name]}"
                        for existing_file in "${existing_files[@]}"; do
                            if [[ "$existing_file" == "$file" ]]; then
                                already_added=1
                                break
                            fi
                        done
                        if [[ $already_added -eq 0 ]]; then
                            core_placeholders_by_name[$placeholder_name]="${core_placeholders_by_name[$placeholder_name]}|$file"
                        fi
                    fi
                elif [[ -n "${optional_placeholder_descriptions[$placeholder_name]:-}" ]]; then
                    # Add to optional placeholders
                    if [[ -z "${optional_placeholders_by_name[$placeholder_name]:-}" ]]; then
                        optional_placeholders_by_name[$placeholder_name]="$file"
                    else
                        # Check if file is already in the list (literal string match)
                        local already_added=0
                        IFS='|' read -ra existing_files <<< "${optional_placeholders_by_name[$placeholder_name]}"
                        for existing_file in "${existing_files[@]}"; do
                            if [[ "$existing_file" == "$file" ]]; then
                                already_added=1
                                break
                            fi
                        done
                        if [[ $already_added -eq 0 ]]; then
                            optional_placeholders_by_name[$placeholder_name]="${optional_placeholders_by_name[$placeholder_name]}|$file"
                        fi
                    fi
                fi
            done < <(grep -o '{{[A-Z_]+}}' "$file" || true)
        fi
    done
    
    # Report core placeholders that weren't replaced (this is an error)
    if [[ ${#core_placeholders_by_name[@]} -gt 0 ]]; then
        error "Error: The following required placeholders were not replaced:"
        echo ""
        for placeholder_name in $(echo "${!core_placeholders_by_name[@]}" | tr ' ' '\n' | sort); do
            echo -e "${RED}  {{$placeholder_name}}${NC}"
            echo "    Found in:"
            
            IFS='|' read -ra files <<< "${core_placeholders_by_name[$placeholder_name]}"
            for file in "${files[@]}"; do
                echo "      - $file"
            done
            echo ""
        done
        warn "This indicates the script did not replace all required placeholders. Please review the files and replace these manually."
        echo ""
        exit 1
    else
        success "All required placeholders replaced successfully!"
    fi
    
    # Report optional placeholders that need manual updates
    if [[ ${#optional_placeholders_by_name[@]} -gt 0 ]]; then
        echo ""
        info "Optional content placeholders to fill in as you develop your project:"
        echo ""
        
        for placeholder_name in $(echo "${!optional_placeholders_by_name[@]}" | tr ' ' '\n' | sort); do
            local description="${optional_placeholder_descriptions[$placeholder_name]}"
            
            echo -e "${YELLOW}  {{$placeholder_name}}${NC}"
            echo "    Description: $description"
            echo "    Found in:"
            
            IFS='|' read -ra files <<< "${optional_placeholders_by_name[$placeholder_name]}"
            for file in "${files[@]}"; do
                echo "      - $file"
            done
            echo ""
        done
        info "See TEMPLATE-PLACEHOLDERS.md for details on each placeholder."
    fi
    
    # Optional cleanup
    step "Cleanup"
    echo ""
    echo -e "${YELLOW}Remove template-specific files? (y/N)${NC}"
    echo -e "  Files to remove:"
    echo "    - scripts/setup.ps1"
    echo "    - scripts/setup.sh (this script)"
    echo "    - LICENSE-SELECTION.md"
    echo "    - README-FORMATTING.md"
    echo "    - REPO-INSTRUCTIONS.md"
    echo ""
    echo -e "${CYAN}  Note: TEMPLATE-PLACEHOLDERS.md will remain for your reference.${NC}"
    echo -e "${CYAN}        Delete it manually when you've reviewed it and no longer need it.${NC}"
    echo ""
    echo -en "${YELLOW}Remove template files? (y/N): ${NC}"
    read -r cleanup
    
    if [[ "$cleanup" =~ ^[Yy]$ ]]; then
        FILES_TO_REMOVE=(
            "scripts/setup.ps1"
            "scripts/setup.sh"
            "LICENSE-SELECTION.md"
            "README-FORMATTING.md"
            "REPO-INSTRUCTIONS.md"
        )
        
        for file in "${FILES_TO_REMOVE[@]}"; do
            if [[ -f "$file" ]]; then
                rm -f "$file"
                success "Removed: $file"
            fi
        done
    else
        info "Keeping template files. You can remove them manually later."
    fi
    
    # Success!
    echo ""
    echo -e "${GREEN}╔════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}║                    🎉 Setup Complete! 🎉                       ║${NC}"
    echo -e "${GREEN}║                                                                ║${NC}"
    echo -e "${GREEN}╚════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    
    # Git operations
    step "Git Operations"
    echo ""
    
    # Step 1: Create branch and commit changes
    echo -en "${YELLOW}Create a branch and commit these changes? (Y/n): ${NC}"
    read -r commit_changes
    if [[ -z "$commit_changes" || "$commit_changes" =~ ^[Yy]$ ]]; then
        # Generate branch name
        branch_name="setup/configure-from-template-$(date +%Y%m%d-%H%M%S)"
        
        info "Step 1/4: Creating branch '$branch_name'..."
        if git checkout -b "$branch_name"; then
            success "Branch created successfully!"
            echo ""
            
            info "Step 2/4: Committing changes..."
            if git add .; then
                if git commit -m "Configure repository from template"; then
                    success "Changes committed successfully!"
                    echo ""
                    # Step 3: Push to GitHub
                    info "Step 3/4: Pushing branch to GitHub..."
                    git push -u origin "$branch_name"
                    if [[ $? -eq 0 ]]; then
                        success "Branch pushed to GitHub successfully!"
                        echo ""
                        
                        # Step 4: Create Pull Request
                        info "Step 4/4: Creating pull request..."
                        if gh pr create --title "Configure repository from template" --body "This PR contains the initial repository configuration from the template setup script.

Please review the changes, make any necessary adjustments, and merge to main when ready." --base main --head "$branch_name"; then
                            success "Pull request created successfully!"
                        else
                            echo -e "${RED:-}❌ Error: Failed to create pull request. You can create one manually from branch '$branch_name'.${NC:-}" >&2
                        fi
                    else
                        echo -e "${RED:-}❌ Error: Failed to push branch '$branch_name' to origin. Please check your Git remote and network connection, then try again.${NC:-}" >&2
                        exit 1
                    fi
                else
                    echo -e "${RED:-}❌ Error: Failed to commit changes. Please resolve any issues and try committing manually.${NC:-}" >&2
                    exit 1
                fi
            else
                echo -e "${RED:-}❌ Error: Failed to add files to the commit. Please check your working directory and try again.${NC:-}" >&2
                exit 1
            fi
        else
            echo -e "${RED:-}❌ Error: Failed to create branch '$branch_name'. Please ensure your repository is initialized and try again.${NC:-}" >&2
            exit 1
        fi
                        if [[ $? -eq 0 ]]; then
                            success "Pull request created successfully!"
                            echo ""
                            
                            # Get PR URL (best-effort; fall back to generic instruction on failure)
                            if pr_url=$(gh pr view "$branch_name" --json url --jq .url 2>/dev/null); then
                                echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
                                echo -e "${CYAN}║                                                                ║${NC}"
                                echo -e "${CYAN}║                       📋 Review Required                       ║${NC}"
                                echo -e "${CYAN}║                                                                ║${NC}"
                                echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
                                echo ""
                                echo -e "${YELLOW}Branch: $branch_name${NC}"
                                echo -e "${YELLOW}Pull Request: $pr_url${NC}"
                                echo ""
                                info "Please review the pull request, make any necessary changes, and merge it to main before continuing with development."
                                echo ""
                            else
                                echo -e "${CYAN}╔════════════════════════════════════════════════════════════════╗${NC}"
                                echo -e "${CYAN}║                                                                ║${NC}"
                                echo -e "${CYAN}║                       📋 Review Required                       ║${NC}"
                                echo -e "${CYAN}║                                                                ║${NC}"
                                echo -e "${CYAN}╚════════════════════════════════════════════════════════════════╝${NC}"
                                echo ""
                                echo -e "${YELLOW}Branch: $branch_name${NC}"
                                echo -e "${YELLOW}Pull Request URL: (unable to automatically determine)${NC}"
                                echo ""
                                info "Please review the pull request, make any necessary changes, and merge it to main before continuing with development."
                                info "If needed, you can view the pull request with: gh pr view \"$branch_name\" --web"
                                echo ""
                            fi
                            echo ""
                        else
                            warn "Failed to create pull request. You can create it manually with:"
                            echo "  gh pr create --title \"Configure repository from template\" --body \"Initial setup\" --base main --head "$branch_name""
                            echo ""
                        fi
                    else
                        warn "Push failed. You can push manually later with:"
                        echo "  git push -u origin "$branch_name""
                        echo ""
                    fi
                else
                    warn "Commit failed. You can commit manually later with:"
                    echo "  git commit -m \"Configure repository from template\""
                    echo "  git push -u origin "$branch_name""
                    echo ""
                fi
            else
                warn "Git add failed. You can commit manually later with:"
                echo "  git add ."
                echo "  git commit -m \"Configure repository from template\""
                echo "  git push -u origin "$branch_name""
                echo ""
            fi
        else
            warn "Failed to create branch. You can create it manually with:"
            echo "  git checkout -b \"$branch_name\""
            echo "  git add ."
            echo "  git commit -m \"Configure repository from template\""
            echo "  git push -u origin \"$branch_name\""
            echo ""
        fi
    else
        info "Skipping branch creation and commit. You can do this manually later with:"
        echo "  git checkout -b setup/configure-from-template-<timestamp>"
        echo "  git add ."
        echo "  git commit -m \"Configure repository from template\""
        echo "  git push -u origin setup/configure-from-template-<timestamp>"
        echo "  gh pr create --title \"Configure repository from template\" --base main"
        echo ""
    fi
    
    # Next steps
    echo -e "${CYAN}✅ Next Steps:${NC}"
    echo ""
    echo -e "${YELLOW}1. Configure branch protection (see REPO-INSTRUCTIONS.md if kept)${NC}"
    echo ""
    echo -e "${YELLOW}2. Start developing!${NC}"
    echo -e "   ${NC}dotnet new sln -n $PROJECT_NAME${NC}"
    echo -e "   ${NC}# Add your projects to src/ and tests/${NC}"
    echo ""
    
    info "Your repository is now configured and ready for development!"
    echo ""
}

# Run setup
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
