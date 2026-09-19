# Repository Baseline

Every repository owned by `Chris-Wolfgang` is measured against the items below. Gaps become one issue per
failing item in the repository where the item fails (title `Baseline: <item name>`, label `baseline` plus
`security` or `process`). The audit is automated by [`scripts/audit-repos.ps1`](../scripts/audit-repos.ps1);
this document is the human-readable definition of what that script checks and how to fix each gap.

Status vocabulary used by the audit:

| Status | Meaning |
|--------|---------|
| `pass` | Verified present and correct. |
| `fail` | Missing or wrong. An issue is opened in the repository. |
| `na` | Item does not apply to this repository (for example, AOT flags on a non-library repo). |
| `pending` | Cannot be decided yet (for example, custom secret patterns whose formats are not defined). No issue is opened. |

Scope rules:

- Every non-archived public repository is audited, game repositories included. Archived repositories are never audited.
- Public repositories only need free GitHub features. Nothing in this baseline requires GitHub Advanced Security billing.

## Items

### 1. Secret scanning enabled

- **Verify:** `gh api repos/{owner}/{repo} --jq '.security_and_analysis.secret_scanning.status'` returns `enabled`.
  Settings page: *Settings → Code security → Secret scanning*.
- **Fix:** Enable it on the settings page. Free for public repositories. Account-level default: *Settings → Code security → Enable for all repositories*.
- **Label:** `security`

### 2. Push protection enabled

- **Verify:** `gh api repos/{owner}/{repo} --jq '.security_and_analysis.secret_scanning_push_protection.status'` returns `enabled`.
- **Fix:** Enable it on the settings page (same page as item 1). Free for public repositories.
- **Label:** `security`

### 3. Custom secret patterns registered

- **Verify:** *Settings → Code security → Secret scanning → Custom patterns*. No API on a personal account.
- **Status:** `pending` until the WMS license-key and API-key formats are defined. Recorded as "pending WMS", not as a failure.
- **Fix:** Register the patterns once defined. Custom patterns may require GitHub Secret Protection on a personal account; confirm before enabling.
- **Label:** `security`

### 4. gitleaks pre-commit hook shipped

- **Verify:** Either `.pre-commit-config.yaml` references `gitleaks`, or `.githooks/pre-commit` exists and the README or CONTRIBUTING documents `git config core.hooksPath .githooks`.
- **Fix:** Copy `.githooks/pre-commit` from the template and document `core.hooksPath` in CONTRIBUTING.md.
- **Label:** `security`

### 5. Dependabot security updates on

- **Verify:** `gh api repos/{owner}/{repo}/automated-security-fixes --jq '.enabled'` returns `true`.
  Settings page: *Settings → Code security → Dependabot security updates*.
- **Fix:** Enable on the settings page. Account-level default: *Settings → Code security → Dependabot → Enable for all repositories*.
- **Label:** `security`

### 6. Dependabot version updates for NuGet and Actions

- **Verify:** `.github/dependabot.yml` exists and its `updates:` list contains `package-ecosystem: nuget` and `package-ecosystem: github-actions`.
- **Fix:** Copy `.github/dependabot.yml` from the template.
- **Label:** `security`

### 7. CodeQL workflow present and passing

- **Verify:** A file matching `.github/workflows/codeql*.y*ml` exists, and the most recent completed run of that workflow on the default branch has `conclusion: success`
  (`gh api repos/{owner}/{repo}/actions/workflows/<file>/runs?branch=<default>&status=completed&per_page=1`).
- **Fix:** Copy `.github/workflows/codeql.yaml` from the template; investigate failing runs with `gh run view --log-failed`.
- **Label:** `security`

### 8. gitleaks / DevSkim workflow present

- **Verify:** Some workflow under `.github/workflows/` invokes gitleaks or DevSkim on a `uses:` line (for example `gitleaks/gitleaks-action`, `microsoft/DevSkim-Action`) or inside a `run:` block. Comment lines and job/step `name:` lines do not count. The template's `pr.yaml` carries both (`secrets-scan` runs the gitleaks CLI, `security-scan` runs the DevSkim CLI).
- **Fix:** Copy `.github/workflows/pr.yaml` from the template (jobs `secrets-scan` and `security-scan`).
- **Label:** `security`

### 9. Branch ruleset on default branch

- **Verify:** `gh api repos/{owner}/{repo}/rulesets` lists a ruleset whose conditions include the default branch (`~DEFAULT_BRANCH` or the branch name) and whose rules include:
  `pull_request`, `required_status_checks`, `non_fast_forward` (no force-push), `deletion` (no deletion).
  Zero required approvals is acceptable for a solo developer. `required_linear_history` is reported as evidence but is **advisory** while linear history is trialled per repository (`wms` first); it becomes required once that trial settles.
- **Fix:** Run `scripts/Setup-BranchRuleset.ps1` from the template (add `-RequireLinearHistory` to opt into linear history, which also limits merges to squash/rebase; stacked PRs then use `scripts/restack.ps1` after each merge, see `docs/STACKED-PRS.md`), or fix the missing rule on the ruleset page of an existing repository.
- **Label:** `security`

### 10. Ruleset active with no person in the bypass list

- **Verify:** The ruleset from item 9 has `enforcement: active` and `bypass_actors` contains no entries with `actor_type` of `Team`, `Integration`, or a specific user. `RepositoryRole` (for example, repository admin) and `OrganizationAdmin` entries are allowed.
- **Fix:** Re-enable the ruleset; remove named users from the bypass list. Never disable a ruleset to merge: a configuration-only PR passes the protected-file guard on review, and a mixed PR is split (`protected-file-pr-split`) rather than bypassed.
- **Label:** `security`

### 11. Actions pinned by commit SHA

- **Verify:** Every `uses:` in `.github/workflows/*.y*ml` that references an external action (contains `/` and `@`, not starting with `./` or `docker://`) matches `@[0-9a-f]{40}`. A trailing `# vX.Y.Z` comment is expected so Dependabot can keep the pin current.
- **Fix:** Replace tags with the full commit SHA and a version comment, for example `actions/checkout@<sha>  # v7.0.0`.
- **Label:** `security`

### 12. `permissions:` block in every workflow

- **Verify:** Every file under `.github/workflows/*.y*ml` has a top-level `permissions:` key or a `permissions:` key on every job.
- **Fix:** Add `permissions: contents: read` at the top of the workflow and widen per job only where required.
- **Label:** `security`

### 13. CODEOWNERS present

- **Verify:** `.github/CODEOWNERS` (or `CODEOWNERS` at the root or under `docs/`) exists.
- **Fix:** Copy `.github/CODEOWNERS` from the template.
- **Label:** `process`

### 14. SECURITY.md with a reporting channel

- **Verify:** `SECURITY.md` (root or `.github/`) exists and contains a reporting channel: an email address, or the words `security advisory` / `Report a vulnerability`, or a `github.com/.../security/advisories` link.
- **Fix:** Copy `SECURITY.md` from the template.
- **Label:** `process`

### 15. CODE_OF_CONDUCT.md and CONTRIBUTING.md present

- **Verify:** Both `CODE_OF_CONDUCT.md` and `CONTRIBUTING.md` exist (root or `.github/`).
- **Fix:** Copy both from the template.
- **Label:** `process`

### 16. LICENSE present and correct

- **Verify:** `LICENSE` (or `LICENSE.md` / `LICENSE.txt`) exists. For library repositories the license is one the template offers — MIT, Apache-2.0 or MPL-2.0 (`gh api repos/{owner}/{repo} --jq '.license.spdx_id'`). The custom/TBD placeholder ("all rights reserved pending selection") reports as `pending`, not a failure. Non-library repositories pass with any recognised license.
- **Fix:** Run the template's `scripts/setup.ps1` license step, or copy the matching `LICENSE-*.txt` and fill in the year and holder.
- **Label:** `process`

### 17. OpenSSF Scorecard workflow present; badge in README

- **Verify:** A workflow under `.github/workflows/` uses `ossf/scorecard-action`, and `README.md` contains `api.securityscorecards.dev` or `scorecard.dev`. The current score is read from `https://api.securityscorecards.dev/projects/github.com/{owner}/{repo}` and recorded as evidence when available.
- **Fix:** Copy the Scorecard workflow from the template and add the badge to the README badge row.
- **Label:** `process`

### 18. `IsAotCompatible` and `IsTrimmable` enabled

- **Verify:** Library repositories only (a `src/**/*.csproj` exists). `Directory.Build.props` or every `src/**/*.csproj` sets `<IsAotCompatible>true</IsAotCompatible>` and `<IsTrimmable>true</IsTrimmable>` (a TFM condition is fine; `IsAotCompatible=true` implies `IsTrimmable` on net8.0+). The audit checks the properties only. Trim and AOT warnings (`IL2xxx` / `IL3xxx`) are surfaced by the Release build once the properties are on, and item 21 turns them into errors, so they are gated by CI rather than by this audit.
- **Status:** `na` for non-library repositories.
- **Fix:** Add both properties to `Directory.Build.props` under a `net8.0`-or-later condition and fix any `IL2xxx` / `IL3xxx` warnings.
- **Label:** `process`

### 19. Changelog fragments convention and CI check

- **Verify:** `changelog/unreleased/` exists (with its `README.md`), and a workflow under `.github/workflows/` invokes `scripts/changelog.ps1 check` (or contains `changelog.ps1`).
- **Fix:** Copy `changelog/unreleased/README.md`, `scripts/changelog.ps1`, and the `changelog-check` step of `pr.yaml` from the template.
- **Label:** `process`

### 20. Security-alert triage workflow present

- **Verify:** `.github/workflows/security-alerts.yml` (or `.yaml`) exists.
- **Fix:** Copy `.github/workflows/security-alerts.yml` and `scripts/security-alerts.ps1` from the template, then add the `SECURITY_ALERTS_TOKEN` repository secret (fine-grained PAT: Secret scanning alerts read, Dependabot alerts read, Metadata read; one token scoped to all repositories is fine). Without it those reads fall back to `GITHUB_TOKEN`; a kind is skipped with a notice only when that fallback is denied (always for secret-scanning, account-dependent for Dependabot).
- **Label:** `security`

### 21. Warnings-as-errors on for Release builds

- **Verify:** `Directory.Build.props` sets `<TreatWarningsAsErrors>true</TreatWarningsAsErrors>` with `Condition="'$(Configuration)' == 'Release'"` (either MSBuild quote style inside the attribute). An unconditional `true` fails, because it would also gate Debug; any other condition (Debug-only, per-TFM, per-project) fails too. Repositories with no `.csproj` are `na`.
  Release is the configuration CI builds, tests, and packs, so this is what keeps warnings out of packages. Debug is deliberately left with warnings as warnings so local iteration is not blocked by an analyzer mid-edit; build with `-c Release` before pushing to see what CI will see.
- **Fix:** Add to `Directory.Build.props` (the template already has it):
  `<TreatWarningsAsErrors Condition="'$(Configuration)' == 'Release'">true</TreatWarningsAsErrors>`. Fix warnings; suppress narrowly only where unavoidable.
- **Label:** `process`

### 22. README with build and test instructions

- **Verify:** `README.md` exists and mentions both `dotnet build` and `dotnet test` (or a `build-pr.ps1` / `build.ps1` script) for .NET repositories; non-.NET repositories pass with any README that has a section named Build, Usage, or Getting Started.
- **Fix:** Add a "Building and testing" section; the template's `README-TEMPLATE.md` has one.
- **Label:** `process`

### 23. GitHub Pages deploy mode matches the docs workflow

- **Verify:** For a repository whose `docfx.yaml` pushes the built site to the `gh-pages` branch (the canonical pattern), `gh api repos/{owner}/{repo}/pages` reports `build_type: legacy` and `source.branch: gh-pages`. A repository whose docs workflow uses `actions/deploy-pages` must report `build_type: workflow` instead. Repositories with no docs workflow, or with a docs workflow but no Pages site yet, are `na`.
- **Why:** Pages only auto-publishes a `gh-pages` push in `legacy` mode. Three repositories sat on `build_type: workflow` with a push-to-branch workflow and served stale docs for weeks while every deploy went green (repo-template#344). The mismatch is invisible from the workflow run; this item makes it visible.
- **Fix:** `gh api -X PUT repos/{owner}/{repo}/pages -f build_type=legacy -f source[branch]=gh-pages -f source[path]=/` (or the Pages settings page: *Build and deployment → Source → Deploy from a branch*). Do not switch the workflow to `actions/deploy-pages` to match the setting — versioned docs need the branch.
- **Label:** `process`

### 24. No workflow disabled for inactivity

- **Verify:** `gh api repos/{owner}/{repo}/actions/workflows` reports `state: active` for every workflow file under `.github/workflows/`. Any `disabled_inactivity` (or `disabled_manually`) entry fails.
- **Why:** GitHub switches off *scheduled* workflows in a repository with no commits for 60 days. The switch is per workflow file, so it also stops the `pull_request` runs of that file — on Conflict.Classic and Conflict.Modern the weekly CodeQL run went quiet after 2026-08-30 and the next PR sat on "Expected — Security Scan (CodeQL)" forever, because a required check from a disabled workflow can never report. Nothing in the PR, the ruleset or the Actions tab of the run says why.
- **Fix:** `gh api -X PUT repos/{owner}/{repo}/actions/workflows/{file}/enable`, then push a commit (or re-run) so the PR gets a fresh run — a workflow without `workflow_dispatch` cannot be triggered by hand. Any commit to the default branch resets the 60-day clock for the whole repository.
- **Label:** `process`

## Account-level settings

These are not per-repository and are not checked by the script. Verify on the account settings pages and record the state; the audit report lists them under "manual checks".

| Setting | Where | Expected |
|---------|-------|----------|
| Push protection for all public repositories | *Settings → Code security → Secret scanning → Enable for all repositories* | On |
| Dependabot alerts default-on for new repositories | *Settings → Code security → Dependabot alerts* | On |
| Dependabot security updates default-on for new repositories | *Settings → Code security → Dependabot security updates* | On |

## Running the audit

```powershell
pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang            # audit only, writes audit-results.json + audit-summary.md
pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang -OpenIssues # also open one issue per failing item
pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang -Repo ETL-Csv,ETL-Json  # subset
pwsh ./scripts/audit-repos.ps1 -Owner Chris-Wolfgang -Exclude Hawsey,D20-Dice   # everything but these
```

Requires `gh` authenticated as the owner (rulesets and `automated-security-fixes` need admin read). Every run re-checks
everything; issues are deduplicated by title, so re-running after fixing a gap only opens issues for gaps that remain.
