# Template Repository Placeholder Explanation

## Purpose of TEMPLATE_REPO_OWNER and TEMPLATE_REPO_NAME

The questions **"Template Repository Owner"** and **"Template Repository Name"** collect information about the original template repository that was used to create a new project. These values are used to replace placeholders in the setup documentation.

## Where These Questions Appear

### 1. Interactive Setup Scripts

Both setup scripts (`scripts/setup.ps1` and `scripts/setup.sh`) prompt users for this information:

**PowerShell (setup.ps1):**
```powershell
$templateRepoOwner = Read-Input `
    -Prompt "Template Repository Owner" `
    -Default "Chris-Wolfgang" `
    -Example "YourUsername"

$templateRepoName = Read-Input `
    -Prompt "Template Repository Name" `
    -Default "repo-template" `
    -Example "my-template"
```

**Bash (setup.sh):**
```bash
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
```

### 2. GitHub Actions Workflow

The `setup-template.yml` workflow automatically detects the template repository:

```yaml
template_repo_owner=$(printf '%s\n' "${{ github.event.repository.template_repository.owner.login || 'Chris-Wolfgang' }}" | sed -e 's/[&|\\]/\\&/g')
template_repo_name=$(printf '%s\n' "${{ github.event.repository.template_repository.name || 'repo-template' }}" | sed -e 's/[&|\\]/\\&/g')
```

This uses GitHub's API to automatically detect the source template repository when a repository is created from a template, falling back to defaults if unavailable.

## What These Placeholders Replace

### Primary Usage: REPO-INSTRUCTIONS.md

The main purpose is to replace the placeholder reference in `REPO-INSTRUCTIONS.md`:

**Before replacement (line 46):**
```markdown
1. `Start with a template` select `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}`
```

**After replacement (if using default template):**
```markdown
1. `Start with a template` select `Chris-Wolfgang/repo-template`
```

**After replacement (if user selects different template):**
```markdown
1. `Start with a template` select `YourUsername/my-template`
```

This ensures that the setup instructions accurately reflect which template was actually used to create the repository.

## Why This Matters

When users:
1. Fork the template to customize it
2. Create their own variant of this template
3. Use a customized version within an organization

The setup instructions should reference the **actual template they used**, not the original upstream template. This prevents confusion during onboarding and documentation.

## Files That Process These Placeholders

1. **scripts/setup.ps1** - PowerShell setup script (prompts: lines 341-349; replacements hashtable: lines 390-391)
2. **scripts/setup.sh** - Bash setup script (prompts: lines 361-371; replacements array: lines 412-413)
3. **.github/workflows/setup-template.yml** - GitHub Actions workflow (variable extraction: lines 133-134; sed replacements: lines 147-148)
4. **REPO-INSTRUCTIONS.md** - Target file where replacement occurs (line 46)

## Validation

The setup scripts validate that these placeholders are properly replaced (along with other core placeholders) before completing:

**PowerShell (setup.ps1, lines 475-479):**
```powershell
$corePlaceholders = @(
    'PROJECT_NAME', 'PROJECT_DESCRIPTION', 'PACKAGE_NAME',
    'GITHUB_REPO_URL', 'REPO_NAME', 'GITHUB_USERNAME',
    'DOCS_URL', 'LICENSE_TYPE',
    'NUGET_STATUS', 'TEMPLATE_REPO_OWNER', 'TEMPLATE_REPO_NAME'
)
```

**Bash (setup.sh, lines 486-491):**
```bash
local core_placeholders=(
    "PROJECT_NAME" "PROJECT_DESCRIPTION" "PACKAGE_NAME"
    "GITHUB_REPO_URL" "REPO_NAME" "GITHUB_USERNAME"
    "DOCS_URL" "LICENSE_TYPE"
    "NUGET_STATUS" "TEMPLATE_REPO_OWNER" "TEMPLATE_REPO_NAME"
)
```

## Default Values

- **TEMPLATE_REPO_OWNER**: `Chris-Wolfgang` (the original template owner)
- **TEMPLATE_REPO_NAME**: `repo-template` (the original template name)

These defaults work for most users creating repositories directly from the original template.

## When to Use Custom Values

Users should provide custom values when:
- Using a forked version of the template
- Using an organization-specific template variant
- The template has been renamed or moved to a different owner
- Creating documentation for a derivative template

## Related Documentation

- **TEMPLATE-PLACEHOLDERS.md** - Complete reference of all template placeholders
- **REPO-INSTRUCTIONS.md** - Contains the actual text that gets replaced
- **LICENSE-SELECTION.md** - License selection guidance
