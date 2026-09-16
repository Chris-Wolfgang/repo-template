# Copilot Coding Agent Instructions

## Repository Summary

This is a **repository template** for creating new .NET repositories. It provides a standardized structure with comprehensive GitHub integration, CI/CD workflows, and development tooling. The template supports multi-TFM .NET projects using C# and follows Microsoft's recommended project organization patterns.

**Repository Type**: Template (not a working project — it contains no csproj)
**Target Platforms**: .NET Framework 4.6.2–4.8.1, .NET Core 3.1, .NET 5.0–10.0
**Primary Language**: C#; the `scripts/` tooling is PowerShell 7 (`pwsh`). The one shell script is the git hook `.githooks/pre-commit` (bash, as git hooks must be), and CI `run:` steps use bash on the Linux/macOS stages.

## Build and Validation Instructions

### Prerequisites
- .NET SDK — the current release (10.0); CI installs 3.1 through 10.0 for the multi-target matrix
- PowerShell 7 (`pwsh`) — every script under `scripts/`
- A bash on PATH for the pre-commit hook (`.githooks/pre-commit`; Git for Windows ships one) plus the optional gitleaks CLI (`git config core.hooksPath .githooks`)

### Build Process (For Repositories Created from This Template)
**IMPORTANT**: This template has no buildable projects. These commands apply to repositories created FROM this template.

1. **Restore and build** (Release is what CI builds; analyzer warnings are errors there):
   ```powershell
   dotnet restore
   dotnet build --no-restore --configuration Release
   ```

2. **Run the PR workflow's Windows stage locally** — build, every target framework of every test project, coverage gates, DevSkim, gitleaks:
   ```powershell
   pwsh ./scripts/build-pr.ps1
   ```
   `-SkipSecurity` / `-SkipCoverage` / `-SkipTests` narrow it while iterating. The Linux and macOS stages only run in CI.

3. **Format**: `pwsh ./scripts/format.ps1` (`-Check` to verify only). The PR workflow does not run a format check; formatting is developer-side.

### Critical Build Requirements
- **Test projects**: every project under `tests/` is a test project (no name pattern). Every entry in its `<TargetFrameworks>` is tested, and a framework on which zero tests ran fails the stage.
- **Code coverage**: **90 %** line coverage for assemblies under `src/`, **100 %** for assemblies under `tests/` (test code that never runs is dead code). Gated per assembly.
- **Changelog fragment**: a PR that changes anything under `src/` must add `changelog/unreleased/<name>.md` (`type: breaking|feature|fix|docs|internal` + one user-facing sentence) or carry the `no-changelog` label. `CHANGELOG.md` is never edited by hand. See `changelog/unreleased/README.md`.
- **Protected configuration files**: `.editorconfig`, `Directory.Build.props`, `Directory.Build.targets`, `BannedSymbols.txt`, `*.globalconfig`, `*.ruleset`, `*.DotSettings` and anything under `.github/workflows/` are re-fetched from `main` during CI, and a PR that changes them **fails the `Detect .NET Projects` check by design** so a maintainer reviews the diff and merges with the admin bypass. Keep such changes in their own PR. See `docs/WORKFLOW_SECURITY.md`.
- **Security scanning**: gitleaks, DevSkim, CodeQL (security-extended), Semgrep, ReSharper InspectCode (error-severity findings fail), actionlint + zizmor on the workflow files (High-severity zizmor findings fail).
- **Documentation**: `GenerateDocumentationFile` is on for every project under `src/`; a public member without an XML doc comment is CS1591 → Release error.

### Common Issues and Workarounds
- **Coverage threshold failures**: the build fails below the gate by design; the gate reads ReportGenerator's `Summary.txt` per assembly.
- **`Detect .NET Projects` red with "PROTECTED CONFIGURATION FILES CHANGED"**: expected for any workflow/config change — it is the review signal, not a bug to fix.
- **`Changelog Fragment Check` red**: add the fragment or the `no-changelog` label, then re-run the job.
- **Missing test projects**: CI refuses to skip the coverage gate silently when `src/` has projects but `tests/` has none.

## Project Layout and Architecture

### Standard Directory Structure
```
root/
├── MySolution.slnx             # Solution file (setup.ps1 can create it)
├── src/                        # Library / application projects
├── tests/                      # Test projects (*.Tests.Unit, *.Tests.Integration)
├── benchmarks/                 # Performance benchmarks (optional)
├── examples/                   # Example projects (optional)
├── changelog/unreleased/       # One changelog fragment per src/-touching PR
├── docfx_project/              # DocFX source; the built site lives on the gh-pages branch
├── docs/                       # Repository guides (workflow security, release setup, stacked PRs, baseline)
├── scripts/                    # PowerShell tooling (setup, build-pr, changelog, format, rulesets, Pages, restack, audit)
├── .githooks/pre-commit        # gitleaks secret scan
└── .github/                    # Workflows, issue/PR templates, CODEOWNERS, dependabot, license-audit, pip requirements
```

### Key Configuration Files
- **`.editorconfig`**: Code style rules and analyzer severities, layered per directory (`src/` strictest; `tests/`, `benchmarks/`, `examples/` relaxed). File-scoped namespaces, `var` where the type is apparent, Allman braces.
- **`Directory.Build.props`**: Shared MSBuild properties, the seven always-on analyzer packages plus the opt-in PublicApiAnalyzers, `TreatWarningsAsErrors` for Release, `GenerateDocumentationFile` for `src/`, SourceLink.
- **`BannedSymbols.txt`**: Async-first enforcement (blocking waits, sync I/O, `Parallel.*`, obsolete APIs).
- **`coverlet.runsettings`**: coverage collection, test assemblies instrumented too.
- **`.gitleaks.toml`**: gitleaks allowlist (extends the default rules).
- **`REPO-INSTRUCTIONS.md`** / **`TEMPLATE-PLACEHOLDERS.md`**: template setup instructions and placeholder reference.
- **`CONTRIBUTING.md`**, **`SECURITY.md`**, **`CODE_OF_CONDUCT.md`**: contribution guidelines, reporting channel + response timelines, Contributor Covenant.

### GitHub Integration
- **Workflows** (`.github/workflows/`): `pr.yaml` (the gated PR pipeline), `release.yaml` (release → NuGet trusted publishing + attestation + docs), `docfx.yaml` (versioned docs deploy, called by release), `codeql.yaml`, `actions-audit.yaml` (actionlint + zizmor), `scorecard.yaml`, `semgrep.yaml`, `license-audit.yaml`, `sbom.yaml`, `sourcelink.yaml`, `security-alerts.yml` (nightly alert → issue triage), `stryker.yaml`, `benchmarks.yaml`, `build-all-versions.yaml`.
- **Issue templates** (all YAML forms): bug report, feature request, maintenance task.
- **PR template**: structured checklist.
- **CODEOWNERS**: default owner `@Chris-Wolfgang`, update as needed.
- **Dependabot**: NuGet, GitHub Actions and the hash-pinned pip tooling under `.github/requirements/`, weekly, grouped, labelled `dependencies`.

### Continuous Integration Pipeline (`.github/workflows/pr.yaml`)
Runs on `pull_request_target` (the workflow file and protected config come from `main`; the PR head is checked out for the code):

1. **Secrets Scan (gitleaks)** and **Detect .NET Projects** (project discovery + the protected-file guard) run first.
2. **Changelog Fragment Check** and **ReSharper InspectCode** run in parallel with the test stages.
3. **Stage 1 Linux** (.NET 5.0–10.0 + coverage gate) → **Stage 2 Windows** (.NET Core 3.1, .NET 5.0–10.0, .NET Framework 4.6.2–4.8.1; integration tests; the full-TFM backstop) → **Stage 3 macOS** (.NET 6.0–10.0). Each stage discovers the projects' target frameworks at run time.
4. **Security Scan (DevSkim)**; CodeQL, actionlint/zizmor, license audit and SBOM run from their own workflows.
5. **Required checks** (ruleset): Detect .NET Projects, the three stages, DevSkim, CodeQL, gitleaks, Changelog Fragment Check. InspectCode, actionlint/zizmor, license audit and SBOM are advisory.

### Branch Protection Configuration
Branch protection rules are configured by running the local PowerShell script `scripts/Setup-BranchRuleset.ps1`. The script prompts you to choose repository settings during setup.

**Single-Developer Configuration (Default):**
- No PR approvals required (you can merge your own PRs)
- Allows solo developers to merge their own PRs while still enforcing CI/CD checks

**Multi-Developer Configuration:**
- Requires 1+ approval before merging
- Requires code owner review

**All Configurations Include:**
- Require the status checks listed above to pass before merging
- Require branches to be up to date
- Require conversation resolution before merging
- Restrict deletions and block force pushes
- Require code scanning (CodeQL, errors / High+ security), Copilot code review, code quality
- Optional `-RequireLinearHistory` (squash/rebase only; stacked PRs use `scripts/restack.ps1`, see `docs/STACKED-PRS.md`)

**Branch Protection Setup Instructions:**
1. Install GitHub CLI (gh) from https://cli.github.com/
2. Authenticate: `gh auth login`
3. From PowerShell 7+ (for example, using `pwsh`), run the branch protection setup script:
   ```powershell
   pwsh -File ./scripts/Setup-BranchRuleset.ps1
   ```
4. When prompted by the script, choose single-developer or multi-developer settings

## Key Files and Locations

### Root Directory Files
- `README.md` - Template description (replaced by `README-TEMPLATE.md` during setup)
- `LICENSE` - Chosen at setup (MIT, Apache-2.0, MPL-2.0, or custom/TBD)
- `REPO-INSTRUCTIONS.md` - Template setup instructions (delete after setup)
- `.editorconfig`, `Directory.Build.props`, `BannedSymbols.txt`, `coverlet.runsettings` - see above
- `.gitignore` - .NET-specific gitignore; `.gitattributes` - LF for every text file

### GitHub Directory (`.github/`)
- `workflows/` - the 14 workflows listed above
- `ISSUE_TEMPLATE/` - bug report, feature request, maintenance task (YAML forms)
- `pull_request_template.md` - PR template with checklists
- `CODEOWNERS` - Code ownership rules
- `dependabot.yml` - Dependency update configuration
- `license-audit/` - allowed licenses, URL mappings, ignored packages
- `requirements/` - hash-pinned zizmor / semgrep

### Project Directories (Currently Empty in Template)
- `src/` - Library / application source code
- `tests/` - Unit and integration tests
- `benchmarks/` - Performance benchmarks
- `examples/` - Example usage projects

## Maintenance Framework

Every repo derived from this template uses a per-repo **Maintenance** tracking framework to organize ongoing improvement work (security, performance, testing, cleanup, docs, API, CI/CD). The framework has three pieces:

1. **One parent `Maintenance: <repo>` issue per repo** (labeled `maintenance`). Living "improvement menu" — stays open forever. Lists candidate work by category. Never close.
2. **Sub-issues labeled `maintenance-task` + a `maintenance - <category>` label.** These are the actual tracked work. Spawn lazily — create one when there's actionable work, close when done.
3. **A cross-repo GitHub Projects v2 board** that auto-aggregates every `maintenance-task` issue across all repos for filtered views (by repo, by category, by status).

### Categories (one per sub-issue)

| Label | Covers |
|---|---|
| `maintenance - security` | SAST/analyzer scans, finding fixes, dependency vulnerability audit |
| `maintenance - performance` | Profile, benchmark, optimize, validate gains |
| `maintenance - testing` | Coverage %, integration/smoke/mutation tests, fixtures, CI test-step additions |
| `maintenance - cleanup` | Refactor for reuse, quality, efficiency |
| `maintenance - docs` | XML doc coverage, README, CHANGELOG, samples |
| `maintenance - API` | Public/internal surface audit, breaking-change vigilance |
| `maintenance - CI/CD` | Docker, CI workflow, build/publish pipeline, packaging |

### For Copilot agents working in this repo

When you **discover work** that fits one of the categories — a security scanner finding, a slow hot path, missing test coverage, code smelling for refactor, outdated docs, an inadvertent breaking API change, a flaky CI step — **don't just comment or fix it silently.** Instead:

1. Open a `maintenance-task` sub-issue using the **"Maintenance task" issue template** (`.github/ISSUE_TEMPLATE/maintenance-task.yaml`).
2. Pick the matching category in the dropdown.
3. Fill in the Scope and Acceptance fields with concrete observable outcomes.
4. After creation, add the corresponding `maintenance - <category>` label (the form pre-fills only `maintenance-task`; the category must be added manually).
5. If you're submitting a PR that addresses the issue, include `Fixes #<sub-issue-number>` in the PR body so the project board auto-marks the item as Done.

This produces a paper trail that ties findings → tracked work → PRs, and rolls up into the cross-repo Maintenance view so unfinished improvements aren't forgotten when the agent session ends.

**Reserve plain (non-`maintenance - ` prefixed) issues for repo-specific decisions** that aren't part of the fleet-wide pattern — e.g., "Drop net6.0 from TFM matrix," "Add new feature X," one-off bug fixes.

### Provisioning Maintenance on a new repo

When a new repo is created from this template:
1. Run `scripts/Setup-Labels.ps1` to provision the labels (issue-form labels, `dependencies`, `no-changelog`, and the nine Maintenance labels).
2. Run `scripts/Setup-Maintenance.ps1 -MaintenanceProjectUrl '<url>'` to create the parent Maintenance issue. (Pass the cross-repo project URL — ask the user if you don't have it.)
3. The auto-add workflow in the Maintenance project will pick up new `maintenance-task` sub-issues automatically.

## Agent Guidelines

### Trust These Instructions
This information has been validated against the template structure and GitHub workflows (last checked 2026-09-16). **Only search for additional information if these instructions are incomplete or found to be incorrect.**

### When Working with This Template
1. **Creating New Projects**: Follow the structure outlined in `REPO-INSTRUCTIONS.md`
2. **Adding Dependencies**: Use `dotnet add package` commands
3. **Code Style**: Follow `.editorconfig` rules (file-scoped namespaces, `var` where the type is apparent, Allman braces)
4. **Testing**: put test projects under `tests/`; keep the `.Tests.Unit` / `.Tests.Integration` suffixes
5. **Coverage**: 90 % on `src/`, 100 % on `tests/`, per assembly
6. **Changelog**: add a `changelog/unreleased/` fragment to any PR that touches `src/`
7. **Protected files**: never bundle a workflow/config change with unrelated code; it will hold the whole PR for review
8. **Security**: Review DevSkim / CodeQL / InspectCode findings and address security concerns
9. **Maintenance framework**: When you find improvement work that fits a category, open a `maintenance-task` sub-issue rather than fixing silently (see "Maintenance Framework" section above)

### Validation Steps
Before submitting changes:
1. `pwsh ./scripts/build-pr.ps1` (or `dotnet restore && dotnet build --configuration Release` + `dotnet test --configuration Release` at minimum)
2. Verify coverage meets the gates
3. Add the changelog fragment if `src/` changed
4. Ensure all GitHub Actions checks pass — a red `Detect .NET Projects` on a protected-file change is expected and needs a maintainer

This template provides a solid foundation for .NET projects with enterprise-grade CI/CD, security scanning, and development best practices built-in.
