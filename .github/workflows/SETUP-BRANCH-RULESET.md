# Setup Branch Ruleset Workflow Documentation

## Overview

### Purpose
The `setup-branch-ruleset.yml` workflow is a **one-time automation** that configures comprehensive branch protection for the `main` branch in repositories created from this template. It eliminates the need for manual ruleset configuration through the GitHub UI.

### When It Runs
- **Manually only:** Via workflow dispatch from the Actions tab
- **Scope:** Only runs in repositories created from the template (skips the template repository itself)
- **Trigger:** Repository owner must manually trigger this workflow after creating a repository from the template

### What It Does
1. Checks if the "Protect main branch" ruleset already exists
2. Creates the ruleset if it doesn't exist (using `.github/ruleset-config.json`)
3. Automatically creates a cleanup branch and pull request
4. Removes the setup files (workflow and config) in the cleanup PR
5. Provides instructions for the repository owner to review and merge

---

## Workflow Execution Flow

```
START
  │
  ├─► Template Check
  │   ├─► Is template repo? ──[YES]──► SKIP (Exit)
  │   └─► Not template ──────[NO]───► Continue
  │
  ├─► Checkout Repository
  │
  ├─► Check If Ruleset Exists
  │   ├─► API Call: GET /repos/{owner}/{repo}/rulesets
  │   ├─► Filter by name: "Protect main branch"
  │   └─► Set output: exists=true/false
  │
  ├─► Decision: Ruleset Exists?
  │   │
  │   ├─► [YES] ──► Finalize (Already Exists)
  │   │             │
  │   │             ├─► Output: Ruleset already configured
  │   │             ├─► Provide manual cleanup instructions
  │   │             └─► END
  │   │
  │   └─► [NO] ──► Create Ruleset
  │                 │
  │                 ├─► API Call: POST /repos/{owner}/{repo}/rulesets
  │                 │    (using .github/ruleset-config.json)
  │                 │
  │                 ├─► Success? ──[NO]──► FAIL (Exit with error)
  │                 │
  │                 └─► [YES] ──► Automated Cleanup Process
  │                               │
  │                               ├─► Configure Git Identity
  │                               │   (github-actions[bot])
  │                               │
  │                               ├─► Create Cleanup Branch
  │                               │   (cleanup/remove-ruleset-setup-{timestamp})
  │                               │
  │                               ├─► Remove Setup Files
  │                               │   ├─► git rm .github/ruleset-config.json
  │                               │   └─► git rm .github/workflows/setup-branch-ruleset.yml
  │                               │
  │                               ├─► Commit Changes
  │                               │   (with descriptive message)
  │                               │
  │                               ├─► Push Cleanup Branch
  │                               │   (to remote)
  │                               │
  │                               ├─► Create Pull Request
  │                               │   ├─► Title: "chore: Clean up branch ruleset setup files"
  │                               │   ├─► Body: Comprehensive explanation
  │                               │   ├─► Base: main
  │                               │   └─► Head: cleanup/remove-ruleset-setup-{timestamp}
  │                               │
  │                               ├─► Output Workflow Summary
  │                               │   (GitHub Actions summary with links)
  │                               │
  │                               └─► WAIT FOR MANUAL MERGE
  │                                   │
  │                                   └─► (Repository owner reviews and merges PR)
  │                                       │
  │                                       └─► END (Setup files removed, ruleset persists)
```

---

## Detailed Step-by-Step Breakdown

### Phase 1: Initial Checks (Decision Tree)

#### 1.1 Template Repository Check
- **Condition:** `github.repository != 'Chris-Wolfgang/repo-template'`
- **Purpose:** Prevents the workflow from running in the template repository itself
- **Outcome:**
  - ✅ Not template → Continue
  - ❌ Is template → Skip entire job

#### 1.2 Ruleset Existence Check
- **Action:** Query GitHub API for existing rulesets
- **API Endpoint:** `GET /repos/{owner}/{repo}/rulesets`
- **Filter:** `select(.name=="Protect main branch")`
- **Output:** `steps.check.outputs.exists` (true/false)
- **Error Handling:** Exits with error if API call fails

### Phase 2: Ruleset Creation

#### 2.1 Create Ruleset (if doesn't exist)
- **Condition:** `steps.check.outputs.exists == 'false'`
- **Action:** Create ruleset via GitHub API
- **API Endpoint:** `POST /repos/{owner}/{repo}/rulesets`
- **Input:** `.github/ruleset-config.json`
- **Error Handling:** Captures API response and exits on failure
- **Output:** `steps.create_ruleset.outcome` (success/failure)

### Phase 3: Automated Cleanup (NEW)

All steps in this phase are conditional on:
```yaml
if: steps.check.outputs.exists == 'false' && steps.create_ruleset.outcome == 'success'
```

#### 3.1 Configure Git Identity
- **User:** `github-actions[bot]`
- **Email:** `github-actions[bot]@users.noreply.github.com`
- **Purpose:** Properly attribute automated commits

#### 3.2 Create Cleanup Branch
- **Branch Name Pattern:** `cleanup/remove-ruleset-setup-{unix-timestamp}`
- **Example:** `cleanup/remove-ruleset-setup-1707456789`
- **Purpose:** Isolate cleanup changes from main branch
- **Environment Variable:** `CLEANUP_BRANCH` (stored for later steps)

#### 3.3 Remove Setup Files
- **Files Deleted:**
  - `.github/ruleset-config.json`
  - `.github/workflows/setup-branch-ruleset.yml`
- **Method:** `git rm` (stages deletion for commit)

#### 3.4 Commit Cleanup Changes
- **Commit Message:**
  ```
  chore: remove branch ruleset setup files

  - Removed .github/ruleset-config.json
  - Removed .github/workflows/setup-branch-ruleset.yml

  These files are no longer needed after the ruleset has been successfully created.
  ```

#### 3.5 Push Cleanup Branch
- **Action:** Push to remote repository
- **Branch:** Value from `$CLEANUP_BRANCH` environment variable

#### 3.6 Create Pull Request
- **Title:** "chore: Clean up branch ruleset setup files"
- **Base Branch:** `main`
- **Head Branch:** `cleanup/remove-ruleset-setup-{timestamp}`
- **Body Contents:**
  - Success celebration
  - Complete list of protections enabled
  - Files being removed and rationale
  - Verification instructions
  - Next steps for repository owner
  - Explanation of why it can't auto-merge

#### 3.7 Output Workflow Summary
- **Location:** GitHub Actions summary page
- **Contents:**
  - Success message
  - List of enabled protections
  - Link to ruleset settings
  - Instructions to review and merge the PR

### Phase 4: Completion Paths

#### 4.1 Success Path (New Ruleset Created)
1. Ruleset created successfully
2. Cleanup PR created and awaiting review
3. Workflow summary displayed
4. Repository owner merges PR manually
5. Setup files removed, ruleset persists

#### 4.2 Already Exists Path
1. Ruleset already exists
2. Skip creation and cleanup
3. Display instructions for manual cleanup or re-running
4. Workflow completes

#### 4.3 Failure Paths
- **API Failure:** Exit with error and display API response
- **Git Operation Failure:** Automatic failure with error message
- **PR Creation Failure:** Exit with GitHub CLI error

---

## Ruleset Configuration

The `.github/ruleset-config.json` file defines the complete branch protection configuration:

### Core Configuration
```json
{
  "name": "Protect main branch",
  "target": "branch",
  "enforcement": "active"
}
```

- **name:** Display name in GitHub UI
- **target:** Applies to branches (not tags)
- **enforcement:** Active (rules are enforced) vs. evaluate (dry-run mode)

### Target Branches
```json
"conditions": {
  "ref_name": {
    "include": ["refs/heads/main"],
    "exclude": []
  }
}
```

- **include:** Only applies to `main` branch
- **exclude:** No exclusions

### Bypass Actors
```json
"bypass_actors": [
  {
    "actor_id": 1,
    "actor_type": "RepositoryRole",
    "bypass_mode": "always"
  }
]
```

- **actor_id: 1** = Repository Admin role
- **bypass_mode: always** = Admins can bypass all rules
- **Rationale:** Allows emergency fixes and workflow troubleshooting

### Pull Request Rules
```json
{
  "type": "pull_request",
  "parameters": {
    "required_approving_review_count": 0,
    "dismiss_stale_reviews_on_push": true,
    "require_code_owner_review": false,
    "require_last_push_approval": false,
    "required_review_thread_resolution": true
  }
}
```

- **required_approving_review_count: 0** = No approvals required (single-developer friendly)
- **dismiss_stale_reviews_on_push: true** = Re-review after new commits
- **require_code_owner_review: false** = Not required (single-developer)
- **required_review_thread_resolution: true** = All discussions must be resolved

**For multi-developer repositories:** Update to require 1+ approvals and code owner review.

### Required Status Checks
```json
{
  "type": "required_status_checks",
  "parameters": {
    "strict_required_status_checks_policy": true,
    "required_status_checks": [
      { "context": "Stage 1: Linux Tests (.NET 5.0-10.0) + Coverage Gate" },
      { "context": "Stage 2: Windows Tests (.NET 5.0-10.0, Framework 4.6.2-4.8.1)" },
      { "context": "Stage 3: macOS Tests (.NET 6.0-10.0)" },
      { "context": "Security Scan (DevSkim)" },
      { "context": "Security Scan (CodeQL)" }
    ]
  }
}
```

- **5 Required Status Checks:**
  1. **Stage 1:** Linux multi-framework tests + 90% coverage gate
  2. **Stage 2:** Windows multi-framework tests (including .NET Framework)
  3. **Stage 3:** macOS multi-framework tests
  4. **DevSkim:** Security pattern scanning
  5. **CodeQL:** Security vulnerability detection

- **strict_required_status_checks_policy: true** = Branches must be up to date with main

### Code Scanning Rules
```json
{
  "type": "code_scanning",
  "parameters": {
    "code_scanning_tools": [
      {
        "tool": "CodeQL",
        "security_alerts_threshold": "high_or_higher",
        "alerts_threshold": "errors"
      }
    ]
  }
}
```

- **tool: CodeQL** = GitHub's semantic code analysis engine
- **security_alerts_threshold: high_or_higher** = Blocks on High or Critical severity
- **alerts_threshold: errors** = Blocks on error-level findings

### Additional Protections
```json
{ "type": "non_fast_forward" },  // Block force pushes
{ "type": "deletion" },           // Prevent branch deletion
{ "type": "update" }              // Require pull requests for updates
```

---

## File State Changes

### Before Workflow Execution
```
.github/
├── ruleset-config.json           ✅ EXISTS
├── workflows/
│   ├── setup-branch-ruleset.yml  ✅ EXISTS
│   ├── pr.yaml                   ✅ EXISTS
│   └── ...                       ✅ EXISTS
```

**Repository Settings:**
- ❌ No "Protect main branch" ruleset

### After Successful Execution (Before PR Merge)
```
.github/
├── ruleset-config.json           ✅ STILL EXISTS (on main)
├── workflows/
│   ├── setup-branch-ruleset.yml  ✅ STILL EXISTS (on main)
│   ├── pr.yaml                   ✅ EXISTS
│   └── ...                       ✅ EXISTS

Branches:
├── main                          ✅ Original files intact
└── cleanup/remove-ruleset-setup-{timestamp}
    ├── ruleset-config.json       ❌ DELETED
    └── setup-branch-ruleset.yml  ❌ DELETED
```

**Repository Settings:**
- ✅ "Protect main branch" ruleset exists and is active

**Pull Requests:**
- ✅ Cleanup PR created (awaiting review)

### After PR Merge (Final State)
```
.github/
├── workflows/
│   ├── pr.yaml                   ✅ EXISTS
│   ├── codeql.yml                ✅ EXISTS
│   └── ...                       ✅ EXISTS
```

**Deleted Files:**
- ❌ `.github/ruleset-config.json` (no longer needed)
- ❌ `.github/workflows/setup-branch-ruleset.yml` (no longer needed)

**Repository Settings:**
- ✅ "Protect main branch" ruleset **still exists and is active**
  - Rulesets persist in repository settings independently of config files
  - Can be viewed at: Settings → Rules → Rulesets

---

## Conditional Execution Matrix

| Condition | Template Repo? | Ruleset Exists? | API Success? | Outcome |
|-----------|----------------|-----------------|--------------|---------|
| 1 | Yes | N/A | N/A | Skip entire job (no execution) |
| 2 | No | Yes | N/A | Skip creation, show manual cleanup instructions |
| 3 | No | No | Yes | Create ruleset → Create cleanup PR → Success |
| 4 | No | No | No | Attempt creation → API fails → Exit with error |
| 5 | No | Check fails | N/A | API error checking rulesets → Exit with error |

---

## Timeline View

**Typical Execution Time:** ~30-60 seconds

| Step | Duration | Cumulative Time |
|------|----------|----------------|
| Checkout repository | ~5s | 5s |
| Check if ruleset exists | ~3s | 8s |
| Create ruleset (API call) | ~5s | 13s |
| Configure Git | <1s | 13s |
| Create cleanup branch | <1s | 14s |
| Remove setup files | <1s | 15s |
| Commit changes | <1s | 16s |
| Push cleanup branch | ~5s | 21s |
| Create pull request | ~5s | 26s |
| Output summary | <1s | 27s |
| **Total** | | **~27-30s** |

**Post-Workflow:**
- Manual PR review: Variable (minutes to hours)
- PR merge: ~5-10s
- **Total end-to-end:** ~30s automated + manual review time

---

## State Diagram

```
┌─────────────────────────────────────────────────────────────┐
│                       INITIAL STATE                         │
│  Files: ✅ workflow.yml, ruleset-config.json                │
│  Ruleset: ❌ Does not exist                                 │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Workflow Triggered
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│                    CHECKING STATE                           │
│  Action: Query GitHub API for existing ruleset             │
└─────────────────────────┬───────────────────────────────────┘
                          │
              ┌───────────┴───────────┐
              │                       │
         Exists?                  Doesn't exist?
              │                       │
              ▼                       ▼
┌─────────────────────────┐  ┌─────────────────────────────────┐
│   ALREADY CONFIGURED    │  │      CREATING STATE             │
│  Output: Instructions   │  │  Action: POST API call          │
│  Files: Unchanged       │  │  Status: Creating ruleset       │
└─────────────────────────┘  └──────────┬──────────────────────┘
                                        │
                                   Success?
                                        │
                              ┌─────────┴─────────┐
                              │                   │
                            Fail                Success
                              │                   │
                              ▼                   ▼
                    ┌──────────────────┐  ┌─────────────────────────────┐
                    │   ERROR STATE    │  │   CLEANUP STATE             │
                    │  Exit with error │  │  Files: ✅ workflow.yml,    │
                    └──────────────────┘  │         ruleset-config.json │
                                          │  Ruleset: ✅ Created         │
                                          │  Action: Creating cleanup   │
                                          └──────────┬──────────────────┘
                                                     │
                                                     │ Create branch,
                                                     │ remove files,
                                                     │ commit, push
                                                     │
                                                     ▼
                                          ┌─────────────────────────────┐
                                          │  AWAITING REVIEW STATE      │
                                          │  PR: ✅ Created              │
                                          │  Branch: cleanup/remove-*   │
                                          │  Files on main: Unchanged   │
                                          │  Ruleset: ✅ Active          │
                                          └──────────┬──────────────────┘
                                                     │
                                              Owner reviews PR
                                                     │
                                                     ▼
                                          ┌─────────────────────────────┐
                                          │    FINAL STATE              │
                                          │  Files: ❌ Deleted           │
                                          │  Ruleset: ✅ Active          │
                                          │  Status: Complete           │
                                          └─────────────────────────────┘
```

---

## Error Handling Flow

```
┌─────────────────────────────────────────────────────────────┐
│                    WORKFLOW STARTS                          │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
                ┌─────────────────────┐
                │  Template Check     │
                └──────────┬──────────┘
                           │
                    Is Template?
                           │
                ┌──────────┴──────────┐
                │                     │
              YES                    NO
                │                     │
                ▼                     ▼
        ┌──────────────┐      ┌──────────────┐
        │  SKIP JOB    │      │  Continue    │
        │  (Success)   │      └──────┬───────┘
        └──────────────┘             │
                                     ▼
                          ┌──────────────────┐
                          │  API: Get        │
                          │  Rulesets        │
                          └────────┬─────────┘
                                   │
                            ┌──────┴──────┐
                            │             │
                       API Fails      API Success
                            │             │
                            ▼             ▼
                    ┌──────────────┐  ┌──────────────────┐
                    │  ERROR EXIT  │  │  Parse Response  │
                    │  Show Error  │  └────────┬─────────┘
                    └──────────────┘           │
                                        ┌──────┴──────┐
                                        │             │
                                    Exists      Doesn't Exist
                                        │             │
                                        ▼             ▼
                              ┌──────────────┐  ┌──────────────────┐
                              │  Skip        │  │  API: Create     │
                              │  Creation    │  │  Ruleset         │
                              └──────────────┘  └────────┬─────────┘
                                                         │
                                                  ┌──────┴──────┐
                                                  │             │
                                             API Fails      API Success
                                                  │             │
                                                  ▼             ▼
                                          ┌──────────────┐  ┌──────────────────┐
                                          │  ERROR EXIT  │  │  Automated       │
                                          │  Show Error  │  │  Cleanup Process │
                                          └──────────────┘  └────────┬─────────┘
                                                                     │
                                                              ┌──────┴──────┐
                                                              │             │
                                                         Git Fails     Git Success
                                                              │             │
                                                              ▼             ▼
                                                      ┌──────────────┐  ┌──────────────────┐
                                                      │  ERROR EXIT  │  │  Create PR       │
                                                      │  (Automatic) │  └────────┬─────────┘
                                                      └──────────────┘           │
                                                                          ┌──────┴──────┐
                                                                          │             │
                                                                     PR Fails      PR Success
                                                                          │             │
                                                                          ▼             ▼
                                                                  ┌──────────────┐  ┌──────────────────┐
                                                                  │  ERROR EXIT  │  │  SUCCESS         │
                                                                  │  Show Error  │  │  Output Summary  │
                                                                  └──────────────┘  └──────────────────┘
```

**Recovery Options:**
- **API Failures:** Check GitHub status, verify token permissions, retry workflow
- **Git Failures:** Typically automatic failures; check workflow logs
- **PR Creation Failures:** Verify `pull-requests: write` permission exists, check network connectivity

---

## Key Design Decisions

### 1. Idempotent Design
- **Decision:** Check for existing ruleset before attempting creation
- **Rationale:** Allows safe re-runs without errors or duplicates
- **Benefit:** Workflow can be manually triggered multiple times

### 2. Template-Aware Execution
- **Decision:** Skip execution in template repository itself
- **Condition:** `github.repository != 'Chris-Wolfgang/repo-template'`
- **Rationale:** Template doesn't need its own ruleset; prevents accidental activation
- **Benefit:** Clean template repository without active rulesets

### 3. Safe Error Handling
- **Decision:** Capture and display API errors instead of silent failures
- **Implementation:** `set +e`, capture output, `set -e`, check exit code
- **Benefit:** Clear debugging information when issues occur

### 4. Admin Bypass Enabled
- **Decision:** Allow repository admins to bypass all rules
- **Rationale:** Emergency fixes, workflow troubleshooting, flexibility for repository owner
- **Trade-off:** Reduces protection for admins, but increases operational flexibility

### 5. Zero Required Approvals (Default)
- **Decision:** Default to 0 required PR approvals
- **Rationale:** Single-developer repositories don't need self-approvals
- **Customization:** Multi-developer repos should update config before first run
- **Benefit:** Frictionless workflow for solo developers

### 6. Self-Cleanup Limitation
- **Decision:** Cannot automatically merge cleanup PR
- **Rationale:** The workflow respects the branch protection it just created
- **Alternative Considered:** Delete files in the same push (rejected due to unreliability with rulesets)
- **Benefit:** Ensures human review before permanent deletion

### 7. Automated Cleanup via PR
- **Decision:** Create cleanup PR instead of manual instructions
- **Rationale:** Reduces manual steps, provides clear change tracking, ensures review
- **Benefit:** Professional workflow, clear audit trail, reduced friction

---

## Potential Issues & Considerations

### Required Status Checks May Not Exist Yet
- **Issue:** The 5 status checks require PR workflow to have run at least once
- **Impact:** PRs may be unmergeable until after first successful PR workflow run
- **Workaround:** Admin bypass allows merging despite missing checks
- **Solution:** Push an initial commit to trigger PR workflow before creating feature branches

### Zero Required Approvals Trade-off
- **For single developers:**
  - ✅ Benefit: No friction, can merge own PRs
  - ❌ Risk: No peer review enforcement
- **For teams:**
  - ⚠️ Action Required: Update `ruleset-config.json` to require 1+ approvals

### Manual Cleanup vs. Automated PR
- **Previous Approach:** Manual deletion instructions
- **Current Approach:** Automated cleanup PR creation
- **Trade-off:** Adds complexity but improves UX
- **Rationale:** Professional repositories benefit from change tracking and review

### Timestamp-Based Branch Names
- **Pattern:** `cleanup/remove-ruleset-setup-{unix-timestamp}`
- **Pro:** Guaranteed uniqueness, allows multiple cleanup attempts
- **Con:** Less human-readable than fixed names
- **Alternative:** Could use fixed name, but risks conflicts if workflow re-runs

---

## Recommendations

### For Solo Projects
- ✅ Use the default configuration (0 required approvals)
- ✅ Merge the cleanup PR after reviewing changes
- ✅ Rely on CI/CD checks for quality enforcement
- ⚠️ Consider enabling code owner review for important projects

### For Team Projects
**Before Running Workflow:**
1. Edit `.github/ruleset-config.json`
2. Set `required_approving_review_count` to 1 or higher
3. Set `require_code_owner_review` to `true`
4. Update `.github/CODEOWNERS` with team members
5. Manually trigger the workflow from the Actions tab

**After Setup:**
- Review and merge the cleanup PR as a team
- Verify all required status checks are passing
- Test PR workflow with a sample change

### For Simpler Projects
If the comprehensive protection is too restrictive:
1. Delete `.github/workflows/setup-branch-ruleset.yml` without running it
2. Configure branch protection manually with fewer checks
3. Or modify `ruleset-config.json` to remove specific rules before running the workflow

---

## Additional Resources

- **GitHub Rulesets Documentation:** https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets
- **GitHub REST API - Rulesets:** https://docs.github.com/en/rest/repos/rules
- **Branch Protection Best Practices:** https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-protected-branches/about-protected-branches

---

**Last Updated:** 2026-02-09
