# Workflow Security

## Overview

This document describes the security model of the GitHub Actions workflows in this repository, centred on the PR validation workflow (`.github/workflows/pr.yaml`) and the protected-files guard (`.github/workflows/protected-files.yaml`) that keeps it honest.

The model in one paragraph: **PR checks run on `pull_request`, so a PR is built and tested with its own code and its own copies of every workflow and config file — exactly what merges — inside a run that GitHub gives a read-only token and no secrets. Gate integrity comes from one small `pull_request_target` workflow that never checks out or executes anything from the PR: it lists the PR's changed files through the API and refuses any PR that changes a protected file alongside other changes.** A PR therefore cannot weaken a check it is subject to except as a configuration-only PR that a maintainer reviews on its own.

## Security Architecture

### 1. PR Checks Run in an Unprivileged Context

**Mechanism**: `pull_request` trigger (plus `push` to `main`)

```yaml
on:
  pull_request:
    branches:
      - main
  push:
    branches:
      - main
```

- The workflow file, the code and every analyzer/config file come from the PR's merge commit, so what is validated is what merges.
- GitHub gives a `pull_request` run a **read-only `GITHUB_TOKEN`** and **no repository secrets** when the PR comes from a fork; `pr.yaml` declares `permissions: contents: read` so same-repo PRs get the same. Nothing in `pr.yaml` reads a secret.
- The push-to-`main` run re-validates the merged result and keeps the InspectCode alert set on `main` current — a `pull_request` run attributes its SARIF to the PR ref, not to `main`.

**Why not `pull_request_target`?** Running the *base* branch's workflow against the *PR's* code gives that code the base repository's identity (secrets, a token that can be granted write scopes). Every job that built PR code was a place where a malicious MSBuild target or test could reach that identity, and Scorecard's *Dangerous-Workflow* and CodeQL's *untrusted-checkout* rightly flag the shape. Under `pull_request` there is nothing to reach.

### 2. Protected Files Guard

**Mechanism**: `protected-files.yaml` — the one workflow on `pull_request_target`, and the reason it may be: it **never checks out or executes PR content**. It runs from `main` (a PR cannot edit it), lists the PR's changed files through the API (`pulls/{n}/files`), and classifies the PR:

| The PR changes… | Result |
|---|---|
| no protected file | pass — `pr.yaml` validated everything |
| **only** protected files | pass with a notice: this is the change that decides what future PRs are checked against, so a maintainer reviews the diff itself |
| protected files **and** anything else | **fail, and nothing can bypass it** — split the PR |

**Protected files** — everything that shapes what CI checks:
- `.github/workflows/*.yml` / `*.yaml` — the workflows themselves
- `.editorconfig` (root and nested), `*.globalconfig`, `*.ruleset`, `*.DotSettings` — analyzer and InspectCode severities
- `Directory.Build.props`, `Directory.Build.targets`, `BannedSymbols.txt` — build properties and banned-API rules
- `coverlet.runsettings` — coverage collection (exclusions, instrumentation)
- `.config/dotnet-tools.json` — the pinned versions of every CI tool (`dotnet tool restore`); a PR must not be able to redirect which tool code CI executes
- `.github/license-audit/*.json` — license-audit policy (allow-list, ignored packages, URL mappings, overrides), read by `license-audit.yaml`
- `.gitleaks.toml` — secrets-scan rules and allowlist
- `scripts/changelog.ps1`, `scripts/tfm-parity.ps1`, `scripts/build-pr.ps1`, `scripts/third-party-notices.ps1` — the CI scripts `pr.yaml` and `license-audit.yaml` run from the PR's tree

Wildcards are matched case-insensitively (Windows and ReSharper resolve `foo.dotsettings` and `foo.DotSettings` to the same file). Renames count for both the old and the new name; deletions count.

**Why the mixed-PR rule still exists.** Under `pull_request` a mixed PR *is* fully validated — the PR's config applies to the PR's code — so the old "validated against stale config" argument is gone. The rule stays for reviewability: a weakened `.editorconfig` hidden among forty code files is exactly the change that must not slip through, and forcing it into a PR of its own makes it the only thing the reviewer looks at.

The guard's check is **`Protected Files Guard`** and must be a required status check in the ruleset (`scripts/Setup-BranchRuleset.ps1` adds it). Dependabot PRs are exempt: its bumps to `Directory.Build.props` are legitimate and its identity is GitHub-controlled.

### 3. Credential Protection

**Mechanism**: `persist-credentials: false`

Every checkout uses `persist-credentials: false`, so the job token is never written to `.git/config` where a build step could read it:

```yaml
- name: Checkout code
  uses: actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1  # v7.0.1
  with:
    persist-credentials: false
```

**Note**: this keeps the token out of git config; it does not stop a step that is *explicitly* handed `${{ github.token }}` from using it. `pr.yaml` hands it to exactly one command — the `changelog-check` job's `git fetch` of the base commit, needed on private repositories — and never stores it.

### 4. Minimal Permissions

```yaml
permissions:
  contents: read
```

is the workflow default. The only elevation is `security-events: write` (+ `actions: read`) on `inspectcode-upload`, scoped to that job.

### 5. No Write Scope in Any Job That Builds PR Code

**Mechanism**: job split — `inspectcode` (checks out and builds PR code, `contents: read` only, hands `inspect.sarif` off as an artifact) and `inspectcode-upload` (checks out the base branch, never PR code, downloads the artifact and is the only job holding `security-events: write`).

Every job that runs the PR's code — `detect-projects`, `inspectcode`, the three test stages, `security-scan` — holds `contents: read` and nothing else, so a PR's MSBuild targets, tests or analyzers can reach neither the repository nor Code Scanning through the job token. `inspectcode-upload` is skipped for fork and Dependabot PRs, whose token cannot write Code Scanning anyway; those PRs still get the InspectCode gate.

### 6. Pinned Actions and Audited Workflow Files

Every external action referenced by `uses:` in `.github/workflows/` is pinned to a full commit SHA with a `# vMAJOR.MINOR.PATCH` comment (repository baseline item 11; a same-repository reference such as `uses: ./.github/workflows/docfx.yaml` needs no pin — it runs at the calling commit); Dependabot's `github-actions` ecosystem moves the pins. `actions-audit.yaml` runs on every PR: `actionlint` (workflow YAML + embedded shell via shellcheck) is a hard gate, and `zizmor` uploads every finding to the Security tab and **fails the job on High-severity findings**. The one deliberate pattern zizmor objects to — `protected-files.yaml`'s `pull_request_target` — is accepted with an inline `# zizmor: ignore[dangerous-triggers]` on the flagged key, never with a config file (`zizmor` only reads `.github/zizmor.yml`; a root `.zizmor.yml` is silently ignored). Because any such change touches a workflow file, it also trips the protected-files guard and is reviewed by a maintainer.

## Attack Scenarios Prevented

### Scenario 1: Malicious Workflow Modification
**Attack**: PR modifies `.github/workflows/pr.yaml` to disable security checks
**Prevention**: The change is a protected file. Mixed with code, the guard fails and cannot be bypassed; on its own, it is a configuration-only PR a maintainer reviews line by line before it becomes the workflow future PRs run under. The guard itself runs from `main` and cannot be edited by the PR.
**Status**: ✅ Protected

### Scenario 2: Configuration File Tampering
**Attack**: PR modifies `.editorconfig` to disable security analyzers
**Prevention**: Same as Scenario 1 — protected file; mixed PRs fail, configuration-only PRs are reviewed in isolation
**Status**: ✅ Protected

### Scenario 3: Credential Theft
**Attack**: PR contains malicious code that tries to access GitHub credentials
**Prevention**: `pull_request` runs carry no secrets (forks) and a read-only token; `persist-credentials: false`; the token is handed to exactly one fetch command
**Status**: ✅ Protected

### Scenario 4: Code Analysis Bypass
**Attack**: PR modifies `BannedSymbols.txt`, `.ruleset`, `.DotSettings` or `scripts/tfm-parity.ps1` to allow dangerous APIs or silence findings
**Prevention**: All are protected files (Scenario 1)
**Status**: ✅ Protected

### Scenario 5: PR Code Reaches a Write Scope
**Attack**: A PR (fork or same-repo) puts a payload in an MSBuild target, test or analyzer that forges or dismisses Code Scanning alerts with the job token
**Prevention**: No job that builds PR code holds a write scope; the SARIF upload runs in a separate job that never checks out PR code (see §5)
**Status**: ✅ Protected

### Scenario 6: Workflow Regression to an Unpinned or Injectable Step
**Attack**: A PR re-introduces `uses: some/action@v1`, an over-broad `permissions:`, or `${{ }}` expanded into a `run:` script
**Prevention**: `actions-audit.yaml` fails on High-severity zizmor findings; the change is also a protected-file change (Scenario 1)
**Status**: ✅ Protected

### Scenario 7: Guard Evasion
**Attack**: A PR tries to disable the protected-files guard itself
**Prevention**: The guard runs from `main` (`pull_request_target`) regardless of what the PR's tree contains, and editing `protected-files.yaml` is itself a protected-file change
**Status**: ✅ Protected

## Validation

When reviewing changes to the workflow security model:

1. **Configuration-only PR**: open a PR that changes only `.editorconfig`; confirm `Protected Files Guard` passes with the notice and `pr.yaml` ran with the changed file.
2. **Mixed PR**: add a `.cs` change to that PR; confirm `Protected Files Guard` fails and the failure cannot be bypassed.
3. **Code-only PR**: confirm the guard passes silently and every gate ran on the merge commit.
4. **Scanner view**: confirm no Scorecard *Dangerous-Workflow* or CodeQL *untrusted-checkout* alert exists on `pr.yaml` (there is no PR-head checkout anywhere), and that `protected-files.yaml` carries no checkout at all.

## Maintenance

### Making Changes to Protected Configuration Files

1. **Create a PR with your configuration changes — and nothing else.** `pr.yaml` runs with the changed configuration, so the run shows what it will do; `Protected Files Guard` passes with a notice listing the files. If the PR also changes anything else the guard fails: split the protected files into their own PR first.
2. **A maintainer reviews the diff itself and merges normally** — no bypass exists and the ruleset stays active. From then on every PR is checked against the new configuration.
3. **Relaxing a rule and adding code that needs it** therefore takes two PRs: the configuration change first (reviewed on its own), the code second. That is the point of the rule.

### Adding New Protected Files

1. Add the file to `protected-files.yaml` — the fixed-name `case` list for an exact name, or the `grep -iE` pattern for a wildcard.
2. Update this document and the list in [CONTRIBUTING.md](../CONTRIBUTING.md).

## References

- [GitHub Actions Security Hardening](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions)
- [Keeping your GitHub Actions secure](https://docs.github.com/en/actions/security-guides/security-hardening-for-github-actions#using-third-party-actions)
- [Preventing pwn requests (why `pull_request_target` + PR checkout is dangerous)](https://securitylab.github.com/research/github-actions-preventing-pwn-requests/)
