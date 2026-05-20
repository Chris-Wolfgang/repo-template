This issue is the living **improvement menu** for this repo. It is intentionally evergreen — the parent stays open forever. Sub-issues are spawned from the categories below as work begins, and they get closed when complete. The parent is never closed.

## How this works

- **This issue (`quality` label)** is the per-repo reference. Read it to see candidate work for this repo.
- **Sub-issues (`quality-task` + `quality:<category>` labels)** are the actual tracked work.
- All `quality-task` issues across all repos roll up into the Quality project board: {{QUALITY_PROJECT_URL}}
- To create a sub-issue, use the **"Quality task"** issue template (`.github/ISSUE_TEMPLATE/quality-task.yaml`). It pre-fills the `quality-task` label and prompts for category, scope, acceptance criteria, and links. After creation, **manually add the matching `quality:<category>` label** — issue forms can't apply labels dynamically based on dropdown selections yet.

## Candidate tasks by category

### Security (`quality:security`)
- Run SAST / analyzer scan
- Audit dependencies for CVEs / outdated packages
- Fix findings from scans

### Performance (`quality:performance`)
- Profile hot paths
- Add benchmarks for identified hotspots
- Optimize bottlenecks found via profiling / benchmarks
- Validate performance gains via benchmark deltas

### Testing (`quality:testing`)
- Achieve / maintain code coverage ≥ 90 %
- Add integration test suite
- Add mutation tests (Stryker)
- Refactor test fixtures
- Add CI test-step improvements (e.g. coverage collectors, gates)

### Cleanup (`quality:cleanup`)
- Refactor for reuse / quality / efficiency ("simplify pass")
- Remove dead code

### Docs (`quality:docs`)
- XML doc coverage on all public API
- Refresh README and CHANGELOG
- Add usage samples

### API (`quality:api`)
- Audit public vs internal surface
- Breaking-change vigilance / API review

### CI/CD (`quality:cicd`)
- Refactor CI workflows
- Set up Docker build (if applicable)
- Improve packaging / publish pipeline

## Notes

- Not every category is relevant to every repo at every time. **Spawn sub-issues only when there is actionable work** — don't pre-fill the categories with placeholder tasks.
- Repo-specific decisions that don't fit the fleet-wide pattern (e.g., dropping a TFM, a one-off bug fix, a feature request) are tracked as **regular issues without the `quality:` prefix**. They stay out of the Project board.
- This issue should not be closed. If everything is "done", that just means there's no actionable work right now — but the categories remain a reference for the next cycle.
