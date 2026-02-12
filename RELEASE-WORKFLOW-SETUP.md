# Release Workflow Setup Guide

This guide explains how to configure the repository after merging the updated `release.yaml` workflow.

## Overview

The release workflow implements a comprehensive validation and automatic deployment process that:
- ✅ Tests all target frameworks per test project on Windows
- ✅ Enforces 90% code coverage threshold
- ✅ Validates NuGet package integrity with smoke tests
- ✅ Automatically publishes to NuGet.org after validation passes
- ✅ Creates GitHub releases with artifacts and coverage reports
- ✅ Eliminates duplicate build work for faster releases

## Required Post-Merge Configuration

After merging this PR, complete the following setup step:

### Add NuGet API Key Secret

**Location:** Settings → Secrets and variables → Actions → New repository secret

1. Click **"New repository secret"**
2. **Name:** `NUGET_API_KEY`
3. **Value:** Your NuGet.org API key
   - Get your key from [NuGet.org Account → API Keys](https://www.nuget.org/account/apikeys)
   - Recommended scopes: **Push new packages and package versions**
   - Set expiration date (recommended: 1 year)
4. Click **"Add secret"**

**What this does:** Allows the workflow to authenticate with NuGet.org and publish packages. The workflow validates this secret exists before attempting to publish.

### Verify Branch Protection Rules

**Location:** Settings → Branches → main

> **Note:** By default, the template is configured for single developer repositories. The branch protection setup script (`scripts/Setup-BranchRuleset.ps1`) includes interactive prompts that allow you to choose between single-developer or multi-developer settings during execution. Simply run the script and select option [1] for single-developer mode (0 approvals) or option [2] for multi-developer mode (1+ approvals and code owner review required).

Ensure the following settings are enabled:

- ✅ **Require a pull request before merging**
  - **Single developer repos:** 0 approvals (default)
  - **Multi-developer repos:** 1+ approvals (recommended)
- ✅ **Require status checks to pass before merging**
  - Required checks should include the following status check contexts:
    - "Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate"
    - "Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)"
    - "Stage 3: macOS Tests (.NET 6.0-10.0)"
    - "Security Scan (DevSkim)"
    - "Security Scan (CodeQL)"
- ✅ **Require branches to be up to date before merging**
- ✅ **Require conversation resolution before merging**
- ✅ **Do not allow bypassing the above settings** (recommended, even for admins)
- ✅ **Restrict deletions**
- ✅ **Require linear history** (optional but recommended)

**What this does:** Ensures all code merged to `main` has passed comprehensive validation, preventing broken releases.

## Testing the Release Workflow

After completing the setup, test the workflow with a test tag:

```bash
# Create and push a test tag
git tag v0.0.1-test
git push origin v0.0.1-test
```

### Expected Workflow Behavior

1. **Job 1: validate-release** (3-10 minutes)
   - Runs all framework tests with coverage
   - Enforces 90% coverage threshold
   - Uploads coverage report
   - ✅ Auto-passes if tests succeed

2. **Job 2: pack-and-validate** (2-5 minutes)
   - Packs NuGet packages
   - Performs smoke test installation
   - Uploads packages as artifacts
   - ✅ Auto-passes if packages are valid

3. **Job 3: publish-nuget** (1-2 minutes)
   - Validates NUGET_API_KEY secret
   - Publishes packages to NuGet.org automatically
   - ✅ Auto-completes if secret is valid

4. **Job 4: create-github-release** (1-2 minutes)
   - Creates GitHub release
   - Attaches `.nupkg` files and coverage report
   - Generates release notes automatically
   - Marks as prerelease if tag contains `-` (e.g., `-test`, `-beta`)
   - ✅ Auto-completes

### Monitoring the Workflow

- **Actions Tab:** Shows workflow progress in real-time
- **Artifacts:** Each job uploads artifacts (coverage reports, packages)
- **Releases:** Check the Releases page after successful completion

## Troubleshooting

### "NUGET_API_KEY secret not configured" Error

**Problem:** The `publish-nuget` job fails with secret validation error.

**Solution:**
1. Verify the secret name is exactly `NUGET_API_KEY` (case-sensitive)
2. Re-add the secret in Settings → Secrets → Actions
3. Re-run the workflow (this will restart the jobs using the updated secret; don't re-tag)

### Tests Fail on Specific Framework

**Problem:** Tests pass on some frameworks but fail on others (e.g., net462).

**Solution:**
1. Check the test logs for framework-specific issues
2. Fix compatibility issues in your code
3. Test locally: `dotnet test --framework net462`
4. Push fix and re-tag

### Coverage Below 90% Threshold

**Problem:** Workflow fails at coverage validation step.

**Solution:**
1. Review `CoverageReport/Summary.txt` artifact
2. Add tests for uncovered code paths
3. Ensure tests run on all frameworks
4. Re-tag after improving coverage

### Smoke Test Fails to Install Package

**Problem:** Package packs successfully but fails smoke test installation.

**Solution:**
1. Check package dependencies in `.csproj`
2. Verify framework compatibility in `<TargetFrameworks>`
3. Test locally: `dotnet pack` then try installing in a test project
4. Fix packaging issues and re-tag

## Production Release Checklist

Before creating a production release tag (e.g., `v1.0.0`):

- [ ] All tests pass on all platforms (pr.yaml workflow)
- [ ] Code coverage meets 90% threshold
- [ ] Security scan shows no critical issues
- [ ] Version numbers updated in `.csproj` files
- [ ] `CHANGELOG.md` updated with release notes (if applicable)
- [ ] All PRs merged to `main` branch
- [ ] Local build succeeds: `dotnet build --configuration Release`
- [ ] Local tests pass: `dotnet test --configuration Release`

**Create production tag:**
```bash
git tag v1.0.0
git push origin v1.0.0
```

**After workflow completes:**
- [ ] Verify packages appear on NuGet.org
- [ ] Check GitHub release has correct artifacts
- [ ] Test installing package from NuGet.org in a clean project
- [ ] Announce release (if applicable)

## Workflow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  Trigger: Push tag v*.*.*                                   │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌─────────────────────────────────────────────────────────────┐
│  Job 1: validate-release (Windows)                          │
│  • Restore & Build                                          │
│  • Test all frameworks (net5.0-10.0, net462-481)           │
│  • Collect coverage                                         │
│  • Enforce 90% threshold                                    │
│  • Upload coverage artifacts                                │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ (only if tests pass)
┌─────────────────────────────────────────────────────────────┐
│  Job 2: pack-and-validate (Windows)                         │
│  • Restore & Build (fresh)                                  │
│  • Pack NuGet packages                                      │
│  • Smoke test installation                                  │
│  • Upload package artifacts                                 │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ (only if packing succeeds)
┌─────────────────────────────────────────────────────────────┐
│  Job 3: publish-nuget (Windows)                             │
│  • Download packages                                        │
│  • Validate NUGET_API_KEY                                   │
│  • Publish to NuGet.org automatically                       │
└─────────────────────────────────────────────────────────────┘
                            │
                            ▼ (only if publishing succeeds)
┌─────────────────────────────────────────────────────────────┐
│  Job 4: create-github-release (Windows)                     │
│  • Download packages & coverage                             │
│  • Create GitHub release                                    │
│  • Attach artifacts                                         │
│  • Generate release notes                                   │
└─────────────────────────────────────────────────────────────┘
```

## Key Improvements Over Previous Workflow

| Issue | Before | After |
|-------|--------|-------|
| **Framework Coverage** | Default framework only | All frameworks (net5.0-10.0, net462-481) |
| **Code Coverage** | Not enforced | 90% threshold enforced |
| **Package Validation** | None | Smoke test installation |
| **Deployment** | Incomplete publish script | Automatic publishing after validation |
| **Secret Validation** | None | Validates before publishing |
| **GitHub Releases** | Not created | Automated with artifacts |
| **Build Efficiency** | Duplicate builds in each job | Build once per job with dependencies |
| **Test Logging** | No logger parameter | Console logging with verbosity |
| **Permissions** | Read-only | Write access for releases |

## Support

If you encounter issues not covered in this guide:

1. Check the [Actions tab](../../actions) for detailed logs
2. Review artifacts uploaded by failed jobs
3. Consult the [GitHub Actions documentation](https://docs.github.com/en/actions)
4. Open an issue in this repository with:
   - Tag name used
   - Workflow run URL
   - Error message and logs
   - Steps to reproduce
