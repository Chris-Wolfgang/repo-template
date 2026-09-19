# .NET Repository Template

[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/Chris-Wolfgang/repo-template/badge)](https://scorecard.dev/viewer/?uri=github.com/Chris-Wolfgang/repo-template)

A comprehensive, production-ready .NET repository template with enterprise-grade CI/CD, comprehensive code quality enforcement, automated documentation generation, and multi-license support.

## 📋 Prerequisites

Before using this template, ensure you have the following installed:

- **PowerShell Core 7.0+** - Cross-platform PowerShell
  - Windows: `winget install Microsoft.PowerShell`
  - macOS: `brew install powershell`
  - Linux: [Install instructions](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)
- **GitHub CLI (gh)** - For branch protection, labels, Pages and the setup PR
  - Windows: `winget install GitHub.cli`
  - macOS: `brew install gh`
  - Linux: [Install instructions](https://cli.github.com/)
- **.NET SDK** - the current LTS/STS SDK (10.0 at the time of writing); older SDKs are installed by CI for the multi-target matrix
- **gitleaks** (optional) - `winget install gitleaks` / `brew install gitleaks`; enables the pre-commit secret scan (`git config core.hooksPath .githooks`)

## 🚀 Quick Start

1. **Create repository from template** - Click "Use this template" on GitHub
2. **Clone your new repository** - Clone to your local computer
3. **Run the automated setup and follow the prompts**
   ```powershell
   pwsh ./scripts/setup.ps1
   ```
   - The script will ask you for required values and read other details from your git configuration and repository,
   - Replaces all placeholders with your project information,
   - Creates a branch, commits the changes and pushes it to your repository
   - Creates a pull request for you to review and merge if approved
4. **Merge your changes** - Review the pull request created in the previous step and merge it into `main`
5. **Authenticate with GitHub CLI** - Required for branch protection setup:
   ```bash
   gh auth login
   ```
   Follow the prompts to authenticate. You only need to do this once per machine.
6. **Set up branch protection** - Configure branch protection rules:
   ```powershell
   pwsh ./scripts/Setup-BranchRuleset.ps1
   ```
   
   The script will ask if you want:
   - **Single Developer**: No PR approvals required (you can merge your own PRs)
   - **Multi-Developer**: Requires 1+ approval and code owner review
7. **(Optional) Set up issue labels** - Create standard labels for issues and PRs:
   ```powershell
   pwsh ./scripts/Setup-Labels.ps1
   ```
8. **(Optional) Set up GitHub Pages for documentation** - Configure DocFX and enable documentation:
   ```powershell
   pwsh ./scripts/Setup-GitHubPages.ps1
   ```

   The script will:
   - Configure DocFX documentation files with your project details
   - Create a gh-pages branch for hosting documentation
   - Enable GitHub Pages in repository settings
   - Your docs will be live at `https://<username>.github.io/<repo>/`
9. **(Optional) Create the maintenance tracker** - Opens the evergreen "Maintenance: <repo>" issue with its category sub-issues. Requires the labels from step 7 (`maintenance`, `maintenance-task`, `maintenance - <category>`) and the URL of the GitHub Projects board the tasks roll up to:
   ```powershell
   pwsh ./scripts/Setup-Maintenance.ps1 -MaintenanceProjectUrl https://github.com/users/<username>/projects/<n>
   ```
10. **Enable the pre-commit secret scan** (once per clone): `git config core.hooksPath .githooks`
11. **Your repository is ready!** - Branch protection is now configured and enforcing CI/CD checks

The setup script automatically:
- ✅ Replaces all placeholders with your project information
- ✅ Swaps template README with project-specific README
- ✅ Sets up your chosen license (MIT, Apache 2.0, MPL 2.0, or custom/TBD — all rights reserved pending selection)
- ✅ Validates all changes
- ✅ Optionally cleans up template files

---

## ✨ What's Included

### 🔍 Code Quality Enforcement (7 Analyzers + 1 Opt-in)

All code is analyzed during builds by these industry-standard tools:

1. **Microsoft.CodeAnalysis.NetAnalyzers** - Built-in .NET correctness, performance, and security
2. **Roslynator.Analyzers** - 500+ refactoring and code quality rules
3. **AsyncFixer** - Async/await anti-pattern detection
4. **Microsoft.VisualStudio.Threading.Analyzers** - Thread safety and async patterns
5. **Microsoft.CodeAnalysis.BannedApiAnalyzers** - Blocks banned APIs via `BannedSymbols.txt`
6. **Meziantou.Analyzer** - Comprehensive code quality and performance checks
7. **SonarAnalyzer.CSharp** - Industry-standard code analysis and security
8. **Microsoft.CodeAnalysis.PublicApiAnalyzers** (opt-in) - Tracks the public API surface; activates for a project that carries `PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt`

Plus **ReSharper InspectCode** on every PR (a different rule set from the Roslyn analyzers, results in the Security tab) and `GenerateDocumentationFile` on for every `src/` project, so undocumented public members fail the Release build.

**Result:** Enforces async-first patterns, prevents common mistakes, and maintains consistent code quality.

### 🔐 Security & Safety

- **gitleaks** secret scanning - pre-commit hook and a PR check (default rules + `.gitleaks.toml` allowlist)
- **DevSkim** security scanning in CI/CD
- **CodeQL** analysis (security-extended query pack) on every PR and weekly
- **Semgrep** (C# + security-audit + secrets rule packs)
- **actionlint + zizmor** audit of the workflow files themselves; High-severity zizmor findings fail the PR
- **OpenSSF Scorecard** weekly, with the badge in the README
- **License audit** of the full transitive dependency closure against an OSI-permissive allow-list, and a **CycloneDX SBOM** per package
- **Nightly security-alert triage** - opens an issue per new Dependabot / code-scanning / secret-scanning alert and closes it when the alert closes
- **SLSA build-provenance attestation** on every published package; **NuGet trusted publishing** (OIDC) - no stored API key
- **Every action pinned by commit SHA**; Dependabot keeps the pins moving
- **BannedSymbols.txt** - Prevents usage of dangerous/obsolete APIs:
  - ❌ `Task.Wait()`, `Task.Result` → Use `await` instead
  - ❌ `Thread.Sleep()` → Use `await Task.Delay()`
  - ❌ Synchronous I/O → Use async versions
  - ❌ Obsolete APIs (`WebClient`, `BinaryFormatter`)

### 📦 CI/CD Workflows

#### Pull Request Workflow (`.github/workflows/pr.yaml`)
- **Multi-stage testing** across Linux, Windows, macOS
- **Multi-framework testing** (.NET Core 3.1, .NET 5.0-10.0, .NET Framework 4.6.2-4.8.1) - every TFM of every test project, discovered at run time; a TFM that runs zero tests fails
- **Code coverage gates** - 90 % line coverage for `src/`, 100 % for `tests/`
- **Protected-file guard** - the workflow runs from `main` (`pull_request_target`) and re-fetches `.editorconfig`, `Directory.Build.props`, `BannedSymbols.txt`, `*.DotSettings`, workflows, ... from `main`; a PR that changes them is held for maintainer review ([docs/WORKFLOW_SECURITY.md](docs/WORKFLOW_SECURITY.md))
- **Changelog fragment check** - a PR touching `src/` must add `changelog/unreleased/<name>.md` or carry the `no-changelog` label
- **gitleaks** (check log), **DevSkim** (text artifact), **ReSharper InspectCode** (SARIF to the Security tab), **coverage reports** (artifact per stage)
- **Local mirror** - `pwsh ./scripts/build-pr.ps1` reproduces the Windows stage on your machine

#### Release Workflow (`.github/workflows/release.yaml`)
- Triggered by **publishing a GitHub Release**; the tag must match a `<Version>` or `<PackageVersion>` declared under `src/`
- **Full-matrix tests + coverage gates**, then **pack**, **smoke-test install**, **SBOM**
- **DocFX build verified** before anything is published
- **SLSA build-provenance attestation** per package, then **NuGet publish via trusted publishing**
- **Versioned docs deploy** to GitHub Pages; packages, SBOM and coverage report **attached to the Release**

#### Documentation Workflow (`.github/workflows/docfx.yaml`)
- **Called by the release workflow** (or run manually) - builds DocFX and deploys to `gh-pages` under `versions/<tag>/` plus `versions/latest/`
- **Version picker** on every page, previous versions preserved
- **Live documentation** at `https://<username>.github.io/<repo>/`; validate a deploy with `pwsh ./scripts/Validate-DocsDeploy.ps1`

#### Additional Workflows
- **codeql.yaml** - CodeQL security analysis (PRs + weekly)
- **actions-audit.yaml** - actionlint + zizmor on the workflow files
- **scorecard.yaml** - OpenSSF Scorecard (weekly)
- **semgrep.yaml**, **license-audit.yaml**, **sbom.yaml**, **sourcelink.yaml** - SAST, license allow-list, SBOM, SourceLink verification
- **security-alerts.yml** - nightly alert → issue triage
- **stryker.yaml** - mutation testing (weekly); **benchmarks.yaml** - BenchmarkDotNet results to gh-pages; **build-all-versions.yaml**
- **Dependabot** for NuGet, GitHub Actions and the pinned pip tooling, grouped, labelled `dependencies`
- **PR template** with comprehensive checklists; **issue templates** including the maintenance-task form

### 📚 Documentation System

- **DocFX integration** for API documentation
- **Automatic builds** and versioned deployment to GitHub Pages on every release
- **Local preview** support with `docfx build --serve`
- **Markdown + API reference** combined documentation
- **Live API Reference** at `https://<username>.github.io/<repo>/api/`

### 🎨 Code Style & Formatting

- **Comprehensive `.editorconfig`** with 200+ rules, analyzer severities layered per directory (`src/` strictest)
- **Formatting** via `dotnet format` / `pwsh ./scripts/format.ps1` (developer-side; the PR workflow does not run a format check)
- **Consistent style** across team members and IDEs

Key style rules:
- 4-space indentation for C#, 2 for XML/JSON/YAML
- Allman braces; `System` usings first
- PascalCase for types and members, camelCase for parameters/locals
- File-scoped namespaces, `var` where apparent, pattern-matching null checks (suggestions, not build errors)
- Unix-style line endings (LF) for every text file, including `*.ps1`

### 📋 Project Structure

```
root/
├── .github/
│   ├── workflows/          # CI/CD pipelines
│   ├── ISSUE_TEMPLATE/     # Issue templates (bug, feature, maintenance task)
│   ├── license-audit/      # Allowed-license list for license-audit.yaml
│   ├── requirements/       # Hash-pinned pip tooling (zizmor, semgrep)
│   ├── CODEOWNERS          # Code review assignments
│   └── dependabot.yml      # Dependency updates
├── .githooks/pre-commit    # gitleaks secret scan (git config core.hooksPath .githooks)
├── changelog/unreleased/   # A fragment per PR that changes src/ (or the no-changelog label); assembled at release
├── scripts/                # setup, build-pr, changelog, format, ruleset, Pages, restack, ...
├── src/                    # Library / application projects
├── tests/                  # Test projects (*.Tests.Unit, *.Tests.Integration)
├── benchmarks/             # Performance benchmarks (optional)
├── examples/               # Example projects (optional)
├── docfx_project/          # DocFX source (built docs go to the gh-pages branch)
├── docs/                   # Guides: baseline, workflow security, release setup, stacked PRs, ...
├── .editorconfig           # Code style rules and analyzer severities
├── .gitattributes          # LF for every text file
├── .gitignore              # Comprehensive .NET gitignore
├── .gitleaks.toml          # gitleaks allowlist (extends the default rules)
├── .globalconfig           # Global analyzer config
├── BannedSymbols.txt       # Banned API list
├── CHANGELOG.md            # Assembled from changelog/unreleased/
├── coverlet.runsettings    # Coverage collection settings
├── Directory.Build.props   # Shared MSBuild properties and analyzers
├── LICENSE                 # Project license
├── README.md               # Project README (from README-TEMPLATE.md)
├── SECURITY.md             # Reporting channel, response timelines
├── CONTRIBUTING.md         # Contribution guidelines
└── CODE_OF_CONDUCT.md      # Contributor Covenant
```

### 🏷️ License Options

Choose from three popular open-source licenses, or defer the decision, during setup:

| License | Best For | Key Characteristics |
|---------|----------|---------------------|
| **MIT** | Maximum freedom, libraries | Permissive, minimal restrictions |
| **Apache 2.0** | Patent protection, enterprise | Permissive + patent grant |
| **MPL 2.0** | File-level copyleft | Weak copyleft, file-based |
| **custom/TBD** | Publishing before the license is chosen | All rights reserved; `LicenseRef-TBD` file header, README wording says a license is pending |

See [choosealicense.com](https://choosealicense.com/licenses/) for a detailed comparison.
> **Note:** You will be prompted for a license when you run the setup script (`pwsh ./scripts/setup.ps1`)

---

## 📖 Template Setup Instructions

### Automated Setup (Recommended)

The template includes an automated setup script that handles all configuration:

#### PowerShell (Cross-platform - Windows/macOS/Linux)

> **Note:** PowerShell Core 7.0+ is required. If you don't have `pwsh` installed:
> - Windows: `winget install Microsoft.PowerShell`
> - macOS: `brew install powershell`
> - Linux: See [PowerShell installation guide](https://learn.microsoft.com/en-us/powershell/scripting/install/installing-powershell)

```powershell
pwsh ./scripts/setup.ps1
```

The script will:
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
| License Type | `MIT`, `Apache-2.0`, `MPL-2.0`, or `TBD` (all rights reserved pending selection) | No |
| Copyright Holder | `Chris Wolfgang` | Yes (from git) |
| NuGet Status | `Coming soon to NuGet.org` | No |

**Note:** The setup scripts handle the placeholders above. Additional optional content placeholders (`{{QUICK_START_EXAMPLE}}`, `{{FEATURES_TABLE}}`, `{{FEATURE_EXAMPLES}}`, `{{TARGET_FRAMEWORKS}}`, `{{ACKNOWLEDGMENTS}}`) remain in your README.md for you to fill in as you develop your project. See [TEMPLATE-PLACEHOLDERS.md](TEMPLATE-PLACEHOLDERS.md) for details.

### Manual Setup (Not Recommended)

If you prefer manual setup, see [TEMPLATE-PLACEHOLDERS.md](TEMPLATE-PLACEHOLDERS.md) for a complete list of placeholders and instructions.

---

## 🧪 Quality Standards

### Code Coverage
- **Gates:** 90 % line coverage for `src/` assemblies, 100 % for `tests/` assemblies (test code that never runs is dead code) - enforced per assembly in CI
- **Reports:** Generated with ReportGenerator
- **Formats:** HTML, Markdown, CSV

### Test Strategy
- Every project under `tests/` is a test project; `*.Tests.Integration.*` projects run on the Windows stage only
- Every `<TargetFrameworks>` entry is tested; a TFM on which zero tests ran fails the stage
- Coverage collection with `XPlat Code Coverage` (`coverlet.runsettings`)

### Build Configuration
- **Debug:** Warnings allowed (development)
- **Release:** Warnings treated as errors (CI); `LangVersion` is `latestMajor`
- **Multi-targeting:** Supports .NET Core 3.1, .NET 5.0-10.0 + .NET Framework 4.6.2-4.8.1

### Security Scanning
- **gitleaks, DevSkim:** PR checks (gitleaks logs findings; DevSkim uploads a text artifact)
- **CodeQL, Semgrep, InspectCode:** PR checks whose SARIF lands in the Security tab
- **zizmor, Scorecard, license audit, SBOM, nightly alert triage:** see *Security & Safety* above

---

## 📁 Repository Contents

### Core Files

| File | Purpose |
|------|---------|
| `README.md`[^1] | **THIS FILE** - Deleted during setup, replaced by renamed README-TEMPLATE.md |
| `README-TEMPLATE.md`[^1] | Project README template (renamed to `README.md` during setup) |
| `TEMPLATE-PLACEHOLDERS.md` | Complete placeholder documentation including template identification |
| `REPO-INSTRUCTIONS.md` | Manual setup instructions and the post-setup script reference |
| `scripts/setup.ps1` | PowerShell setup automation (offers to delete itself at the end; default is to keep it) |
| `docs/repository-baseline.md` | The 24-item hardening baseline every repo is audited against (`scripts/audit-repos.ps1`) |

[^1]: Modified during setup process

> **Note:** During setup (`pwsh ./scripts/setup.ps1`), the template README.md (this file) is deleted and README-TEMPLATE.md is renamed to README.md. The new README.md file will be a customized starter README for your repository, with placeholders replaced by the values you define.

### License Templates

| File | License Type |
|------|--------------|
| `LICENSE-MIT.txt` | MIT License template |
| `LICENSE-APACHE-2.0.txt` | Apache License 2.0 template |
| `LICENSE-MPL-2.0.txt` | Mozilla Public License 2.0 template |
| `LICENSE-TBD.txt` | All rights reserved pending license selection (copied to `LICENSE` by option 4; `setup.ps1` separately sets the `LicenseRef-TBD` file header in `.editorconfig` and the README wording) |

### Configuration Files

| File | Purpose |
|------|---------|
| `.editorconfig` | Code style rules (200+ settings) and per-directory analyzer severities |
| `.globalconfig` | Global analyzer configuration |
| `BannedSymbols.txt` | Banned API list |
| `Directory.Build.props` | Shared MSBuild properties, analyzer packages, `GenerateDocumentationFile` for `src/` |
| `coverlet.runsettings` | Coverage collection settings |
| `.gitleaks.toml` | gitleaks allowlist (extends the default rule set) |
| `.gitignore` | Comprehensive .NET gitignore |
| `.gitattributes` | LF line endings for every text file |

### GitHub Integration

| Location | Purpose |
|----------|---------|
| `.github/workflows/` | CI/CD pipeline definitions |
| `.github/ISSUE_TEMPLATE/` | Bug and feature request templates |
| `.github/CODEOWNERS` | Code review assignments |
| `.github/dependabot.yml` | Dependency update configuration (NuGet, Actions, pip tooling) |
| `.github/pull_request_template.md` | PR template with checklists |
| `.github/license-audit/` | Allowed licenses, URL mappings and ignored packages for the license audit |
| `.github/requirements/` | Hash-pinned `zizmor` / `semgrep` requirements |

---

## 🎯 After Setup

Once you've run the setup script and committed the changes:

### 1. Configure Branch Protection

**Important:** You must authenticate with GitHub CLI before running the branch protection script.

#### Step 1: Authenticate with GitHub CLI

```bash
gh auth login
```

Follow the prompts to authenticate. You only need to do this once per machine.

#### Step 2: Run the branch protection setup script

```powershell
pwsh ./scripts/Setup-BranchRuleset.ps1
```

The script will prompt you to choose between single-developer or multi-developer settings and automatically configure all required protections.

**Alternatively, for manual configuration**, go to **Settings → Rules → Rulesets** and configure the rule that applies to your default branch with:
- ✅ Require status checks before merging
- ✅ Require branches to be up to date
- ✅ Require pull request reviews (recommended for multi-developer repos)
- ✅ Require code owner review (recommended for multi-developer repos)
- ✅ Require Copilot review
- ✅ Restrict deletions
- ✅ Block force pushes
- ✅ Require code scanning

### 2. Set Up Release Workflow (Optional)

If publishing to NuGet, register a **trusted publishing policy** on NuGet.org (Account → Trusted Publishing: repository owner, repository, workflow file `release.yaml`). The workflow authenticates with a short-lived OIDC-issued key — there is no API-key secret to store.

See [RELEASE-WORKFLOW-SETUP.md](docs/RELEASE-WORKFLOW-SETUP.md) for details.

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
dotnet sln add tests/MyLib.Tests.Integration/MyLib.Tests.Integration.csproj
dotnet sln add tests/MyLib.Tests.Unit/MyLib.Tests.Unit.csproj
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

### 5. Keep Up With the Template

`setup.ps1` records the template commit it used in `.template-version`. When the
template moves on (a workflow fix, a new analyzer rule, a bumped tool pin), run:

```powershell
pwsh ./scripts/upgrade.ps1          # dry run: safe / review / in-sync / removed per file
pwsh ./scripts/upgrade.ps1 -Apply   # take the safe files, sidecar the rest, re-stamp
```

Files you never touched come across as-is; files you customised get a
`<file>.template` sidecar to merge by hand. See the script table in
[REPO-INSTRUCTIONS.md](REPO-INSTRUCTIONS.md#maintenance--repair-scripts).

---

## 📚 Additional Resources

- **Formatting Guide:** [README-FORMATTING.md](docs/README-FORMATTING.md)
- **Contributing Guide:** [CONTRIBUTING.md](CONTRIBUTING.md)
- **Code of Conduct:** [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md)
- **Release Workflow:** [RELEASE-WORKFLOW-SETUP.md](docs/RELEASE-WORKFLOW-SETUP.md)
- **Repository Baseline:** [repository-baseline.md](docs/repository-baseline.md)
- **Stacked PRs with linear history:** [STACKED-PRS.md](docs/STACKED-PRS.md)
- **Setup Instructions:** [REPO-INSTRUCTIONS.md](REPO-INSTRUCTIONS.md)
<!-- -**API Reference:** `https://<username>.github.io/<repo>/api/` (live documentation)-->

---

## 🔒 Automated Security & Branch Protection

This template includes automated security scanning and a local setup script for configuring branch protection.

### What's Included

#### 🛡️ Security Scanning
- **CodeQL Analysis** - Scans C# code for security vulnerabilities weekly and on every PR
- **DevSkim Security Scan** - Detects security anti-patterns in code

#### 🔐 Branch Protection (Main Branch)
Configured by running the local PowerShell setup script (see "How It Works" below):

- ✅ **Require pull requests** before merging
- ✅ **Require these status checks to pass:**
  - Detect .NET Projects
  - Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate
  - Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)
  - Stage 3: macOS Tests (.NET 6.0-10.0)
  - Security Scan (DevSkim)
  - Security Scan (CodeQL) (csharp)
  - Secrets Scan (gitleaks)
  - Changelog Fragment Check
- ✅ **Require branches to be up to date** before merging
- ✅ **Require conversation resolution** before merging
- ✅ **Dismiss stale reviews** when new commits are pushed
- ✅ **Require code scanning** - CodeQL alerts at *errors* / security *high or higher* block the merge
- ✅ **Require Copilot code review** and the **code quality** rule
- ✅ **Block force pushes** to main
- ✅ **Prevent branch deletion**
- ⬜ **Require linear history** - optional (`-RequireLinearHistory`), see [docs/STACKED-PRS.md](docs/STACKED-PRS.md)
- Nobody is in the bypass list. A PR that changes only protected files (workflows, `Directory.Build.props`, `.editorconfig`, …) passes the guard with a warning and merges on review; a PR that mixes them with other changes fails the guard and is split

**Repository Type Options:**
- **Single Developer:** No PR approvals required (you can merge your own PRs)
- **Multi-Developer:** Requires 1+ approval and code owner review

#### 🔍 Code Quality Gates
- **CodeQL:** Blocks merges on High or Critical security findings
- **Code Quality:** Blocks merges on errors
- **Advisory (not required checks):** ReSharper InspectCode and zizmor (SARIF to the Security tab), actionlint (check log), license audit (table in the job log, fails on a disallowed license), SBOM (artifact)

### How It Works

After creating a repository from this template:

1. **Install GitHub CLI (gh)** - Download from [https://cli.github.com/](https://cli.github.com/)
2. **Authenticate with GitHub** - Run `gh auth login` and follow the prompts
   - **Important:** You MUST complete this step before running the branch protection script
   - Authentication only needs to be done once per machine
3. **Run the branch protection script** from your repository root:
   ```powershell
   pwsh ./scripts/Setup-BranchRuleset.ps1
   ```
4. The script will:
   - ✅ Prompt you to choose single-developer or multi-developer settings
   - ✅ Automatically detect the current repository
   - ✅ Check if branch protection already exists
   - ✅ Create comprehensive branch protection for the main branch
   - ✅ Configure required status checks, PR requirements, and security scanning

You only need to run this script once per repository.

### For Template Users

The branch protection will apply to **your** repository after you run the local setup script. The configuration works for every repo created from this template; nobody, including the admin, can bypass the rules - configuration-only PRs merge on review instead.

### Customization

The script provides interactive prompts to choose between single-developer or multi-developer settings during execution. You can update the ruleset manually in Settings → Rules → Rulesets after setup if you need additional customization beyond the standard single/multi-developer options.

---

## ⚡ Key Features Summary

✅ **7 Code Analyzers + InspectCode** - Comprehensive quality enforcement
✅ **Multi-Platform CI/CD** - Linux, Windows, macOS
✅ **Multi-Framework** - .NET Core 3.1, .NET 5.0-10.0 + Framework 4.6.2-4.8.1
✅ **Coverage Gates** - 90 % src / 100 % tests, automated
✅ **Security Scanning** - gitleaks, DevSkim, CodeQL, Semgrep, zizmor, Scorecard, license audit, SBOM
✅ **Supply Chain** - SHA-pinned actions, trusted publishing, SLSA provenance attestations
✅ **Automated Documentation** - DocFX + versioned GitHub Pages
✅ **4 License Options** - MIT, Apache 2.0, MPL 2.0, or custom/TBD (pending selection)
✅ **Setup Automation** - PowerShell scripts (cross-platform, no bash)
✅ **Repository Baseline** - 22 audited hardening items

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

Projects created from this template can use any license - the setup script offers MIT, Apache 2.0, MPL 2.0, or a custom/TBD placeholder (all rights reserved pending selection) for repositories published before a license is chosen.

---

## 🙏 Credits

Created by [Chris Wolfgang](https://github.com/Chris-Wolfgang) and Copilot

Built with:
- .NET SDK (10.0 and the older SDKs the matrix needs)
- DocFX for documentation
- Multiple Roslyn analyzers and ReSharper InspectCode
- GitHub Actions for CI/CD
- ReportGenerator for coverage
- gitleaks, DevSkim, CodeQL, Semgrep, zizmor, actionlint and OpenSSF Scorecard for security

---

**Ready to create production-grade .NET projects?** Click "Use this template" above! 🚀
