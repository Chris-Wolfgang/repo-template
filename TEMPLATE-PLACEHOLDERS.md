# Template Placeholders Documentation

This document provides comprehensive documentation of all placeholders used in this repository template and instructions for replacing them.

## Overview

The automated setup scripts (`scripts/setup.ps1` and `scripts/setup.sh`) handle all placeholder replacements automatically. This document is for reference or manual setup if needed.

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
| `{{GITHUB_REPO_URL}}` | Full GitHub repository URL | `https://github.com/Chris-Wolfgang/MyProject` | Yes (from `git remote`) |
| `{{REPO_NAME}}` | Repository name only | `MyProject` | Yes (extracted from URL) |
| `{{GITHUB_USERNAME}}` | GitHub username with @ | `@Chris-Wolfgang` | Yes (from GitHub repo URL, or prompted if missing) |
| `{{DOCS_URL}}` | Documentation URL | `https://chris-wolfgang.github.io/MyProject/` | Yes (generated from repo URL) |
| `{{LICENSE_TYPE}}` | License identifier | `MIT`, `Apache-2.0`, or `MPL-2.0` | No |
| `{{YEAR}}` | Copyright year | `2024` | Yes (current year) |
| `{{COPYRIGHT_HOLDER}}` | Copyright owner name | `Chris Wolfgang` | Yes (from `git config`) |
| `{{NUGET_STATUS}}` | NuGet availability message | `Coming soon to NuGet.org` or `Available on NuGet.org` | No |
| `{{TEMPLATE_REPO_OWNER}}` | Template repository owner | `Chris-Wolfgang` | No |
| `{{TEMPLATE_REPO_NAME}}` | Template repository name | `repo-template` | No |

---

## Optional Content Placeholders

These placeholders represent sections that users should fill in later. They can remain as placeholders initially:

| Placeholder | Purpose | Location |
|------------|---------|----------|
| `{{QUICK_START_EXAMPLE}}` | Code example showing basic usage | README.md |
| `{{FEATURES_TABLE}}` | Markdown table listing features | README.md |
| `{{FEATURE_EXAMPLES}}` | Code examples demonstrating features | README.md |
| `{{TARGET_FRAMEWORKS}}` | List of supported .NET frameworks | README.md |
| `{{ACKNOWLEDGMENTS}}` | Credits for libraries/tools used | README.md |

**Note:** The automated setup scripts do NOT replace these - users fill them in as they develop their project.

---

## Files Containing Placeholders

### 1. README.md (After Rename)

**Important:** `README-TEMPLATE.md` becomes `README.md` during setup.

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 1 | `{{PROJECT_NAME}}` | Main heading |
| 3 | `{{PROJECT_DESCRIPTION}}` | Project description |
| 5 | `{{LICENSE_TYPE}}` | License badge |
| 7 | `{{GITHUB_REPO_URL}}` | GitHub badge link |
| 13 | `{{PACKAGE_NAME}}` | Installation command |
| 16 | `{{NUGET_STATUS}}` | NuGet availability |
| 21 | `{{LICENSE_TYPE}}` | License section |
| 27 | `{{GITHUB_REPO_URL}}` | Documentation link (2 occurrences) |
| 28 | `{{DOCS_URL}}` | API documentation URL |
| 35 | `{{QUICK_START_EXAMPLE}}` | Quick start code |
| 41 | `{{FEATURES_TABLE}}` | Features table |
| 44 | `{{FEATURE_EXAMPLES}}` | Feature examples |
| 50 | `{{TARGET_FRAMEWORKS}}` | Framework list |
| 119 | `{{GITHUB_REPO_URL}}` | Clone command |
| 120 | `{{REPO_NAME}}` | Directory name |
| 197 | `{{ACKNOWLEDGMENTS}}` | Acknowledgments section |

### 2. CONTRIBUTING.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 1 | `{{PROJECT_NAME}}` | Main heading |
| 3 | `{{PROJECT_NAME}}` | Introduction paragraph |

### 3. .github/CODEOWNERS

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 5 | `{{GITHUB_USERNAME}}` | Default owner |
| 8 | `{{GITHUB_USERNAME}}` | src/ directory (commented) |
| 11 | `{{GITHUB_USERNAME}}` | docs/ directory (commented) |
| 14 | `{{GITHUB_USERNAME}}` | workflows/ directory (commented) |
| 17 | `{{GITHUB_USERNAME}}` | .github/ directory |

### 4. REPO-INSTRUCTIONS.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 46 | `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}` | Template selection instruction |
| ~135 | `{{GITHUB_USERNAME}}` | CODEOWNERS update instruction |

### 5. scripts/Setup-BranchRuleset.ps1

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 37 | `{{GITHUB_USERNAME}}/{{REPO_NAME}}` | Default repository parameter |

**Note:** This file is automatically updated during setup to contain your repository information. After setup, the script will automatically use the correct repository without needing to auto-detect or pass parameters.

### 6. License Files (Selected During Setup)

**LICENSE-MIT.txt:**
- Line 3: `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`

**LICENSE-APACHE-2.0.txt:**
- Line 189: `{{YEAR}}` and `{{COPYRIGHT_HOLDER}}`

**LICENSE-MPL-2.0.txt:**
- No placeholders (license text is complete)
- Copyright notice added separately if needed

### 6. docfx_project/docfx.json

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 46 | `{{PROJECT_NAME}}` | Application name |
| 47 | `{{PROJECT_NAME}}` | Application title |
| 53 | `{{DOCS_URL}}` | Base URL for documentation |

### 7. docfx_project/index.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 5 | `{{PROJECT_NAME}}` | Main heading |
| 7 | `{{PROJECT_NAME}}` | Welcome message |
| 13 | `{{GITHUB_REPO_URL}}` | GitHub repository link |
| 15 | `{{PROJECT_NAME}}` | About section |
| 17 | `{{PROJECT_DESCRIPTION}}` | About section |
| 22 | `{{PACKAGE_NAME}}` | Installation command |
| 35-37 | `{{GITHUB_REPO_URL}}` | Additional resources links (3 occurrences) |

### 8. docfx_project/api/index.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 3 | `{{PROJECT_NAME}}` | Welcome message |

### 9. docfx_project/docs/toc.yml

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| Various | `{{GITHUB_REPO_URL}}` | Project website link |

### 10. docfx_project/docs/introduction.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| Various | `{{PROJECT_NAME}}`, `{{PROJECT_DESCRIPTION}}` | Introduction headings and descriptive text |
| Various | `{{GITHUB_REPO_URL}}` | Links back to the GitHub repository from the introduction |

### 11. docfx_project/docs/getting-started.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| Various | `{{PROJECT_NAME}}` | Getting started headings and examples |
| Various | `{{PACKAGE_NAME}}` | NuGet installation and package reference snippets |
| Various | `{{GITHUB_REPO_URL}}` | Links to source code, issues, and documentation on GitHub |

### 9. docfx_project/docs/toc.yml

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 8 | `{{GITHUB_REPO_URL}}` | Project website link |

### 10. docfx_project/docs/introduction.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 3 | `{{PROJECT_NAME}}` | Welcome message |
| 7 | `{{PROJECT_DESCRIPTION}}` | Overview section |
| 21 | `{{PROJECT_NAME}}` | Getting help section |
| 25 | `{{GITHUB_REPO_URL}}` | GitHub repository link |
| 26 | `{{GITHUB_REPO_URL}}` | GitHub issues link |

### 11. docfx_project/docs/getting-started.md

| Line(s) | Placeholder | Context |
|---------|-------------|---------|
| 3 | `{{PROJECT_NAME}}` | Guide title |
| 17 | `{{PACKAGE_NAME}}` | NuGet installation command |
| 23 | `{{PACKAGE_NAME}}` | Package Manager Console command |
| 34 | `{{PROJECT_NAME}}` | Using statement in code example |
| 42 | `{{PROJECT_NAME}}` | Next steps section |
| 43 | `{{GITHUB_REPO_URL}}` | GitHub repository link |
| 51 | `{{GITHUB_REPO_URL}}` | Additional resources |
| 52 | `{{GITHUB_REPO_URL}}` | Contributing guidelines link |
| 53 | `{{GITHUB_REPO_URL}}` | Issue reporting link |

---

## Replacement Process

### Automated (Recommended)

The setup scripts handle all replacements automatically:

```bash
# PowerShell
pwsh ./scripts/setup.ps1

# Bash
./scripts/setup.sh
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
   - Files to search:
     - `README.md` (now the renamed template)
     - `CONTRIBUTING.md`
     - `.github/CODEOWNERS`
     - `REPO-INSTRUCTIONS.md`
     - `LICENSE-SELECTION.md`
     - `docfx_project/docfx.json`
     - `docfx_project/index.md`
     - `docfx_project/api/index.md`
     - `docfx_project/api/README.md`
     - `docfx_project/docs/toc.yml`
     - `docfx_project/docs/introduction.md`
     - `docfx_project/docs/getting-started.md`

4. **Validation:**
   ```bash
   # Check for remaining required placeholders
   # Note: README.md will still contain optional placeholders like {{QUICK_START_EXAMPLE}},
   # {{FEATURES_TABLE}}, {{FEATURE_EXAMPLES}}, {{TARGET_FRAMEWORKS}}, {{ACKNOWLEDGMENTS}}
   # which you fill in as you develop your project
   grep -r "{{.*}}" CONTRIBUTING.md .github/CODEOWNERS REPO-INSTRUCTIONS.md LICENSE-SELECTION.md docfx_project/ || echo "No required placeholders found in core files"
   
   # Check README.md separately for required placeholders only
   grep -E "{{(PROJECT_NAME|PROJECT_DESCRIPTION|PACKAGE_NAME|GITHUB_REPO_URL|REPO_NAME|DOCS_URL|LICENSE_TYPE|NUGET_STATUS)}}" README.md && echo "⚠️  Found required placeholders in README.md - please replace them" || echo "✓ All required placeholders replaced in README.md"
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
{{YEAR}}                      → 2024
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

- **Setup Scripts:** `scripts/setup.ps1`, `scripts/setup.sh`
- **License Selection Guide:** [LICENSE-SELECTION.md](LICENSE-SELECTION.md)
- **Repository Instructions:** [REPO-INSTRUCTIONS.md](REPO-INSTRUCTIONS.md)
- **Template README:** [README.md](README.md) (describes template)
- **Project README Template:** [README-TEMPLATE.md](README-TEMPLATE.md)

---

## Contributing

Found an issue with placeholder documentation? Please open an issue or submit a pull request!
