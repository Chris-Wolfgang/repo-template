# Setting Up Your Repository

## Automated Setup (Recommended)

**NEW:** This template now includes automated setup scripts that handle all configuration for you!

### Quick Setup

```bash
# PowerShell (Windows/macOS/Linux)
pwsh ./scripts/setup.ps1

# Or Bash (macOS/Linux)
chmod +x scripts/setup.sh
./scripts/setup.sh
```

The automated scripts will:
1. ✅ Prompt for all required information (with examples and defaults)
2. ✅ Auto-detect git repository information where possible
3. ✅ Replace placeholders in core template files (see TEMPLATE-PLACEHOLDERS.md for details and any manual steps, including DocFX docs)
4. ✅ Delete the template README.md
5. ✅ Rename README-TEMPLATE.md to README.md
6. ✅ Set up your chosen LICENSE (MIT, Apache 2.0, or MPL 2.0)
7. ✅ Remove unused license templates
8. ✅ **Optionally create a default .slnx solution file** with proper folder structure (requires Visual Studio 2022 17.10+)
9. ✅ Validate all replacements
10. ✅ Optionally clean up template-specific files

**For detailed placeholder documentation, see [TEMPLATE-PLACEHOLDERS.md](TEMPLATE-PLACEHOLDERS.md)**  
**For license selection guidance, see [LICENSE-SELECTION.md](LICENSE-SELECTION.md)**

---

## Manual Setup Instructions

After you create your repo from the template you will still need to configure some settings. 
Below is a list of what needs to be done. Once you have completed the checklist below you can delete this file

## Creating Your Repository

1. On the `Repositories` page click `New`
1. On the `Create a new repository` page enter
	1. `Repository name`
 	2. `Description`
  	3. Select `Public` or `Private`
1. `Start with a template` select `{{TEMPLATE_REPO_OWNER}}/{{TEMPLATE_REPO_NAME}}`
1. `Include all branches` set `On` - this will include the `develop` branch. If you don't want the `develop` branch or if there are other branches you don't want you can leave this `off` and create the `develop` branch in your new repository


## Add Branch Protection Rules

> **Note:** Branch protection is now configured using a local PowerShell script. After setting up your repository, run the script to configure branch protection:
> ```powershell
> pwsh ./scripts/Setup-BranchRuleset.ps1
> ```
> The script includes interactive prompts that allow you to choose between **single developer** or **multi-developer** repository settings during execution. Simply run the script and select option [1] for single-developer mode (no approvals required) or option [2] for multi-developer mode (requires 1+ approval and code owner review).

If you need to manually configure branch protection instead:

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

> **Note for Single-Developer Repositories:** This template is configured for single-developer use. The branch protection script (`scripts/Setup-BranchRuleset.ps1`) includes interactive prompts that allow you to choose between single-developer or multi-developer settings during execution. Simply run the script and select option [1] for single-developer mode (no PR approvals required) or option [2] for multi-developer mode (requires 1+ approval and code owner review).
**Note:** The pr.yaml workflow uses `pull_request_target` to always run from the trusted main branch, even for PRs from feature branches. This prevents malicious workflow modifications in untrusted PR branches while still testing the PR's code.

> **Branch protection is now configured via local script!** Run `pwsh ./scripts/Setup-BranchRuleset.ps1` to automatically configure all required settings. Manual configuration below is only needed if you prefer not to use the automated script.

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

1. Go to your repository
2. Click on the `Actions` tab
3. Select `Create Dependabot Security and Dependencies Labels` from the workflow list
4. Click `Run workflow` button
5. Select the branch `main` and click `Run workflow`
6. This will create all four labels:

If that doesn't work try the following

Go to `Issues` tab at the top of your repo and the select `Labels` and click `New label`

1. dependabot-dependencies
2. dependabot-security


## Creating the project

### Automated Solution Creation (Recommended)

If you used the automated setup script (`pwsh ./scripts/setup.ps1`), you had the option to create a default solution file automatically. The script creates a `.slnx` format solution (requires Visual Studio 2022 version 17.10+) with the following structure:
- Empty solution folders for `/benchmarks/`, `/examples/`, `/src/`, and `/tests/`
- A `/.root/` folder containing all repository configuration files (preserves directory structure)

If you chose to create a solution during setup, skip to step 2 below.

### Manual Solution Creation

If you didn't create a solution during setup or prefer the traditional `.sln` format:

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

**Note:** The release workflow automatically publishes packages to NuGet.org when you push a version tag (e.g., `v1.0.0`). See [RELEASE-WORKFLOW-SETUP.md](RELEASE-WORKFLOW-SETUP.md) for detailed information about the release workflow, testing, and troubleshooting.


## Update Template Files

After creating your repository from the template, update the following files with your project-specific information:

### Update README.md

1. Open `README.md` in the root folder
2. Replace the template content with your project's description
3. Add installation instructions, usage examples, and other relevant information

### Update CONTRIBUTING.md

1. Open `CONTRIBUTING.md`
2. Ensure any project name placeholders (for example, `{{PROJECT_NAME}}`) have been replaced with your actual project name (the automated setup scripts should normally do this for you)
3. Review and adjust contribution guidelines as needed for your project

### Update CODEOWNERS

1. Open `.github/CODEOWNERS`
2. Replace `{{GITHUB_USERNAME}}` with your GitHub username or team names
3. Uncomment and customize the example rules if you want different owners for specific directories

**Note:** The CODEOWNERS file determines who is automatically requested for review when someone opens a pull request.

### Update Documentation (Optional)

If you're using DocFX for documentation:
1. Review and customize the generated table of contents in `docfx_project/docs/toc.yml` as needed (the setup scripts already point this to your repository)
2. Customize the rest of the documentation content in `docfx_project/`
