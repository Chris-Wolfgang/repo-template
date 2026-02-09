# .NET Repository Template

A comprehensive, production-ready .NET repository template with enterprise-grade CI/CD, comprehensive code quality enforcement, automated documentation generation, and multi-license support.

## 🚀 Quick Start

1. **Create repository from template** - Click "Use this template" on GitHub
2. **Clone your new repository**
3. **Run automated setup:**
   ```bash
   # PowerShell (Windows/macOS/Linux)
   pwsh ./setup.ps1
   
   # Or Bash (macOS/Linux)
   chmod +x setup.sh
   ./setup.sh
   ```
4. **Follow the prompts** - The script will guide you through customization
5. **Commit and push** - Your repository is ready!

The setup script automatically:
- ✅ Replaces all placeholders with your project information
- ✅ Swaps template README with project-specific README
- ✅ Sets up your chosen license (MIT, Apache 2.0, or MPL 2.0)
- ✅ Validates all changes
- ✅ Optionally cleans up template files

---

## ✨ What's Included

### 🔍 Code Quality Enforcement (7 Analyzers)

All code is analyzed during builds by these industry-standard tools:

1. **Microsoft.CodeAnalysis.NetAnalyzers** - Built-in .NET correctness, performance, and security
2. **Roslynator.Analyzers** - 500+ refactoring and code quality rules
3. **AsyncFixer** - Async/await anti-pattern detection
4. **Microsoft.VisualStudio.Threading.Analyzers** - Thread safety and async patterns
5. **Microsoft.CodeAnalysis.BannedApiAnalyzers** - Blocks banned APIs via `BannedSymbols.txt`
6. **Meziantou.Analyzer** - Comprehensive code quality and performance checks
7. **SonarAnalyzer.CSharp** - Industry-standard code analysis and security

**Result:** Enforces async-first patterns, prevents common mistakes, and maintains consistent code quality.

### 🔐 Security & Safety

- **DevSkim** security scanning in CI/CD
- **CodeQL** analysis for vulnerability detection
- **BannedSymbols.txt** - Prevents usage of dangerous/obsolete APIs:
  - ❌ `Task.Wait()`, `Task.Result` → Use `await` instead
  - ❌ `Thread.Sleep()` → Use `await Task.Delay()`
  - ❌ Synchronous I/O → Use async versions
  - ❌ Obsolete APIs (`WebClient`, `BinaryFormatter`)

### 📦 CI/CD Workflows

#### Pull Request Workflow (`.github/workflows/pr.yaml`)
- **Multi-stage testing** across Linux, Windows, macOS
- **Multi-framework testing** (.NET 5.0-10.0, .NET Framework 4.6.2-4.8.1)
- **Code coverage** with 90% threshold enforcement
- **Security scanning** with DevSkim
- **Coverage reports** as build artifacts
- **Branch protection** integration

#### Release Workflow (`.github/workflows/release.yaml`)
- **Automated NuGet publishing** on version tags (e.g., `v1.0.0`)
- **Package signing** (if configured)
- **GitHub Releases** with changelogs
- **Multi-targeting** support

#### Documentation Workflow (`.github/workflows/docfx.yaml`)
- **Automatic DocFX builds** on pushes to main
- **GitHub Pages deployment** for API documentation
- **Live documentation** at `https://<username>.github.io/<repo>/`

#### Additional Workflows
- **CodeQL** security analysis
- **Dependabot** automated dependency updates - Automatically creates PRs to keep NuGet packages up-to-date with security patches and new versions
- **Label automation** for Dependabot PRs
- **PR template** with comprehensive checklists

### 📚 Documentation System

- **DocFX integration** for API documentation
- **Automatic builds** and deployment to GitHub Pages
- **Local preview** support with `docfx build --serve`
- **Markdown + API reference** combined documentation
- **Live API Reference** at `https://<username>.github.io/<repo>/api/`

### 🎨 Code Style & Formatting

- **Comprehensive `.editorconfig`** with 200+ rules
- **Automated formatting** via `dotnet format`
- **Consistent style** across team members
- **CI enforcement** with `dotnet format --verify-no-changes`

Key style rules:
- 4-space indentation for C#
- File-scoped namespaces (C# 10+)
- PascalCase for public members
- camelCase for parameters/locals
- Unix-style line endings (LF)

### 📋 Project Structure

```
root/
├── .github/
│   ├── workflows/          # CI/CD pipelines
│   ├── ISSUE_TEMPLATE/     # Issue templates
│   ├── CODEOWNERS          # Code review assignments
│   └── dependabot.yml      # Dependency updates
├── src/                    # Application projects
├── tests/                  # Test projects
├── benchmarks/             # Performance benchmarks (optional)
├── examples/               # Example projects (optional)
├── docfx_project/          # DocFX documentation
├── docs/                   # Generated documentation
├── .editorconfig           # Code style rules
├── .gitignore              # Comprehensive .NET gitignore
├── .globalconfig           # Global analyzer config
├── BannedSymbols.txt       # Banned API list
├── Directory.Build.props   # Shared MSBuild properties
├── Solution.slnx           # Solution file
├── LICENSE                 # Project license
├── README.md               # Project README (from README-TEMPLATE.md)
├── CONTRIBUTING.md         # Contribution guidelines
├── CODE_OF_CONDUCT.md      # Contributor Covenant
└── format.ps1              # Code formatting script
```

### 🏷️ License Options

Choose from three popular open-source licenses or add your own during setup:

| License | Best For | Key Characteristics |
|---------|----------|---------------------|
| **MIT** | Maximum freedom, libraries | Permissive, minimal restrictions |
| **Apache 2.0** | Patent protection, enterprise | Permissive + patent grant |
| **MPL 2.0** | File-level copyleft | Weak copyleft, file-based |

See [LICENSE-SELECTION.md](LICENSE-SELECTION.md) for detailed comparison and guidance.
> **NOTE** You will be prompted for a license when you run the setup (setup.ps1 or setup.sh)

---

## 📖 Template Setup Instructions

### Automated Setup (Recommended)

The template includes automated setup scripts that handle all configuration:

#### PowerShell (Cross-platform - Windows/macOS/Linux)

```powershell
pwsh ./setup.ps1
```

#### Bash (macOS/Linux)

```bash
chmod +x setup.sh
./setup.sh
```

The scripts will:
1. Prompt for project information (with examples and defaults)
2. Auto-detect git repository details where possible
3. Replace all placeholders in template files
4. **Delete** the template README.md
5. **Rename** README-TEMPLATE.md → README.md
6. Set up chosen LICENSE with copyright information
7. Remove unused license templates
8. Validate all replacements
9. Optionally clean up template files

### What You'll Be Asked

| Prompt | Example | Auto-detected? |
|--------|---------|----------------|
| Project Name | `Wolfgang.MyProject.MyLib` | No |
| Description | `High-performance extension methods...` | No |
| Package Name | `Wolfgang.MyProject.MyLib` | No |
| Repository URL | `https://github.com/Chris-Wolfgang/MyProject` | Yes (from git) |
| Repository Name | `MyProject` | Yes (from URL) |
| GitHub Username | `@Chris-Wolfgang` | Yes (from git) |
| Docs URL | `https://chris-wolfgang.github.io/MyProject/` | Yes (generated) |
| License Type | `MIT`, `Apache-2.0`, or `MPL-2.0` | No |
| Copyright Holder | `Chris Wolfgang` | Yes (from git) |
| NuGet Status | `Coming soon to NuGet.org` | No |

**Note:** The setup scripts handle the placeholders above. Additional optional content placeholders (`{{QUICK_START_EXAMPLE}}`, `{{FEATURES_TABLE}}`, `{{FEATURE_EXAMPLES}}`, `{{TARGET_FRAMEWORKS}}`, `{{ACKNOWLEDGMENTS}}`) remain in your README.md for you to fill in as you develop your project. See [TEMPLATE-PLACEHOLDERS.md](TEMPLATE-PLACEHOLDERS.md) for details.

### Manual Setup (Not Recommended)

If you prefer manual setup, see [TEMPLATE-PLACEHOLDERS.md](TEMPLATE-PLACEHOLDERS.md) for a complete list of placeholders and instructions.

---

## 🧪 Quality Standards

### Code Coverage
- **Minimum:** 90% line coverage (enforced in CI)
- **Reports:** Generated with ReportGenerator
- **Formats:** HTML, Markdown, CSV

### Test Strategy
- Unit tests in `/tests` folder
- Pattern: `*Test*.csproj` for test projects
- Coverage collection with `XPlat Code Coverage`

### Build Configuration
- **Debug:** Warnings allowed (development)
- **Release:** Warnings treated as errors (CI)
- **Multi-targeting:** Supports .NET 5.0-10.0 + .NET Framework 4.6.2-4.8.1

### Security Scanning
- **DevSkim:** CLI-based security analysis
- **CodeQL:** Vulnerability detection
- **Results:** Included in PR checks

---

## 📁 Repository Contents

### Core Files

| File | Purpose |
|------|---------|
| `README.md`* | **THIS FILE** - Gets replaced by the README-TEMPLATE.md file during setup |
| `README-TEMPLATE.md`* | Project README template (becomes `README.md`) |
| `TEMPLATE-PLACEHOLDERS.md` | Complete placeholder documentation |
| `LICENSE-SELECTION.md` | License comparison and selection guide |
| `REPO-INSTRUCTIONS.md` | Manual setup instructions |
| `setup.ps1` | PowerShell setup automation |
| `setup.sh` | Bash setup automation |

> **\* NOTE:** The README.md file for the `repo-template` repository (this file) will be replaced by the README-TEMPLATE.md when you run the setup (setup.ps1 or setup.sh). The README-TEMPLATE.md file we renamed to README.md and will be a customized starter README.md file for your repository.

### License Templates

| File | License Type |
|------|--------------|
| `LICENSE-MIT.txt` | MIT License template |
| `LICENSE-APACHE-2.0.txt` | Apache License 2.0 template |
| `LICENSE-MPL-2.0.txt` | Mozilla Public License 2.0 template |

### Configuration Files

| File | Purpose |
|------|---------|
| `.editorconfig` | Code style rules (200+ settings) |
| `.globalconfig` | Global analyzer configuration |
| `BannedSymbols.txt` | Banned API list |
| `Directory.Build.props` | Shared MSBuild properties |
| `.gitignore` | Comprehensive .NET gitignore |
| `.gitattributes` | Git attributes |

### GitHub Integration

| Location | Purpose |
|----------|---------|
| `.github/workflows/` | CI/CD pipeline definitions |
| `.github/ISSUE_TEMPLATE/` | Bug and feature request templates |
| `.github/CODEOWNERS` | Code review assignments |
| `.github/dependabot.yml` | Dependency update configuration |
| `.github/pull_request_template.md` | PR template with checklists |

---

## 🎯 After Setup

Once you've run the setup script and committed the changes:

### 1. Configure Branch Protection

For manual configuration using the GitHub rulesets UI, go to **Settings → Rules → Rulesets** and configure the rule that applies to your default branch with:
- ✅ Require status checks before merging
- ✅ Require branches to be up to date
- ✅ Require pull request reviews (recommended for multi-developer repos)
- ✅ Require code owner review (recommended for multi-developer repos)
- ✅ Require Copilot review
- ✅ Restrict deletions
- ✅ Block force pushes
- ✅ Require code scanning

### 2. Set Up Release Workflow (Optional)

If publishing to NuGet:
1. Go to **Settings → Secrets → Actions**
2. Add secret: `NUGET_API_KEY`
3. Get API key from [NuGet.org](https://www.nuget.org/account/apikeys)

See [RELEASE-WORKFLOW-SETUP.md](RELEASE-WORKFLOW-SETUP.md) for details.

### 3. Create Your Projects

```bash
# Create solution
dotnet new sln -n MySolution

# Create projects
dotnet new classlib -o src/MyLib
dotnet new xunit -o tests/MyLib.Tests.Integration
dotnet new xunit -o tests/MyLib.Tests.Unit

# Add to solution
dotnet sln add src/MyLib/MyLib.csproj
dotnet sln add tests/MyLib.Tests/MyLib.Tests.Integration.csproj
dotnet sln add tests/MyLib.Tests/MyLib.Tests.Unit.csproj
```

### 4. Start Developing!

Your repository now has:
- ✅ All analyzers configured
- ✅ CI/CD pipelines ready
- ✅ Documentation system set up
- ✅ Code quality enforcement enabled
- ✅ Security scanning active
- ✅ Professional README
- ✅ Proper licensing

---

## 📚 Additional Resources

- **Formatting Guide:** [README-FORMATTING.md](README-FORMATTING.md)
- **Contributing Guide:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Code of Conduct:** [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- **Release Workflow:** [RELEASE-WORKFLOW-SETUP.md](RELEASE-WORKFLOW-SETUP.md)
- **Setup Instructions:** [REPO-INSTRUCTIONS.md](REPO-INSTRUCTIONS.md)
<!-- -**API Reference:** `https://<username>.github.io/<repo>/api/` (live documentation)-->

---

## 🔒 Automated Security & Branch Protection

This template includes automated security scanning and branch protection that configures itself on first use.

### What's Included

#### 🛡️ Security Scanning
- **CodeQL Analysis** - Scans C# code for security vulnerabilities weekly and on every PR
- **DevSkim Security Scan** - Detects security anti-patterns in code

#### 🔐 Branch Protection (Main Branch)
Automatically configured on first push to main:

> **Single-Developer Configuration:** This template is configured for single-developer use, so the default ruleset does **not** require pull request approvals or code owner reviews (0 required approvals). For multi-developer or release-workflow scenarios (as described in `RELEASE-WORKFLOW-SETUP.md`), update `.github/ruleset-config.json` to set `required_approving_review_count` to 1+ and `require_code_owner_review` to `true` to match the recommended “Required approvals: 1 (minimum)” guidance.

- ✅ **Require pull requests** before merging
- ✅ **Require all status checks to pass:**
  - Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate
  - Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)
  - Stage 3: macOS Tests (.NET 6.0-10.0)
  - Security Scan (DevSkim)
  - Security Scan (CodeQL)
- ✅ **Require branches to be up to date** before merging
- ✅ **Require conversation resolution** before merging
- ✅ **Dismiss stale reviews** when new commits are pushed
- ✅ **Block force pushes** to main
- ✅ **Prevent branch deletion**
- ✅ **Repository admins can bypass** these rules

> **Note for Single Developer Repositories:** By default, this template is configured for single developer use with `"required_approving_review_count": 0` and `"require_code_owner_review": false` in `.github/ruleset-config.json`. This allows you to merge your own PRs without additional approvals while still benefiting from CI/CD checks.
>
> **For Multi-Developer Repositories:** Update `.github/ruleset-config.json` before first push to require at least one approval and code owner review:
> ```json
> {
>   "type": "pull_request",
>   "parameters": {
>     "required_approving_review_count": 1,
>     "dismiss_stale_reviews_on_push": true,
>     "require_code_owner_review": true,
>     "require_last_push_approval": false,
>     "required_review_thread_resolution": true
>   }
> }
> ```

#### 🔍 Code Quality Gates
- **CodeQL:** Blocks merges on High or Critical security findings
- **Code Quality:** Blocks merges on errors

### How It Works

1. **Create repository** from this template
2. **Make your first commit** and push to main
3. **Automatic setup runs** - Branch protection configures itself
4. **Clean up setup workflow** - After it succeeds, delete `.github/workflows/setup-branch-ruleset.yml`

No manual ruleset configuration needed—only a one-time deletion of the setup workflow file. 🎉

### For Template Users

If you're using this template, the branch protection will automatically apply to **your** repository with **you** as the admin who can bypass rules. The configuration is portable and works for every repo created from this template.

### Customization

To modify the branch protection rules, edit `.github/ruleset-config.json` before the first push, or update the ruleset manually in Settings → Rules → Rulesets after setup.

---

## ⚡ Key Features Summary

✅ **7 Code Analyzers** - Comprehensive quality enforcement  
✅ **Multi-Platform CI/CD** - Linux, Windows, macOS  
✅ **Multi-Framework** - .NET 5.0-10.0 + Framework 4.6.2-4.8.1  
✅ **90% Coverage Requirement** - Automated enforcement  
✅ **Security Scanning** - DevSkim + CodeQL  
✅ **Automated Documentation** - DocFX + GitHub Pages  
✅ **3 License Options** - MIT, Apache 2.0, MPL 2.0  
✅ **Setup Automation** - PowerShell + Bash scripts  
✅ **Professional Structure** - Industry best practices  

---

## 🤝 Contributing to the Template

Found a bug or want to improve the template itself? Contributions are welcome!

1. Fork this template repository
2. Make your improvements
3. Submit a pull request
4. Describe your changes

---

## 📄 Template License

This template is licensed under the **MIT License**.

Projects created from this template can use any license - the setup script offers MIT, Apache 2.0, or MPL 2.0.

---

## 🙏 Credits

Created by [Chris Wolfgang](https://github.com/Chris-Wolfgang) and Copilot

Built with:
- .NET 8.0+ SDK
- DocFX for documentation
- Multiple Roslyn analyzers
- GitHub Actions for CI/CD
- ReportGenerator for coverage
- DevSkim for security

---



**Ready to create production-grade .NET projects?** Click "Use this template" above! 🚀
