# Changelog fragments

`CHANGELOG.md` is not edited by hand. Every pull request that changes `src/` adds **one fragment file** to
this directory; at release time the fragments are assembled into a new version section and deleted.
This avoids merge conflicts on `CHANGELOG.md` and keeps each entry next to the change that earned it.

## Writing a fragment

Create `changelog/unreleased/<short-change-name>.md` (kebab-case, named for the change, not the PR number):

```
type: feature

Add `IsDryRun` to every loader options record so pipelines can be rehearsed without writing.
```

- **Line 1** is `type: <kind>` where `<kind>` is one of:

  | Kind | Use for | Assembles under |
  |------|---------|-----------------|
  | `breaking` | Any change that breaks source or binary compatibility | Breaking changes |
  | `feature` | New public surface or behaviour | Added |
  | `fix` | Bug fix with no new surface | Fixed |
  | `docs` | User-facing documentation only | Documentation |
  | `internal` | Refactors, CI, tests, dependencies with no user-visible effect | Internal |

- **The rest** is a one-sentence, user-facing description. Say what changed for the consumer, not how.
  Markdown inline code is fine. The PR number is appended automatically at assembly time when it can be
  found in the fragment's git history.

One fragment per PR is the norm. A PR that makes two independently notable changes may add two.

## When a fragment is not needed

Add the `no-changelog` label to the PR. Use it for changes under `src/` that have no user-visible effect
and are not worth an `internal` entry (typo in a comment, formatting). Dependabot PRs are exempt automatically.

The CI check reads labels at the time the PR event fires, and **re-running the check replays that
original event payload** rather than reading current state. A label added after the check failed
therefore never reaches it. Push a commit (or rebase) to fire a fresh event.

**A release PR is exempt automatically.** `assemble` deletes every fragment and writes them into the
changelog, and the same PR necessarily touches `src/` (the csproj `<Version>`) — so it changes `src/`
and adds no fragment, which is exactly the shape the check rejects. When a PR deletes one or more
fragments *and* changes the changelog file, the check treats it as the assembly and passes. Do **not**
reach for `no-changelog` on a release: that label is for changes that never needed a note, not for the
one PR that carries all of them. The changelog compared against is `-ChangelogPath` (default
`CHANGELOG.md`), so a repository that keeps its changelog elsewhere is exempt on the same terms.

Some files under `src/` never need a fragment and the check ignores them, so no label is required:
nested `.editorconfig` files, `*.globalconfig` / `*.ruleset` / `*.DotSettings` files, and the
`PublicAPI.Shipped.txt` / `PublicAPI.Unshipped.txt` baselines. None of them can change what the
library does for a consumer.

The analyzer-config files among those are also **protected**, so a PR touching one usually *cannot*
carry a fragment even if you wanted it to: the protected-file guard fails any PR that mixes a
protected file with anything else. The `PublicAPI.*.txt` baselines are **not** protected, so a
baseline-only PR — or a baseline change riding along with code — can carry a fragment. It simply
does not need one.

## The check

`scripts/changelog.ps1 check` fails a PR when files under `src/` changed and no fragment was added,
unless the PR carries `no-changelog` **or the PR is the release that assembles the fragments**.
It also validates every fragment in this directory: a recognised `type:` on line 1 and a non-empty
description.

```powershell
pwsh ./scripts/changelog.ps1 check                     # against origin/main
pwsh ./scripts/changelog.ps1 check -BaseRef origin/vNext
```

## Assembling a release

```powershell
pwsh ./scripts/changelog.ps1 assemble                  # derives the version from the fragments
pwsh ./scripts/changelog.ps1 assemble -Version 0.9.0   # or pin it
pwsh ./scripts/changelog.ps1 bump                      # print the derived version and exit
```

`assemble` inserts a `## [<version>] - <today>` section directly under `## [Unreleased]` in `CHANGELOG.md`,
grouped by kind in the order above, then deletes the fragments. Commit the result as part of the release PR.

Version derivation starts from the newest `## [x.y.z]` heading already in `CHANGELOG.md` and applies the
highest-ranked fragment kind present:

| Current | `breaking` | `feature` | `fix` / `docs` / `internal` |
|---------|-----------|-----------|------------------------------|
| `0.x`   | minor     | minor     | patch                        |
| `>= 1.0` | major    | minor     | patch                        |

Patch releases are lean (fixes only): any new public surface is a minor. Pre-1.0 the minor version is also
the compatibility line, so a breaking change lands on the same minor bump as a feature.
