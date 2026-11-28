type: internal

`scripts/Setup-BranchRuleset.ps1` now creates the Actions policy that allows `pull_request_target` for `.github/workflows/protected-files.yaml` right after the ruleset (baseline item 25), and `-PullRequestTargetPolicyOnly` creates just that policy on a repository whose ruleset already exists. The README's manual `policy.json` step is replaced by it.
