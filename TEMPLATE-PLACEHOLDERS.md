# Template Placeholders Documentation

This document provides comprehensive documentation of all placeholders used in this repository template and instructions for replacing them.

## Overview

The automated setup script (`pwsh ./scripts/setup.ps1`) handles all placeholder replacements automatically. This document is for reference or manual setup if needed.

---

## Placeholder Format

All placeholders use the format: `{{PLACEHOLDER_NAME}}`

**Example:** `{{PROJECT_NAME}}` becomes `Wolfgang.Extensions.IAsyncEnumerable`

---

## Core Placeholders

These placeholders are **required** and must be replaced in every project:

| Placeholder | Description | Example Value | Auto-detected? |
|------------|-------------|---------------|----------------|
| `{{PROJECT_NAME}}` | Full project/library name | `Wolfgang.Extensions.IAsyncEnumerable` | No |
| `{{PROJECT_DESCRIPTION}}` | One-line project description | `High-performance extension methods for IAsyncEnumerable<T>` | No |
| `{{PACKAGE_NAME}}` | NuGet package name | `Wolfgang.Extensions.IAsyncEnumerable` | No (usually same as PROJECT_NAME) |
| `{{GITHUB_REPO_URL}}` | Full GitHub repository URL, normalized to `https://github.com/<owner>/<repo>` (SSH form and trailing `.git` are converted) | `https://github.com/Chris-Wolfgang/MyProject` | Yes (from `git remote`) |
| `{{REPO_NAME}}` | Repository name only | `MyProject` | Yes (extracted from URL) |
| `{{GITHUB_USERNAME}}` | GitHub username with @ | `@Chris-Wolfgang` | Yes (from GitHub repo URL, or prompted if missing) |
| `{{GITHUB_OWNER}}` | GitHub owner slug (no @, URL-safe) | `Chris-Wolfgang` | Yes (derived from `GITHUB_USERNAME`) |
| `{{DOCS_URL}}` | Documentation URL | `https://chris-wolfgang.github.io/MyProject/` | Yes (generated from repo URL) |
| `{{LICENSE_TYPE}}` | License identifier | `MIT`, `Apache-2.0`, `MPL-2.0`, or `TBD` | No |
| `{{YEAR}}` | Copyright year | `2024` | Yes (current year) |
| `{{COPYRIGHT_HOLDER}}` | Copyright owner name | `Chris Wolfgang` | Yes (from `git config`) |
| `{{NUGET_STATUS}}` | NuGet availability message | `Coming soon to NuGet.org` or `Available on NuGet.org` | No |
| `{{TEMPLATE_REPO_OWNER}}` | Template repository owner (used in setup docs) | `Chris-Wolfgang` | No (prompted during setup) |
| `{{TEMPLATE_REPO_NAME}}` | Template repository name (used in setup docs) | `repo-template` | No (prompted during setup) |

---

## Optional Content Placeholders

These placeholders represent sections that users should fill in later. They can remain as placeholders initially:

| Placeholder | Purpose | Location |
|------------|---------|----------|
| `{{QUICK_START_EXAMPLE}}` | Code example showing basic usage | README.md |
| `{{FEATURES_TABLE}}` | Markdown table listing features | README.md |
| `{{FEATURE_EXAMPLES}}` | Code examples demonstrating features | README.md |
| `{{TARGET_FRAMEWORKS}}` | Bullet list of supported .NET frameworks for the "Supported Frameworks" section (copy from your source csproj's `<TargetFrameworks>`) | README.md |
| `{{ACKNOWLEDGMENTS}}` | Credits for libraries/tools used | README.md |

**Note:** The automated setup scripts do NOT replace these - users fill them in as they develop their project.

---

## Template Identification Placeholders

### Purpose of TEMPLATE_REPO_OWNER and TEMPLATE_REPO_NAME

The `{{TEMPLATE_REPO_OWNER}}` and `{{TEMPLATE_REPO_NAME}}` placeholders identify the original template repository used to create a new project. These values are primarily used in setup documentation to ensure that instructions accurately reference the actual template source.

### Why This Matters

When users:
1. Fork the template to customize it
2. Create their own variant of this template
3. Use a customized version within an organization

The setup instructions should reference the **actual template they used**, not the original upstream template. This prevents confusion during onboarding and documentation.

### Default Values

- **TEMPLATE_REPO_OWNER**: `Chris-Wolfgang` (the original template owner)
- **TEMPLATE_REPO_NAME**: `repo-template` (the original template name)

These defaults work for most users creating repositories directly from the original template.

### When to Use Custom Values

Users should provide custom values when:
- Using a forked version of the template
- Using an organization-specific template variant
- The template has been renamed or moved to a different owner
- Creating documentation for a derivative template

### How These Values Are Collected

The setup script (`pwsh ./scripts/setup.ps1`) prompts for both values with `Read-Input` immediately after the license selection (the "Template repository info" block in `scripts/setup.ps1`), using the defaults above, and adds them to the `$replacements` hashtable as `TEMPLATE_REPO_OWNER` and `TEMPLATE_REPO_NAME`. Refer to the script for the exact prompt text; it is not repeated here so the two cannot drift apart.

### Where These Are Used

Two files use these placeholders:

**`REPO-INSTRUCTIONS.md`** — the "Start with a template" step of the setup instructions:

**Before replacement:**
```markdown
1. `Start with a template` select `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}`
```

**After replacement (using default values):**
```markdown
1. `Start with a template` select `Chris-Wolfgang/repo-template`
```

**After replacement (using custom values):**
```markdown
1. `Start with a template` select `YourUsername/my-template`
```

**`README-TEMPLATE.md`** (renamed to `README.md` during setup) — the "Keeping Up With the Template" section links to `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}` so a generated repository points back at the template it was created from.

### Validation

The setup script validates that these placeholders are properly replaced (along with other core placeholders) before completing. The `$corePlaceholders` array in `scripts/setup.ps1` lists the placeholder names it checks:

```powershell
$corePlaceholders = @(
    'PROJECT_NAME', 'PROJECT_DESCRIPTION', 'PACKAGE_NAME',
    'GITHUB_REPO_URL', 'REPO_NAME', 'GITHUB_USERNAME', 'GITHUB_OWNER',
    'DOCS_URL', 'LICENSE_TYPE',
    'NUGET_STATUS', 'TEMPLATE_REPO_OWNER', 'TEMPLATE_REPO_NAME'
)
```

**Files That Process These Placeholders:**
1. **scripts/setup.ps1** - prompts for the values ("Template repository info" block), adds them to the `$replacements` hashtable, and validates them via `$corePlaceholders`
2. **REPO-INSTRUCTIONS.md** - target file (template selection step)
3. **README-TEMPLATE.md** (renamed to **README.md**) - target file ("Keeping Up With the Template" section)

---

## Files Containing Placeholders

The sections below are keyed by file and placeholder. Line numbers are deliberately not given because they change with every edit; search for the placeholder text instead. The file order matches the list `scripts/setup.ps1` substitutes (print it with `pwsh ./scripts/setup.ps1 -ListFiles`), followed by the license files, which the script handles separately.

To regenerate this catalogue from the tree:

```bash
grep -rnoE '\{\{[A-Z_]+\}\}' --exclude-dir=.git --exclude-dir=obj --exclude-dir=bin .
```

### 1. README.md (After Rename)

**Important:** `README-TEMPLATE.md` becomes `README.md` during setup.

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Main heading |
| `{{PROJECT_DESCRIPTION}}` | Project description |
| `{{PACKAGE_NAME}}` | NuGet version and downloads badges; installation command; NuGet package matrix link; `gh attestation verify` example |
| `{{GITHUB_OWNER}}`, `{{REPO_NAME}}` | PR build badge; release build badge; OpenSSF Scorecard badge; `gh attestation verify` example (`--repo` and `--signer-workflow`) |
| `{{GITHUB_REPO_URL}}` | PR build and release build badge links; GitHub badge link; Documentation link (2 occurrences); clone command |
| `{{REPO_NAME}}` | Directory name after clone |
| `{{LICENSE_TYPE}}` | License badge (2 occurrences); License section |
| `{{DOCS_URL}}` | Coverage badge (2 occurrences); API documentation URL |
| `{{NUGET_STATUS}}` | NuGet availability |
| `{{TEMPLATE_REPO_OWNER}}`, `{{TEMPLATE_REPO_NAME}}` | "Keeping Up With the Template" section (link text and URL) |
| `{{QUICK_START_EXAMPLE}}` | Quick start code (optional, left for you to fill in) |
| `{{FEATURES_TABLE}}` | Features table (optional) |
| `{{FEATURE_EXAMPLES}}` | Feature examples (optional) |
| `{{TARGET_FRAMEWORKS}}` | Supported Frameworks list (optional) |
| `{{ACKNOWLEDGMENTS}}` | Acknowledgments section (optional) |

### 2. CONTRIBUTING.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Main heading; introduction paragraph |

### 3. SECURITY.md

| Placeholder | Context |
|-------------|---------|
| `{{GITHUB_REPO_URL}}` | Private vulnerability report form link |

### 4. .github/CODEOWNERS

| Placeholder | Context |
|-------------|---------|
| `{{GITHUB_USERNAME}}` | Default owner; `.github/` directory; commented-out `src/`, `docs/` and `workflows/` examples (5 occurrences) |

### 5. REPO-INSTRUCTIONS.md

| Placeholder | Context |
|-------------|---------|
| `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}` | Template selection instruction |
| `{{GITHUB_USERNAME}}` | CODEOWNERS update instruction |
| `{{PROJECT_NAME}}`, `{{DOCS_URL}}` | Mentioned as examples in the manual-setup instructions; substituted along with the rest of the file |

### 6. scripts/Setup-BranchRuleset.ps1

| Placeholder | Context |
|-------------|---------|
| `{{GITHUB_OWNER}}/{{REPO_NAME}}` | Default `-Repository` parameter value and the two checks that detect whether it was replaced (3 occurrences) |

**Note:** This file is automatically updated during setup to contain your repository information. After setup, the script will automatically use the correct repository without needing to auto-detect or pass parameters.

`{{GITHUB_OWNER}}` (no `@`) is used because the value is an owner/repo slug for the GitHub API, not an @-mention.

`scripts/Setup-GitHubPages.ps1` and `scripts/Fix-BranchRuleset.ps1` carry the same default but are **not** in the substitution list on purpose: Setup-GitHubPages.ps1 performs its own `{{...}}` replacements in the docfx files and must keep those literals intact, so both scripts auto-detect the repository from `gh repo view` instead.

### 7. BannedSymbols.txt

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Header comment |

### 8. .github/workflows/benchmarks.yaml

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Benchmark project path `benchmarks/{{PROJECT_NAME}}.Benchmarks/...` in the csproj detection, restore, build, run and report steps (6 occurrences) |

### 9. License Files (Selected During Setup)

**LICENSE-MIT.txt:**
- Copyright line: `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`

**LICENSE-APACHE-2.0.txt:**
- Copyright line in the appendix: `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`

**LICENSE-MPL-2.0.txt:**
- No placeholders (license text is complete)
- Copyright notice added separately if needed

**LICENSE-TBD.txt** (option 4, custom/TBD — all rights reserved pending license selection):
- Copyright line: `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`
- Manual setup for this option also requires, because the file alone does not do it:
  1. In `.editorconfig`, replace `file_header_template = unset` with
     `file_header_template = Copyright (c) <holder>. All rights reserved. SPDX-License-Identifier: LicenseRef-TBD`
     and add `dotnet_diagnostic.IDE0073.severity = warning` so the header is enforced under warnings-as-errors.
  2. In `README.md`, replace the "licensed under the **TBD License**" sentence with:
     `This project is **not yet licensed**. All rights reserved pending license selection: no reuse, redistribution, or hosting rights are granted. See the [LICENSE](LICENSE) file.`
  3. Set `{{LICENSE_TYPE}}` to `TBD`.

### 10. docfx_project/docfx.json

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | `_appName`; `_appTitle` |
| `{{DOCS_URL}}` | `_baseUrl` for documentation |

### 11. docfx_project/index.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Main heading; welcome message; About section heading; documentation guides description |
| `{{GITHUB_REPO_URL}}` | GitHub repository link; Additional resources links (3 occurrences) |
| `{{PROJECT_DESCRIPTION}}` | About section |
| `{{PACKAGE_NAME}}` | Installation command |

### 12. docfx_project/api/index.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Welcome message |

### 13. docfx_project/api/README.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Mentioned in the note explaining that the placeholder is replaced; substituted along with the rest of the file |

### 14. docfx_project/docs/toc.yml

| Placeholder | Context |
|-------------|---------|
| `{{GITHUB_REPO_URL}}` | Project website link |

### 15. docfx_project/docs/index.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Main heading of the published documentation index |

### 16. docfx_project/docs/introduction.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Welcome message; Getting help section |
| `{{PROJECT_DESCRIPTION}}` | Overview section |
| `{{GITHUB_REPO_URL}}` | GitHub repository link; GitHub issues link |

### 17. docfx_project/docs/getting-started.md

| Placeholder | Context |
|-------------|---------|
| `{{PROJECT_NAME}}` | Guide title; using statement in code example; Next steps section |
| `{{PACKAGE_NAME}}` | NuGet installation command; Package Manager Console command |
| `{{GITHUB_REPO_URL}}` | GitHub repository links (2 occurrences); Contributing guidelines link; Issue reporting link |

---

## Replacement Process

### Automated (Recommended)

The setup scripts handle all replacements automatically:

```powershell
pwsh ./scripts/setup.ps1
```

### Manual Replacement

If you must replace manually:

1. **README File Swap:**
   ```bash
   rm README.md
   mv README-TEMPLATE.md README.md
   ```

2. **License Setup:**
   - Choose a license template (e.g., `LICENSE-MIT.txt`)
   - Replace `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`
   - Save as `LICENSE` (no extension)
   - Delete all `LICENSE-*.txt` files

3. **Global Find and Replace** in your editor:
   - Search for: `{{PLACEHOLDER_NAME}}`
   - Replace with: `Your Value`
   - Files to search: the list `scripts/setup.ps1` substitutes, which is the single source of truth. Print it with:
     ```bash
     pwsh ./scripts/setup.ps1 -ListFiles
     ```
     At the time of writing it prints:
     - `README.md` (now the renamed template)
     - `CONTRIBUTING.md`
     - `SECURITY.md`
     - `.github/CODEOWNERS`
     - `REPO-INSTRUCTIONS.md`
     - `scripts/Setup-BranchRuleset.ps1`
     - `docfx_project/docfx.json`
     - `docfx_project/index.md`
     - `docfx_project/api/index.md`
     - `docfx_project/api/README.md`
     - `docfx_project/docs/toc.yml`
     - `docfx_project/docs/index.md`
     - `docfx_project/docs/introduction.md`
     - `docfx_project/docs/getting-started.md`
     - `BannedSymbols.txt`
     - `.github/workflows/benchmarks.yaml`

4. **Validation:**
   ```bash
   # Check for remaining placeholders in every file the setup script substitutes,
   # except README.md, which keeps the optional placeholders ({{QUICK_START_EXAMPLE}},
   # {{FEATURES_TABLE}}, {{FEATURE_EXAMPLES}}, {{TARGET_FRAMEWORKS}}, {{ACKNOWLEDGMENTS}})
   # for you to fill in as you develop your project
   grep -nE '\{\{[A-Z_]+\}\}' $(pwsh ./scripts/setup.ps1 -ListFiles | tr -d '\r' | grep -vx 'README.md') || echo "No required placeholders found in core files"

   # Check README.md separately for required placeholders only
   grep -nE '\{\{(PROJECT_NAME|PROJECT_DESCRIPTION|PACKAGE_NAME|GITHUB_REPO_URL|GITHUB_OWNER|REPO_NAME|DOCS_URL|LICENSE_TYPE|NUGET_STATUS|TEMPLATE_REPO_OWNER|TEMPLATE_REPO_NAME)\}\}' README.md && echo "⚠️  Found required placeholders in README.md - please replace them" || echo "✓ All required placeholders replaced in README.md"
   ```

---

## Example Replacement Values

Here's a complete example for a hypothetical project:

```
{{PROJECT_NAME}}              → Wolfgang.Net.HttpClient.Extensions
{{PROJECT_DESCRIPTION}}       → Extension methods for HttpClient with retry policies and resilience
{{PACKAGE_NAME}}              → Wolfgang.Net.HttpClient.Extensions
{{GITHUB_REPO_URL}}           → https://github.com/Chris-Wolfgang/HttpClient-Extensions
{{REPO_NAME}}                 → HttpClient-Extensions
{{GITHUB_USERNAME}}           → @Chris-Wolfgang
{{DOCS_URL}}                  → https://chris-wolfgang.github.io/HttpClient-Extensions/
{{LICENSE_TYPE}}              → MIT
{{YEAR}}                      → 2026
{{COPYRIGHT_HOLDER}}          → Chris Wolfgang
{{NUGET_STATUS}}              → Coming soon to NuGet.org
{{TEMPLATE_REPO_OWNER}}       → Chris-Wolfgang
{{TEMPLATE_REPO_NAME}}        → repo-template
```

---

## Validation Checklist

After replacement, verify:

- [ ] All required placeholders are replaced
- [ ] No `{{...}}` patterns remain in core files
- [ ] README.md exists (from README-TEMPLATE.md)
- [ ] LICENSE file exists (no .txt extension)
- [ ] CODEOWNERS has your GitHub username
- [ ] CONTRIBUTING.md has your project name
- [ ] All URLs are correct and accessible
- [ ] License type matches your LICENSE file

---

## Troubleshooting

### Issue: Placeholder not found in file

**Cause:** The file may have been manually edited before running setup.

**Solution:** Check the file manually or re-clone from template.

### Issue: Wrong value auto-detected

**Cause:** Git configuration or remote URL is incorrect.

**Solution:** The setup script allows manual override of all values.

### Issue: Remaining placeholders after setup

**Cause:** Some placeholders are intentionally left for users to fill (e.g., `{{QUICK_START_EXAMPLE}}`).

**Solution:** Fill these in as you develop your project.

---

## Additional Resources

- **Setup Script:** `pwsh ./scripts/setup.ps1`
- **Repository Instructions:** [REPO-INSTRUCTIONS.md](REPO-INSTRUCTIONS.md)
- **Template README:** [README.md](README.md) (describes template)
- **Project README Template:** [README-TEMPLATE.md](README-TEMPLATE.md)

---

## Contributing

Found an issue with placeholder documentation? Please open an issue or submit a pull request!
