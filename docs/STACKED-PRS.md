# Stacked pull requests with linear history

Repositories that enable **Require linear history** on `main` (baseline item 9; `Setup-BranchRuleset.ps1 -RequireLinearHistory`)
accept only squash or rebase merges. That keeps `main` a straight line, one commit per PR, at the cost of one
extra step when PRs are stacked. This page is the whole workflow.

## Building a stack

One linear stack per repository. Each PR branches from the tail of the stack, not from `main`:

```bash
git switch -c feat/pick-list main            # PR 1, targets main
git switch -c feat/pick-confirm feat/pick-list   # PR 2, targets feat/pick-list
git switch -c feat/pick-audit feat/pick-confirm  # PR 3, targets feat/pick-confirm
```

Open each PR against the branch below it. Its diff on GitHub shows only its own layer.

Keep stack branches current by **rebasing**, never by merging `main` into them. A merge commit inside a stack
branch has to be re-resolved every time the stack is replayed.

## Merging

1. **Squash-merge the bottom PR.** (Rebase-merge also satisfies the rule; squash gives one commit per PR.)
   GitHub deletes the branch and retargets the next PR to `main`, but that PR's branch still contains the
   merged PR's *original* commits, so its diff looks wrong and *Update branch* will often conflict.
2. **Restack** from a clean clone:

   ```powershell
   pwsh ./scripts/restack.ps1 -Stack feat/pick-confirm,feat/pick-audit
   ```

   For each remaining branch, bottom to top, the script runs
   `git rebase --onto <new base> <old cut point> <branch>` so only that PR's own commits are replayed, then
   `git push --force-with-lease=<branch>:<old tip>`. The cut point for the first branch is the merged PR's
   head SHA (found automatically from the merged PR, or passed with `-MergedTip`); for the others it is the
   previous branch's tip before the run. It also checks that each PR's base on GitHub is the branch below it.
   `-DryRun` prints the plan.
3. Repeat: merge the new bottom PR, restack the rest.

Only feature branches are ever force-pushed, each with an explicit lease. `main` is never force-pushed.

## Will restacking conflict?

Not because of the squash. The squashed commit is byte-identical to the content the next PR was written on,
so its commits replay cleanly. Conflicts come only from the usual sources:

- something *else* landed on `main` in between and touched the same lines;
- a `main`-sync merge commit inside a stack branch (see above);
- two PRs in the stack editing the same lines, which conflicts under any merge strategy.

Changelog fragments (`changelog/unreleased/`) remove the most common shared edit, `CHANGELOG.md`, so a normal
stack restacks with no conflicts. If one does occur the script stops, prints the resolve-and-continue steps,
and tells you how to re-run for the remaining branches.

## Why this is worth it

`main` has exactly one commit per PR: `git bisect` lands on a PR, `git revert` of one commit undoes one PR,
and OpenSSF Scorecard and the repository baseline both check for it. If the restack step turns out to cost
more than that buys, drop the rule with the ruleset page and update baseline item 9 to match.
