# Template Repository Placeholder Explanation

## Purpose of TEMPLATE_REPO_OWNER and TEMPLATE_REPO_NAME

The questions **"Template Repository Owner"** and **"Template Repository Name"** collect information about the original template repository that was used to create a new project. These values are used to replace placeholders in the setup documentation.

## Where These Questions Appear

### 1. Interactive Setup Script

The setup script (`pwsh ./scripts/setup.ps1`) prompts users for this information:

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
2. **REPO-INSTRUCTIONS.md** - Target file where replacement occurs (line 46)

## Validation

The setup script validates that these placeholders are properly replaced (along with other core placeholders) before completing:

**PowerShell (setup.ps1, lines 475-479):**
```powershell
$corePlaceholders = @(
    'PROJECT_NAME', 'PROJECT_DESCRIPTION', 'PACKAGE_NAME',
    'GITHUB_REPO_URL', 'REPO_NAME', 'GITHUB_USERNAME',
    'DOCS_URL', 'LICENSE_TYPE',
    'NUGET_STATUS', 'TEMPLATE_REPO_OWNER', 'TEMPLATE_REPO_NAME'
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
