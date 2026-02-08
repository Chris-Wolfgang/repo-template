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
            echo -e "  \033[1;32m\$(brew --prefix)/bin/bash setup.sh\033[0m" >&2
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
║        .NET Repository Template - Automated Setup             ║
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
    
    PACKAGE_NAME=$(read_input \
        "NuGet Package Name" \
        "$PROJECT_NAME" \
        "$PROJECT_NAME" \
        "false")
    
    GITHUB_REPO_URL=$(read_input \
        "GitHub Repository URL" \
        "$git_remote_url" \
        "https://github.com/username/repo-name" \
        "true")
    
    # Extract repo name from URL
    REPO_NAME="$git_repo_name"
    if [[ -z "$REPO_NAME" ]] && [[ "$GITHUB_REPO_URL" =~ /([^/]+)$ ]]; then
        REPO_NAME="${BASH_REMATCH[1]}"
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
    
    NUGET_STATUS=$(read_input \
        "NuGet Package Status" \
        "Coming soon to NuGet.org" \
        "Available on NuGet.org" \
        "false")
    
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
        "Template Repository Owner" \
        "Chris-Wolfgang" \
        "YourUsername" \
        "false")
    
    TEMPLATE_REPO_NAME=$(read_input \
        "Template Repository Name" \
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
    
    local remaining_placeholders=()
    for file in "${FILES_TO_UPDATE[@]}"; do
        if [[ -f "$file" ]]; then
            local matches=$(grep -o '{{[A-Z_]*}}' "$file" || true)
            if [[ -n "$matches" ]]; then
                remaining_placeholders+=("$file : $matches")
            fi
        fi
    done
    
    if [[ ${#remaining_placeholders[@]} -eq 0 ]]; then
        success "All required placeholders replaced successfully!"
    else
        warn "Some placeholders were not replaced:"
        for placeholder in "${remaining_placeholders[@]}"; do
            echo "  - $placeholder"
        done
        info "These may be optional content placeholders for you to fill in later."
    fi
    
    # Optional cleanup
    step "Cleanup"
    echo ""
    echo -e "${YELLOW}Remove template-specific files? (y/N)${NC}"
    echo -e "  Files to remove:"
    echo "    - setup.ps1"
    echo "    - setup.sh (this script)"
    echo "    - TEMPLATE-PLACEHOLDERS.md"
    echo "    - LICENSE-SELECTION.md"
    echo "    - README-FORMATTING.md"
    echo "    - REPO-INSTRUCTIONS.md"
    echo ""
    echo -en "${YELLOW}Remove template files? (y/N): ${NC}"
    read -r cleanup
    
    if [[ "$cleanup" =~ ^[Yy]$ ]]; then
        FILES_TO_REMOVE=(
            "setup.ps1"
            "setup.sh"
            "TEMPLATE-PLACEHOLDERS.md"
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
    
    echo -e "${CYAN}✅ Next Steps:${NC}"
    echo ""
    echo -e "${YELLOW}1. Review the changes:${NC}"
    echo -e "   ${NC}git status${NC}"
    echo -e "   ${NC}git diff${NC}"
    echo ""
    echo -e "${YELLOW}2. Commit the changes:${NC}"
    echo -e "   ${NC}git add .${NC}"
    echo -e "   ${NC}git commit -m \"Configure repository from template\"${NC}"
    echo ""
    echo -e "${YELLOW}3. Push to GitHub:${NC}"
    echo -e "   ${NC}git push${NC}"
    echo ""
    echo -e "${YELLOW}4. Configure branch protection (see REPO-INSTRUCTIONS.md if kept)${NC}"
    echo ""
    echo -e "${YELLOW}5. Start developing!${NC}"
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
