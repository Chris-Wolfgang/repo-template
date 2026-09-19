# Workflow Security

## Overview

This document describes the security measures implemented in the GitHub Actions workflows for this repository, particularly focusing on the PR validation workflow (`.github/workflows/pr.yaml`).

## Security Architecture

### 1. Workflow YAML Protection

**Mechanism**: `pull_request_target` trigger

The PR workflow uses `pull_request_target` instead of `pull_request`. This means:
- The workflow YAML file is always executed from the base branch (main)
- Pull requests cannot modify the workflow logic that validates them
- Prevents malicious PRs from weakening or bypassing validation checks

**Code Reference**:
```yaml
on:
  pull_request_target:  # Runs from the main branch, not from PR branch
    branches:
      - main
```

### 2. Configuration File Protection

**Problem**: While `pull_request_target` protects the workflow YAML, the checked-out code includes configuration files (`.editorconfig`, `BannedSymbols.txt`, etc.) that control:
- Code analyzer behavior
- Code quality standards
- Security scanning rules

A malicious PR could modify these files to disable security checks.

**Solution**: After checking out the PR code, we fetch and overwrite configuration files from the trusted main branch.

**Protected Configuration Files**:
- `.editorconfig` (root and nested) - Code style and analyzer rules
- `Directory.Build.props` - MSBuild properties
- `Directory.Build.targets` - MSBuild targets
- `BannedSymbols.txt` - Banned API usage rules
- `coverlet.runsettings` - Coverage collection settings (exclusions, instrumentation)
- `*.globalconfig` - Global analyzer configuration
- `*.ruleset` - Code analysis rulesets
- `*.DotSettings` - ReSharper / InspectCode inspection severities
- `.github/workflows/*.yml` and `.github/workflows/*.yaml` - Workflow definitions

All wildcard entries (`*.editorconfig`, `*.globalconfig`, `*.ruleset`, `*.DotSettings`, `.github/workflows/*.yml`, `.github/workflows/*.yaml`) are matched case-insensitively — Windows (and ReSharper on it) resolve `foo.dotsettings` and `foo.DotSettings` to the same file, so both are protected — and `*.editorconfig` covers the root file and every nested one (a per-project `.editorconfig` overrides analyzer severities for everything beneath it). The fixed names (`Directory.Build.props`, `Directory.Build.targets`, `BannedSymbols.txt`, `coverlet.runsettings`) are matched exactly. A protected file the PR *adds* has no `main` copy to overwrite it with, so it is removed from the checkout before the build.

In addition to the overwrite step, the `Detect .NET Projects` job runs a "Detect protected configuration file changes" step that classifies the PR by what it changes relative to its merge base with `main`. A **configuration-only** PR (every changed file is a protected file) **passes** with a warning banner listing the files: CI could not exercise them (it ran `main`'s copies), but nothing else changed for the stale configuration to mis-validate, so it merges on review with the ruleset fully active. A PR that **mixes** protected files with any other change **fails** and cannot be bypassed: the other files were validated against the old configuration and the configuration change itself was untested. Split it - protected files in their own PR first, the rest rebased on top so it runs under the new configuration.

**Implementation** (in every job that consumes project source — `detect-projects`, `inspectcode`, the three test stages and `security-scan`; *not* the `secrets-scan` job, which only fetches `.gitleaks.toml`, and *not* `changelog-check`, which fetches `scripts/changelog.ps1`):
```yaml
- name: Fetch trusted configuration files from main branch
  run: |
    echo "Fetching configuration files from main branch to prevent malicious overrides..."
    
    # Fetch the main branch
    git fetch origin main:main-branch
    
    # List of configuration files that should come from trusted main branch
    config_files=(
      ".editorconfig"
      "Directory.Build.props"
      "Directory.Build.targets"
      "BannedSymbols.txt"
      "*.globalconfig"
      "*.ruleset"
      "*.DotSettings"
      ".github/workflows/*.yml"
      ".github/workflows/*.yaml"
    )

    # Copy each configuration file from main branch if it exists.
    # A failed copy aborts the job — an empty/partial file would silently
    # put the PR's own configuration in force.
    for config_file in "${config_files[@]}"; do
      # [Copy logic - see workflow file for full implementation]
    done
```

### 3. Credential Protection

**Mechanism**: `persist-credentials: false`

All checkout steps include `persist-credentials: false` to prevent the checkout token from being written to git config:

```yaml
- name: Checkout code
  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
  with:
    ref: refs/pull/${{ github.event.pull_request.number }}/head
    persist-credentials: false
```

**Note**: This prevents the token from being stored in git config, but does NOT prevent steps from accessing `GITHUB_TOKEN` if explicitly exposed.

### 4. Minimal Permissions

The workflow runs with minimal required permissions:

```yaml
permissions:
  contents: read
```

Jobs that need more (`security-events: write` to upload SARIF, `actions: read` for `upload-sarif`) declare it at the job level, so the elevation is scoped to that job only. This limits the impact if the `GITHUB_TOKEN` is somehow exposed or misused.

### 5. Same-Repository Guard on Jobs That Build PR Code With Write Scope

**Mechanism**: `github.event.pull_request.head.repo.full_name == github.repository`

Under `pull_request_target`, `github.repository` is *always* the base repository, so it cannot be used to exclude forks. The `inspectcode` job checks out and **builds** the PR's code while holding `security-events: write`; its `if:` therefore also requires the PR head to live in this repository. A fork PR skips the job rather than building untrusted code with an elevated token. The test stages build PR code too, but with `contents: read` only.

### 6. Pinned Actions and Audited Workflow Files

Every external action referenced by `uses:` in `.github/workflows/` is pinned to a full commit SHA with a `# vMAJOR.MINOR.PATCH` comment (repository baseline item 11; a same-repository reference such as `uses: ./.github/workflows/docfx.yaml` needs no pin — it runs at the calling commit); Dependabot's `github-actions` ecosystem moves the pins. `actions-audit.yaml` runs on every PR: `actionlint` (workflow YAML + embedded shell via shellcheck) is a hard gate, and `zizmor` uploads every finding to the Security tab and **fails the job on High-severity findings**. A deliberate pattern zizmor objects to — this file's `pull_request_target` is the standing example — is accepted with an inline `# zizmor: ignore[rule]` comment on the flagged key, never with a config file (`zizmor` only reads `.github/zizmor.yml`; a root `.zizmor.yml` is silently ignored). Because any such change touches a workflow file, it also trips the protected-file guard and is reviewed by a maintainer.

## Attack Scenarios Prevented

### Scenario 1: Malicious Workflow Modification
**Attack**: PR modifies `.github/workflows/pr.yaml` to disable security checks
**Prevention**: `pull_request_target` ensures workflow runs from main branch
**Status**: ✅ Protected

### Scenario 2: Configuration File Tampering
**Attack**: PR modifies `.editorconfig` to disable security analyzers
**Prevention**: Configuration files are fetched from main branch after checkout
**Status**: ✅ Protected

### Scenario 3: Credential Theft
**Attack**: PR contains malicious code that tries to access GitHub credentials
**Prevention**: `persist-credentials: false` + minimal permissions
**Status**: ✅ Protected

### Scenario 4: Code Analysis Bypass
**Attack**: PR modifies `BannedSymbols.txt`, `.ruleset` or `.DotSettings` to allow dangerous APIs or silence findings
**Prevention**: These files are fetched from main branch after checkout; the PR fails the protected-file guard
**Status**: ✅ Protected

### Scenario 5: Fork Builds Untrusted Code With Write Scope
**Attack**: A fork PR triggers `pull_request_target` and gets its code built by a job holding `security-events: write`
**Prevention**: The `inspectcode` job requires the PR head to be in this repository (see §5)
**Status**: ✅ Protected

### Scenario 6: Workflow Regression to an Unpinned or Injectable Step
**Attack**: A PR re-introduces `uses: some/action@v1`, an over-broad `permissions:`, or `${{ }}` expanded into a `run:` script
**Prevention**: `actions-audit.yaml` fails on High-severity zizmor findings; the change also fails the protected-file guard
**Status**: ✅ Protected

## Validation

The following manual validation scenarios can be used when reviewing changes to the workflow security model:

1. **Configuration Fetch Validation**: Confirm that configuration files are fetched from the `main` branch during workflow execution
2. **Malicious Modification Validation**: Simulate a PR that modifies `.editorconfig` to disable analyzers and confirm the workflow replaces it with the trusted version from `main`

## Maintenance

### Making Changes to Protected Configuration Files

To update protected configuration files (`.editorconfig`, `BannedSymbols.txt`, etc.), follow this workflow:

1. **Create a PR with your configuration changes — and nothing else**
   - Make changes to the configuration file(s) in your PR branch
   - The PR workflow will still fetch and use the current main branch version for testing
   - This means your PR will be tested against the **existing** configuration standards
   - If the PR changes **only** protected files, the `Detect .NET Projects` check passes with a warning banner listing them - that banner is the review signal. If it also changes anything else, the check fails: split the protected files into their own PR first.

2. **Get your PR reviewed and merged to main**
   - A maintainer reviews the configuration diff by hand and merges the configuration-only PR normally (no bypass exists; the ruleset stays active)
   - Once merged, your configuration changes become the new "trusted" version on main
   - Future PRs will automatically use your updated configuration
   - If a larger PR happens to include a protected-file change, split that change out into its own PR first so the rest can merge on green checks

3. **Why this works:**
   - Configuration changes are intentionally one commit behind during PR validation
   - This ensures you can't weaken security standards in the same PR that adds problematic code
   - After merge, the new standards apply to all subsequent PRs

**Example Workflow:**
```
PR #1: Update .editorconfig to add new rule
  ↓ (tested with old .editorconfig from main)
  ↓ (approved and merged)
  ↓
Main: Now has updated .editorconfig

PR #2: New feature
  ↓ (tested with updated .editorconfig from main)
  ↓ (builds/tests using new rules)
```

**Important Notes:**
- If you need to relax a security rule AND add code that violates the old rule in the same change, you'll need two PRs:
  1. First PR: Update the configuration file only
  2. Second PR: Add the code that requires the relaxed rules
- This is intentional security design to prevent simultaneous weakening of standards and addition of problematic code

### Adding New Protected Configuration Files

When adding new configuration files that control code quality or security:

1. Add the file name to the `config_files` array (bash) or `$configFiles` / `$globPatterns` (pwsh, Stage 2) in every job that runs `Fetch trusted configuration files from main branch` — `detect-projects`, `inspectcode`, the three test stages and `security-scan`; search `pr.yaml` for that step name to find them all. The `secrets-scan` and `changelog-check` jobs fetch only their own single file and do not need to be updated.
2. Add the file to the "Detect protected configuration file changes" guard in `pr.yaml` (its `grep -iE` pattern) so PRs that touch the file fail with a maintainer-review banner.
3. Test that the file is correctly fetched from main branch.
4. Update this documentation and the list in [CONTRIBUTING.md](../CONTRIBUTING.md).

## References

- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Keeping your GitHub Actions secure](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)
- [Understanding pull_request_target](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
