# Setting Up Your Repository

## Setup Instructions

After you create your repo from the template you will still need to configure some settings.
Below is a list of what needs to be done. Once you have completed the checklist below you can delete this file.

> **⚡ Fast path — automated setup.** The README's [Quick Start](README.md#quick-start) walks
> through `pwsh ./scripts/setup.ps1`, which handles placeholder replacement, label
> creation, branch-ruleset configuration, and GitHub Pages setup automatically. If
> you ran that, you can skip most of the manual steps below — they're documented
> here as a fallback for cases where the automated script doesn't fit (forks,
> non-template repos adopting this layout, etc.).

## Creating Your Repository

1. On the `Repositories` page click `New`
1. On the `Create a new repository` page enter
	1. `Repository name`
 	2. `Description`
  	3. Select `Public` or `Private`
1. `Start with a template` select `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}`
1. `Include all branches` set `On` - this will include the `develop` branch. If you don't want the `develop` branch or if there are other branches you don't want you can leave this `off` and create the `develop` branch in your new repository


## Add Branch Protection Rules

The fastest path is the bundled script. It provisions the full canonical
ruleset (required status checks, code-scanning gate, force-push protection,
conversation-resolution requirement, Copilot code review) in one command:

```powershell
pwsh -File ./scripts/Setup-BranchRuleset.ps1
```

The script auto-detects the current repository, prompts you to pick
**single-developer** (no approvals required - you can merge your own PRs)
vs. **multi-developer** (one approval + code-owner review), and self-deletes
when it succeeds. Restore it from the template if the ruleset ever needs to
be re-created.

If the live ruleset drifts (e.g. a required check name changes upstream and
PRs get stuck waiting for a check that will never report), run:

```powershell
pwsh -File ./scripts/Fix-BranchRuleset.ps1
```

This inspects the live ruleset and prompts to repair any divergence from the
canonical shape.

### Manual fallback (UI only)

Only use this path if `Setup-BranchRuleset.ps1` does not fit your scenario
(e.g. you are adopting this layout in a non-template repo that does not have
the script).

1. Go to your repository''s **Settings > Rules > Rulesets**.
2. Click **New ruleset > New branch ruleset**.
3. **Ruleset Name** enter `Protect main branch`.
4. **Enforcement status** set to **Active**.
5. **Target branches > Add target > Include by pattern** enter `main`.
6. Under **Branch rules**, enable:
   - Restrict creations / deletions / non-fast-forward updates
   - Require a pull request before merging, with conversation-resolution required
   - Require status checks to pass - add the contexts listed in
     [scripts/Setup-BranchRuleset.ps1](scripts/Setup-BranchRuleset.ps1)
     (Stage 1/2/3 Linux/Windows/macOS, Detect .NET Projects, Secrets Scan
     (gitleaks), Security Scan (DevSkim), Security Scan (CodeQL) (csharp))
   - Require code scanning results from CodeQL, errors threshold
7. Save the ruleset.

## Security Settings

Prevent Merging When Checks Fail
These settings require that all checks in the pr.yaml file succeed before you can merge a branch into main

**Note:** The pr.yaml workflow uses `pull_request_target` to always run from the trusted main branch, even for PRs from feature branches. This prevents malicious workflow modifications in untrusted PR branches while still testing the PR's code.

1. Go to your repository’s Settings → Branches.
2. Under “Branch protection rules,” edit the rule for main.
3. Check “Require status checks to pass before merging.”
4. In the "Status checks that are required" list, select the status check contexts produced by your PR workflow jobs. These options appear after the workflow has run at least once on `main`. For example:
   - "Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate"
   - "Stage 2a: Windows Tests (.NET 5.0-10.0)"
   - "Stage 2b: Windows .NET Framework Tests (4.6.2-4.8.1)"
   - "Stage 3: macOS Tests (.NET 6.0-10.0)"
   - "Security Scan (DevSkim)"

5. Enable “Require branches to be up to date before merging.”
6. Check `Restrict deletions`
7. Check `Require a pull request before merging`
	1. Check `Dismiss stale pull request approvals when new commits are pushed`
	3. **For multi-developer repos:** Check `Require review from Code Owners` and set required approvals to 1 or more
8. Check `Block force pushes`
9. Check `Require code scanning`


## Add Custom Labels

Run the label setup script once after creating your repository:

```powershell
pwsh -File ./scripts/Setup-Labels.ps1
```

This creates the labels used by Dependabot and the Maintenance framework.
The canonical list lives in `scripts/Setup-Labels.ps1`; today it is:

- `dependencies` — applied automatically by Dependabot to every update PR.
- `maintenance` — kind label for the per-repo parent Maintenance issue.
- `maintenance-task` — kind label for every Maintenance sub-issue.
- `maintenance - security` — scans, finding fixes, dependency vulnerability audit.
- `maintenance - performance` — profile, benchmark, optimize, validate.
- `maintenance - testing` — coverage, integration / smoke / mutation tests.
- `maintenance - cleanup` — refactor for reuse / quality / efficiency.
- `maintenance - docs` — XML doc coverage, README, CHANGELOG, samples.
- `maintenance - API` — public/internal surface audit, breaking-change vigilance.
- `maintenance - CI/CD` — Docker, CI workflow, build / publish pipeline.

Requires the [GitHub CLI](https://cli.github.com/) to be installed and authenticated (`gh auth login`).

## Set Up the Maintenance Framework

After the labels exist, provision the per-repo parent **Maintenance** issue
and its standard sub-issues (security, performance, testing, cleanup, docs,
API, CI/CD). The `Maintenance: <repo>` parent issue is referenced by
`.github/copilot-instructions.md` and the downstream maintenance workflows;
if you skip this step those references point at a non-existent issue.

```powershell
pwsh -File ./scripts/Setup-Maintenance.ps1
```

This is a one-time step per repo. The script is idempotent - re-running it
updates the existing parent issue rather than creating duplicates.

Requires `gh auth login` (same prerequisite as the labels script).


## Creating the project

### Creating a Solution

To create a solution:

1. Create a blank solution and save it in the root folder
   ```bash
   dotnet new sln -n YourSolutionName
   ```
2. Add new projects to the solution. Each application project will be in its own folder in the /src folder
3. Add one or more test projects each in its own folder in the /tests folder
4. If the solution will have benchmark project add each project in its own folder under /benchmarks

```
root
├── MySolution.sln
├── src
│   ├── MyApp
│   │   └── MyApp.csproj
│   └── MyLib
│       └── MyLib.csproj
├── tests
│   ├── MyApp.Tests
│   │   └── MyApp.Tests.csproj
│   └── MyLib.Tests
│       └── MyLib.Tests.csproj
└── benchmarks
    └── MyApp.Benchmarks
        └── MyApp.Benchmarks.csproj
```


## Configure Release Workflow (Optional)

If you plan to publish NuGet packages using the automated release workflow, you need to configure the following:

### Add NuGet API Key Secret

1. Go to your repository's Settings → Secrets and variables → Actions
2. Click **"New repository secret"**
3. **Name:** `NUGET_API_KEY`
4. **Value:** Your NuGet.org API key
   - Get your key from [NuGet.org Account → API Keys](https://www.nuget.org/account/apikeys)
   - Recommended scopes: **Push new packages and package versions**
   - Set expiration date (recommended: 1 year)
5. Click **"Add secret"**

**Note:** The release workflow automatically publishes packages to NuGet.org when you **publish a GitHub Release** (the workflow triggers on `release: types: [published]`, not on a tag push). Create a tag like `v1.0.0`, then publish a GitHub Release from that tag to trigger the workflow.


## Update Template Files

After creating your repository from the template, update the following files with your project-specific information:

### Update README.md

1. Open `README.md` in the root folder
2. Replace the template content with your project's description
3. Add installation instructions, usage examples, and other relevant information

### Update CONTRIBUTING.md

1. Open `CONTRIBUTING.md`
2. Ensure any project name placeholders (for example, `{{PROJECT_NAME}}`) have been replaced with your actual project name
3. Review and adjust contribution guidelines as needed for your project

### Update CODEOWNERS

1. Open `.github/CODEOWNERS`
2. Replace `{{GITHUB_USERNAME}}` with your GitHub username or team names
3. Uncomment and customize the example rules if you want different owners for specific directories

**Note:** The CODEOWNERS file determines who is automatically requested for review when someone opens a pull request.

### Setup GitHub Pages for Documentation (Optional)

The fastest path is the bundled script. It creates the `gh-pages` branch if
needed, enables Pages on it, substitutes the docfx placeholders for the
current repo, and self-deletes when it succeeds:

```powershell
pwsh -File ./scripts/Setup-GitHubPages.ps1
```

After this runs, publishing a GitHub Release fires `release.yaml`, which
calls `docfx.yaml` to build the docs and publish them to `gh-pages`. Docs
are served at `https://[username].github.io/[repo-name]/`.

After a docs deploy, validate the result with:

```bash
bash ./scripts/Validate-DocsDeploy.sh
```

This inspects the live `gh-pages` content (`index.html`, `versions.json`,
every version folder, the `latest/` alias) and reports drift from the
expected layout. Useful for catching botched deploys before readers notice.

**The DocFX workflow trigger**:
- **`workflow_call`** - invoked by `release.yaml` after a GitHub Release is
  published (passes the release tag as the version)
- **`workflow_dispatch`** - manual trigger for ad-hoc builds or dry-runs

#### Manual fallback (UI only)

Only use this path if `Setup-GitHubPages.ps1` does not fit your scenario.

1. **Settings > Pages**: set source to **Deploy from a branch**, branch
   `gh-pages` (`git checkout --orphan gh-pages && git push origin gh-pages`
   if it does not exist).
2. Edit `docfx_project/docfx.json` and surrounding files to replace
   `{{PROJECT_NAME}}`, `{{DOCS_URL}}`, etc. with your project values.
3. Publish a GitHub Release to fire the workflow.

### Update Documentation (Optional)

If you're using DocFX for documentation:
1. Review and customize the table of contents in `docfx_project/docs/toc.yml` and update repository-specific values (e.g., links and project names)
2. Customize the rest of the documentation content in `docfx_project/`

### Multi-Version DocFX Documentation

This repository is configured for versioned documentation using DocFX. The setup consists of:

#### Key Files
| File | Purpose |
|------|---------|
| `docfx_project/docfx.json` | DocFX configuration used by CI workflows to build docs. Uses `default` + `modern` templates with dark mode enabled (`colorMode: dark`). |
| `docfx_project/logo.svg` | Repository logo, embedded in the built docs site. |

#### How Versioning Works
- CI workflows discover documentation versions **dynamically at runtime** by querying git tags that match the SemVer pattern `v*.*.*` (e.g. `v1.0.0`, `v0.3.0`). No manual version list is maintained in any config file.
- The `.github/workflows/build-all-versions.yaml` workflow enumerates all matching tags and builds documentation for each — no file updates are required when a new release is published.
- Each release triggers `.github/workflows/release.yaml` (on a published GitHub Release), which calls `.github/workflows/docfx.yaml` via `workflow_call` to build docs and deploy them to the `gh-pages` branch under `versions/<tag>/`. You can also run `docfx.yaml` directly via `workflow_dispatch` from the Actions tab for ad-hoc builds.
- After every versioned deploy, a `versions.json` is generated and written to `gh-pages`, powering the version-switcher dropdown.
- `versions/latest/` always mirrors the most recent stable release; the site root (`/`) hosts the version-picker landing page that links to the latest and all other available documentation versions.

#### Adding a New Version
When you publish a new release (e.g. `v1.0.0`):
1. Create and push a version tag (e.g. `v1.0.0`) to the repository.
2. Publish a GitHub Release for that tag — this triggers `release.yaml`, which calls `docfx.yaml` via `workflow_call` to automatically build and publish the docs. You can also run `docfx.yaml` directly via `workflow_dispatch` for ad-hoc or dry-run builds.
3. To backfill all historical versions at once, run the **Build All Versioned Docs** workflow manually from the Actions tab.

#### Dark Theme
The DocFX modern template is configured to default to dark mode. This is controlled by:
- `"colorMode": "dark"` in `docfx_project/docfx.json` → `build.globalMetadata`
- `"_enableDarkMode": true` enables the light/dark toggle so visitors can switch themes

## Maintenance & Repair Scripts

After the one-time setup scripts have self-deleted, these helpers stay around
because they are useful in steady-state:

| Script | When to use |
|---|---|
| `scripts/Fix-BranchRuleset.ps1` | Repair the branch ruleset if a check name changes upstream and the rule gets stuck waiting. Inspects and patches in place; does not recreate from scratch. |
| `scripts/Setup-Labels.ps1` | Re-run when new canonical labels are added (e.g. a new `maintenance - X` kind). Idempotent. |
| `scripts/Validate-DocsDeploy.sh` | Post-deploy validation of the `gh-pages` branch. See the **Setup GitHub Pages** section above. |
| `scripts/build-pr.ps1` | Local dry-run of the full PR CI matrix (Linux Stage 1 + Windows Stage 2 + macOS Stage 3). Useful before pushing a workflow change to confirm it still passes. |
| `scripts/format.ps1` | One-shot formatter (CSharpier + analyzer auto-fixups). Mirrors what the CI build expects, so running it locally avoids surprise CI failures. |


## Mutation Testing

`.github/workflows/stryker.yaml` runs Stryker.NET mutation testing against
every test project under `tests/` on a **Windows** runner. Windows is
required because the test matrix can include .NET Framework 4.6.2-4.8.1
TFMs, which only build on Windows; a Linux runner would silently mutate
only the .NET (Core) TFMs and miss any bugs that reproduce only on
Framework.

**The workflow always runs** - no opt-in is required.

Two configuration modes are supported:

- **Root-level umbrella** - if a `stryker-config.json` exists at the repo
  root, it is treated as the umbrella config: Stryker is invoked once with
  it and per-project runs are skipped (avoids duplicating the same work).
  Use this when one Stryker invocation should cover multiple test projects.
- **Per-project (default)** - if no root config exists, Stryker runs once
  per test project under `tests/`. A per-project `stryker-config.json` next
  to a test project overrides Stryker's defaults (excluded files, specific
  mutators, mutation level, etc.).

Triggers:

- `workflow_dispatch` - manual ad-hoc runs (e.g. while iterating on tests)
- `schedule` - weekly Sunday 06:00 UTC; catches quality regressions between
  releases without burning CI time on every PR (mutation testing is slow)

The Stryker HTML report is uploaded as a workflow artifact
(`stryker-report-<run-id>`) and retained for 30 days. Download it from the
workflow run page to see per-mutator survival rates and the surviving
mutant locations.
