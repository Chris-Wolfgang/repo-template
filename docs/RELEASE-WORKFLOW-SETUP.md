# Release Workflow Setup Guide

This guide explains how to configure a repository to use the standard `release.yaml` workflow. The same checklist applies whether you are bootstrapping a new repo from `repo-template` or auditing an existing one.

## Overview

The release workflow triggers when you **publish a GitHub Release** and implements a comprehensive validation and automatic deployment process that:
- ✅ Checks the release tag matches a `<Version>` (or `<PackageVersion>`) declared in `src/`
- ✅ Tests all target frameworks per test project on Windows
- ✅ Enforces the coverage gates (90 % line coverage for `src/`, 100 % for `tests/`)
- ✅ Validates NuGet package integrity with smoke tests and generates a CycloneDX SBOM
- ✅ Builds the DocFX documentation before publishing, so a docs failure blocks the package
- ✅ Records a SLSA build-provenance attestation for every package (`gh attestation verify`)
- ✅ Publishes to NuGet.org via OIDC trusted publishing — no stored API key
- ✅ Deploys the versioned documentation to `gh-pages`
- ✅ Attaches the packages, SBOM and coverage report to the GitHub Release

## Required Configuration

Complete the following one-time setup so that the workflow can publish releases.

### Configure NuGet.org Trusted Publishing

The workflow authenticates to NuGet.org with a short-lived token minted from the GitHub Actions OIDC identity (`NuGet/login`); there is **no `NUGET_API_KEY` secret** to create or rotate. NuGet.org must be told which workflow is allowed to publish.

**Location:** [NuGet.org → Account → Trusted Publishing](https://www.nuget.org/account/trustedpublishing)

1. Click **Add** (or **Create**) a trusted publishing policy.
2. **Repository owner:** the GitHub account/org that owns the repo (for example `Chris-Wolfgang`)
3. **Repository:** the repository name
4. **Workflow file:** `release.yaml`
5. **Environment:** leave blank — the canonical workflow does not use a GitHub environment
6. Save. The policy's **NuGet.org user** must match the `user:` input of the `NuGet login` step in `release.yaml`.

**What this does:** When `publish-nuget` runs, `NuGet/login` exchanges the job's OIDC token (the job requests `id-token: write`) for a temporary NuGet API key scoped to the packages the policy allows. The key never leaves the job. Full reference: [Trusted publishing on NuGet.org](https://learn.microsoft.com/nuget/nuget-org/trusted-publishing).

> **Policy scopes:** a policy says whether it may publish *new packages* and/or *new versions of existing packages*, optionally narrowed by a package-ID glob. For a repo that has never published, the policy needs the new-package scope (or push the first version by hand and let the policy handle the rest). A policy for a **private** repository starts as *temporarily active* for 7 days and becomes permanent on the first successful publish.

### Verify Branch Protection Rules

**Location:** Settings → Rules → Rulesets (or Settings → Branches → main)

> **Note:** Repos created from `repo-template` ship with `scripts/Setup-BranchRuleset.ps1`, which creates the ruleset interactively (option `[1]` for single-developer mode, `[2]` for multi-developer mode) with the required checks below already listed. `scripts/Fix-BranchRuleset.ps1` replaces the ruleset when a check name changes upstream (delete + recreate via Setup-BranchRuleset.ps1; it does not patch in place). The repository baseline (`docs/repository-baseline.md`, items 9 and 10) is the audited standard.

Ensure the following settings are enabled:

- ✅ **Require a pull request before merging**
  - **Single developer repos:** 0 approvals (default)
  - **Multi-developer repos:** 1+ approvals (recommended)
- ✅ **Require status checks to pass before merging**, with these contexts:
  - "Detect .NET Projects"
  - "Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate"
  - "Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)"
  - "Stage 3: macOS Tests (.NET 6.0-10.0)"
  - "Security Scan (DevSkim)"
  - "Security Scan (CodeQL) (csharp)"
  - "Secrets Scan (gitleaks)"
  - "Changelog Fragment Check"
- ✅ **Require conversation resolution before merging**
- ✅ **Block force pushes** and **Restrict deletions**
- ⬜ **Require linear history** — optional. `Setup-BranchRuleset.ps1 -RequireLinearHistory` adds it (and limits merges to squash/rebase); stacked PRs then use `scripts/restack.ps1` after each merge, see [STACKED-PRS.md](STACKED-PRS.md). It is being trialled per repo, not fleet-wide.

**What this does:** Ensures all code merged to `main` has passed comprehensive validation, preventing broken releases. Keep the ruleset **active** — disable nothing to merge; a configuration-only PR passes the protected-file guard on review, and a mixed PR is split (baseline item 10).

## Cutting a Release

1. Make sure every merged PR that touched `src/` left a fragment in `changelog/unreleased/` (the `Changelog Fragment Check` enforces this).
2. On a release branch, assemble the changelog and bump the version:
   ```powershell
   pwsh ./scripts/changelog.ps1 bump                  # prints the derived next version
   pwsh ./scripts/changelog.ps1 assemble -Version X.Y.Z
   ```
   Set `<Version>X.Y.Z</Version>` in the `src/` csproj(s) to the same value — `validate-release` fails unless the tag matches a `<Version>` or `<PackageVersion>` found under `src/` — and merge that PR.
3. Go to the repository's **Releases** page → **Draft a new release**.
4. Create the tag `vX.Y.Z` targeting `main`, add a title and the release notes (the new CHANGELOG section is a good body).
5. For a test run, tick **Set as a pre-release**. The tag still has to match the csproj: set `<Version>0.0.1-test</Version>` and tag `v0.0.1-test`, or the run stops at the version check.
6. Click **Publish release**. The workflow triggers on `release: published`.

### Expected Workflow Behavior

1. **validate-release** (3-10 minutes, Windows)
   - Checks the tag against the `<Version>` / `<PackageVersion>` values found in `src/`
   - Runs every target framework of every test project with coverage
   - Enforces the coverage gates (90 % `src/`, 100 % `tests/`) and uploads the report

2. **pack-and-validate** (2-5 minutes, Windows)
   - Packs NuGet packages, smoke-tests installing each one into a scratch project
   - Generates a CycloneDX SBOM (`*.bom.json`) per package
   - Uploads the packages as an artifact; sets `has-packages` for the later jobs

3. **verify-docs-build** (Windows) — skipped when there is no `docfx_project/docfx.json`
   - Builds the DocFX site without deploying, so a docs error blocks the package instead of landing after it

4. **publish-nuget** (1-2 minutes, Windows) — only when packages were produced
   - `actions/attest-build-provenance` signs a SLSA provenance attestation for each `.nupkg` (recorded under the repo's Attestations; verify with `gh attestation verify <pkg>.nupkg --repo <owner>/<repo> --signer-workflow <owner>/<repo>/.github/workflows/release.yaml`)
   - `NuGet/login` mints a short-lived key via OIDC trusted publishing
   - `dotnet nuget push --skip-duplicate` for every `.nupkg`

5. **trigger-docs** — calls `docfx.yaml` to build and deploy the versioned docs to `gh-pages`

6. **update-release-artifacts** — attaches the `.nupkg` / `.snupkg` / `.bom.json` files and the zipped coverage report to the GitHub Release with `gh release upload`

### Monitoring the Workflow

- **Actions tab:** shows workflow progress in real time
- **Artifacts:** each job uploads artifacts (coverage report, packages)
- **Releases:** the assets appear on the release page after `update-release-artifacts`
- **NuGet.org:** the package is visible immediately; the CDN used by `dotnet restore` can lag by minutes to half an hour
- **Docs:** run `pwsh ./scripts/Validate-DocsDeploy.ps1` after the deploy to check the `gh-pages` structure

## Troubleshooting

### `NuGet login` Fails or the Push Is Rejected With 401/403

**Problem:** `publish-nuget` fails at the login or push step.

**Solution:**
1. Confirm a trusted-publishing policy exists on NuGet.org for this owner, repository and `release.yaml` (an environment set on the policy that the workflow does not use will also fail the match)
2. Confirm the `user:` input of the `NuGet login` step is the NuGet.org account that owns the policy
3. Confirm the job still declares `id-token: write`
4. Re-run the workflow from the Actions tab (do not re-publish the release)

### Tag Does Not Match csproj Version

**Problem:** `validate-release` fails at "Validate release tag matches csproj version".

**Solution:** The tag (`v1.2.3`, leading `v` optional) must equal a `<Version>` or `<PackageVersion>` declared in a `src/` csproj. Fix the csproj (or the tag), merge, delete the release and the tag, and publish again.

### Tests Fail on a Specific Framework

**Problem:** Tests pass on some frameworks but fail on others (for example `net462`).

**Solution:**
1. Check the test logs for framework-specific issues
2. Fix compatibility issues in your code
3. Test locally: `dotnet test --framework net462`
4. Push the fix, then re-publish the release (or re-run the workflow from the Actions tab)

### Coverage Below the Gate

**Problem:** The workflow fails at "Verify coverage threshold".

**Solution:**
1. Review the `CoverageReport/Summary.txt` artifact — the gate is per assembly: 90 % for `src/`, 100 % for `tests/` (test code that never runs is dead code)
2. Add tests for the uncovered paths, or delete unreachable test helpers
3. Ensure tests actually run on every framework — a framework with zero tests fails on its own
4. Push the fix, then re-publish the release (or re-run the workflow from the Actions tab)

### Smoke Test Fails to Install a Package

**Problem:** The package packs but fails the smoke-test installation.

**Solution:**
1. Check the package dependencies in the `.csproj`
2. Verify framework compatibility in `<TargetFrameworks>`
3. Test locally: `dotnet pack`, then install the result into a scratch project
4. Fix the packaging issue and re-publish the release (or re-run the workflow from the Actions tab)

### Assets Not Attached to the Release

**Problem:** `update-release-artifacts` fails uploading to the release.

**Solution:** A release marked **immutable** rejects asset uploads after it is published. Leave the immutable option off for now; the canonical draft-then-publish flow for immutable releases is tracked in repo-template#340.

## Production Release Checklist

Before publishing a production GitHub Release (for example `v1.0.0`):

- [ ] All PRs merged to `main`; `pr.yaml` green on the last one
- [ ] Every `src/` change since the last release has a changelog fragment (or the `no-changelog` label)
- [ ] `pwsh ./scripts/changelog.ps1 assemble -Version X.Y.Z` run and merged
- [ ] `<Version>X.Y.Z</Version>` set in the `src/` csproj(s) (the tag must match one of them) and merged
- [ ] Local dry run passes: `pwsh ./scripts/build-pr.ps1`
- [ ] Security tab shows no open High/Critical alerts

**After the workflow completes:**
- [ ] Verify the packages appear on NuGet.org and restore into a clean project
- [ ] Verify the docs deployed: `pwsh ./scripts/Validate-DocsDeploy.ps1`
- [ ] Verify the assets are attached to the release
- [ ] If the repo enables package validation, bump `PackageValidationBaselineVersion` to the new version in a follow-up PR once the package is on the CDN

## Workflow Architecture

```
┌──────────────────────────────────────────────────────────────┐
│  Trigger: Published GitHub Release                           │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  validate-release (Windows)                                  │
│  • Tag == a <Version> / <PackageVersion> under src/           │
│  • Restore & Build (Release)                                 │
│  • Test every TFM of every test project, with coverage       │
│  • Coverage gates: 90 % src, 100 % tests                     │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼ (only if tests pass)
┌──────────────────────────────────────────────────────────────┐
│  pack-and-validate (Windows)                                 │
│  • Pack NuGet packages • Smoke-test installation             │
│  • CycloneDX SBOM • Upload package artifact                  │
└──────────────────────────────────────────────────────────────┘
              │                                  │
              ▼                                  ▼
┌────────────────────────────┐    ┌────────────────────────────┐
│  verify-docs-build         │    │  trigger-docs → docfx.yaml │
│  DocFX build, no deploy    │    │  (after validate-release)  │
└────────────────────────────┘    │  versioned deploy to       │
              │                   │  gh-pages                  │
              ▼ (only if docs build)└──────────────────────────┘
┌──────────────────────────────────────────────────────────────┐
│  publish-nuget (Windows)                                     │
│  • SLSA build-provenance attestation per .nupkg              │
│  • NuGet/login (OIDC trusted publishing)                     │
│  • dotnet nuget push --skip-duplicate                        │
└──────────────────────────────────────────────────────────────┘
                            │
                            ▼
┌──────────────────────────────────────────────────────────────┐
│  update-release-artifacts                                    │
│  • gh release upload: *.nupkg, *.snupkg, *.bom.json,         │
│    release-coverage.zip                                      │
└──────────────────────────────────────────────────────────────┘
```

## Support

If you encounter issues not covered in this guide:

1. Check the Actions tab of this repository on GitHub for detailed logs
2. Review the artifacts uploaded by the failed job
3. Consult the [GitHub Actions documentation](https://docs.github.com/en/actions)
4. Open an issue in this repository with:
   - Workflow run URL
   - Error message and logs
   - Steps to reproduce
