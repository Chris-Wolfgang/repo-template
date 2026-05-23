# Setting Up Your Repository

## Setup Instructions

After you create your repo from the template you will still need to configure some settings. 
Below is a list of what needs to be done. Once you have completed the checklist below you can delete this file

## Creating Your Repository

1. On the `Repositories` page click `New`
1. On the `Create a new repository` page enter
	1. `Repository name`
 	2. `Description`
  	3. Select `Public` or `Private`
1. `Start with a template` select `Chris-Wolfgang/repo-template`
1. `Include all branches` set `On` - this will include the `develop` branch. If you don't want the `develop` branch or if there are other branches you don't want you can leave this `off` and create the `develop` branch in your new repository


## Add Branch Protection Rules

Configure branch protection rules for the `main` branch:

1. Go to your repository’s Settings → Branches.
2. Under “Branch protection rules,” click `Add branch ruleset`
3. `Ruleset Name` enter `main`
4. `Target branches` click `Add target`
5. Select `Include by pattern`
6. `Branch naming pattern` enter `main`
7. Click `Add Inclusion pattern`


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

**Note:** The release workflow automatically publishes packages to NuGet.org when you push a version tag (e.g., `v1.0.0`).


## Update Template Files

After creating your repository from the template, update the following files with your project-specific information:

### Update README.md

1. Open `README.md` in the root folder
2. Replace the template content with your project's description
3. Add installation instructions, usage examples, and other relevant information

### Update CONTRIBUTING.md

1. Open `CONTRIBUTING.md`
2. Ensure any project name placeholders (for example, `Wolfgang.Extensions.DateTime`) have been replaced with your actual project name
3. Review and adjust contribution guidelines as needed for your project

### Update CODEOWNERS

1. Open `.github/CODEOWNERS`
2. Replace `@Chris-Wolfgang` with your GitHub username or team names
3. Uncomment and customize the example rules if you want different owners for specific directories

**Note:** The CODEOWNERS file determines who is automatically requested for review when someone opens a pull request.

### Setup GitHub Pages for Documentation (Optional)

If you want to publish your DocFX documentation to GitHub Pages automatically when you publish a GitHub Release:

1. Set up GitHub Pages manually:
   - Go to your repository's **Settings → Pages**
   - Under "Build and deployment," select **Deploy from a branch**
   - Select the `gh-pages` branch (create it if it doesn't exist: `git checkout --orphan gh-pages && git push origin gh-pages`)
   - Save the settings
   - Update the DocFX configuration files in `docfx_project/` to replace placeholders (e.g., `Wolfgang.D20-Dice`, `https://Chris-Wolfgang.github.io/D20-Dice/`) with your project's values

2. Documentation will be automatically published when you publish a GitHub Release:
   1. Go to your repository's **Releases** page
   2. Click **"Draft a new release"**
   3. Choose or create a version tag (e.g., `v1.0.0`)
   4. Click **"Publish release"**

3. The documentation will be available at: `https://[username].github.io/[repo-name]/`

**Note:** The DocFX workflow (`.github/workflows/docfx.yaml`) is configured to trigger via:
- **`workflow_call`**: Called automatically by `release.yaml` after a GitHub Release is published (passes the release tag as the version)
- **`workflow_dispatch`**: Manual trigger for ad-hoc builds or dry-runs (available from the Actions tab)


### Update Documentation (Optional)

If you're using DocFX for documentation:
1. Review and customize the table of contents in `docfx_project/docs/toc.yml` and update repository-specific values (e.g., links and project names)
2. Customize the rest of the documentation content in `docfx_project/`

### Multi-Version DocFX Documentation

This repository is configured for versioned documentation using DocFX. The setup consists of:

#### Key Files
| File | Purpose |
|------|---------|
| `docfx.json` | Optional root-level DocFX configuration for local/single-version documentation builds or previews. **Not used by CI workflows** for version discovery or multi-version wiring (handled via git tags). |
| `docfx_project/docfx.json` | Per-build DocFX configuration used by CI workflows to build docs. Uses `default` + `modern` templates with dark mode enabled (`colorMode: dark`). |
| `logo.svg` | Repository logo at the root; also present in `docfx_project/`. |

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
