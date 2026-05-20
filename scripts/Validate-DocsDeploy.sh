#!/usr/bin/env bash
# Validate-DocsDeploy.sh
#
# Validates the gh-pages branch contents after a DocFX deployment.
# Checks that the root contains index.html and versions.json, that
# versions.json is correctly structured, that every referenced version
# folder exists with an index.html, and that no known stale DocFX root
# artifacts remain.
#
# Usage:
#   bash scripts/Validate-DocsDeploy.sh
#
# Requirements: git, python3

set -euo pipefail

PASS=0
FAIL=0

check_pass() { echo "  ✅ $1"; PASS=$((PASS + 1)); }
check_fail() { echo "  ❌ $1"; FAIL=$((FAIL + 1)); }
check_warn() { echo "  ⚠️  $1"; }

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║        DocFX Deployment Validation                   ║"
echo "╚══════════════════════════════════════════════════════╝"
echo ""

# ------------------------------------------------------------------
# 1. Verify the gh-pages branch exists on the remote
# ------------------------------------------------------------------
echo "1. Checking gh-pages branch..."
if ! ls_remote_output=$(git ls-remote --heads origin gh-pages 2>&1); then
  check_fail "Could not query 'origin' for the gh-pages branch — \`git ls-remote\` exited non-zero"
  echo "    $ls_remote_output"
  echo ""
  echo "Total: $PASS passed, $FAIL failed"
  exit 1
fi
if ! echo "$ls_remote_output" | grep -q gh-pages; then
  check_fail "gh-pages branch does not exist on remote"
  echo ""
  echo "Total: $PASS passed, $FAIL failed"
  exit 1
fi
check_pass "gh-pages branch exists on remote"

# ------------------------------------------------------------------
# 2. Set up a temporary worktree to inspect the branch contents
# ------------------------------------------------------------------
# Use an explicit template so this works on BSD/macOS mktemp (which rejects
# `mktemp -d` with no template), not only GNU coreutils.
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gh-pages-validate.XXXXXX")
cleanup() {
  git worktree remove "$WORK_DIR" --force 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

# Always fetch the latest gh-pages from origin so we validate what's actually
# deployed, not a stale local copy. Use a detached worktree pointing at
# `origin/gh-pages` directly so we don't depend on (and don't update) any
# local `gh-pages` branch the caller might have around.
if ! git fetch origin gh-pages; then
  check_fail "Failed to fetch origin gh-pages"
  exit 1
fi
git worktree add --detach "$WORK_DIR" origin/gh-pages

echo ""
echo "2. Checking required root files..."

if [ -f "$WORK_DIR/index.html" ]; then
  check_pass "index.html exists at root"
else
  check_fail "index.html is MISSING from root"
fi

if [ -f "$WORK_DIR/versions.json" ]; then
  check_pass "versions.json exists at root"
else
  check_fail "versions.json is MISSING from root (version picker will not work)"
fi

if [ -f "$WORK_DIR/.nojekyll" ]; then
  check_pass ".nojekyll exists (Jekyll processing disabled)"
else
  # The canonical DocFX deploy workflow always creates .nojekyll; missing means
  # the deploy was botched, not a soft warning.
  check_fail ".nojekyll is MISSING from root (GitHub Pages will apply Jekyll processing)"
fi

# ------------------------------------------------------------------
# 3. Validate versions.json structure
# ------------------------------------------------------------------
echo ""
echo "3. Validating versions.json..."

STEP3_OK=0
if [ -f "$WORK_DIR/versions.json" ]; then
  if python3 - "$WORK_DIR/versions.json" <<'PYEOF'
import json, sys

path = sys.argv[1]
try:
    with open(path) as f:
        data = json.load(f)
except json.JSONDecodeError as e:
    print(f"  ❌ versions.json is not valid JSON: {e}")
    sys.exit(1)

if not isinstance(data, list):
    print("  ❌ versions.json must be a JSON array")
    sys.exit(1)

for i, entry in enumerate(data):
    if not isinstance(entry, dict):
        print(f"  ❌ Entry [{i}] is not a JSON object: {entry!r}")
        sys.exit(1)
    version = entry.get("version")
    url = entry.get("url")
    if not isinstance(version, str) or not version:
        print(f"  ❌ Entry [{i}] has missing or non-string 'version': {entry!r}")
        sys.exit(1)
    if not isinstance(url, str) or not url:
        print(f"  ❌ Entry [{i}] has missing or non-string 'url': {entry!r}")
        sys.exit(1)

print(f"  ✅ versions.json is valid ({len(data)} version(s))")
for v in data:
    print(f"       {v['version']:20s}  ->  {v['url']}")
PYEOF
  then
    PASS=$((PASS + 1))
    STEP3_OK=1
  else
    FAIL=$((FAIL + 1))
  fi
fi

# ------------------------------------------------------------------
# 4. Verify every version entry has a matching folder with index.html
# ------------------------------------------------------------------
echo ""
echo "4. Checking version folders match versions.json..."

# Derive the repository name from the origin remote URL so we can strip the
# project-Pages-site prefix (e.g., '/MyRepo/versions/v1.0.0/') from URLs in
# versions.json before mapping them to filesystem paths under gh-pages.
# On a user/org root Pages site there is no prefix; for project Pages sites
# the prefix is '/<repo>/'. Either way, after stripping the prefix the URL
# should map directly to a folder on gh-pages.
#
# Use shell parameter expansion rather than sed regex — BSD/macOS sed
# doesn't support the lazy quantifier '+?' and ERE flag spellings differ
# across implementations. Parameter expansion is POSIX and portable.
REPO_NAME=""
REPO_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -n "$REPO_URL" ]; then
  REPO_URL=${REPO_URL%.git}     # strip optional trailing .git
  REPO_NAME=${REPO_URL##*/}     # take everything after the last '/'
fi

if [ "$STEP3_OK" -ne 1 ]; then
  echo "  ⏭️  Skipped — versions.json failed validation in step 3"
elif [ -f "$WORK_DIR/versions.json" ]; then
  FOLDER_CHECK_RESULT=0
  python3 - "$WORK_DIR" "$REPO_NAME" <<'PYEOF' || FOLDER_CHECK_RESULT=1
import json, os, sys

work_dir = sys.argv[1]
repo_name = sys.argv[2] if len(sys.argv) > 2 else ""

# Sentinel returned when a URL cannot be mapped to a safe folder name.
UNSAFE = object()

def url_to_folder(url, repo_name):
    """Map a versions.json URL to a folder path relative to the gh-pages root.

    Returns None for root-level aliases (no separate folder), UNSAFE for
    URLs that would escape the gh-pages root, or a relative folder string."""
    if not url or url == "/":
        return None  # Root-level alias — no separate folder to check
    # Strip the project-Pages prefix '/<repo>/' if present.
    if repo_name and url.startswith(f"/{repo_name}/"):
        url = url[len(f"/{repo_name}/"):]
    folder = url.strip("/")
    if not folder:
        return None
    # Reject anything that could escape the gh-pages root via parent-dir
    # traversal, backslash injection, or absolute paths. This is defense
    # against a malformed (or hostile) versions.json on the deployed site.
    parts = folder.split("/")
    if any(p in ("", "..", ".") or "\\" in p for p in parts):
        return UNSAFE
    return folder

with open(os.path.join(work_dir, "versions.json")) as f:
    versions = json.load(f)

missing = []
for v in versions:
    ver = v["version"]
    url = v["url"]
    folder_name = url_to_folder(url, repo_name)
    if folder_name is None:
        # Entry points at the site root (typically 'latest' on a user/org Pages
        # site). The root index.html is already validated in step 2.
        continue
    if folder_name is UNSAFE:
        missing.append(f"{ver}  (url {url!r} would escape gh-pages root — rejected)")
        continue
    folder = os.path.join(work_dir, folder_name)
    # Belt-and-suspenders: verify the resolved real path is still under
    # work_dir (catches symlink shenanigans or anything the segment check missed).
    real_folder = os.path.realpath(folder)
    real_root = os.path.realpath(work_dir)
    if os.path.commonpath([real_folder, real_root]) != real_root:
        missing.append(f"{ver}  (resolved path '{real_folder}' is outside gh-pages root — rejected)")
        continue
    if not os.path.isdir(folder):
        missing.append(f"{ver}  (folder '{folder_name}/' not found)")
    elif not os.path.isfile(os.path.join(folder, "index.html")):
        missing.append(f"{ver}  (index.html missing in '{folder_name}/')")

if missing:
    for m in missing:
        print(f"  ❌ {m}")
    sys.exit(1)
else:
    print(f"  ✅ All versioned folders exist and contain index.html")
PYEOF

  if [ "$FOLDER_CHECK_RESULT" -eq 0 ]; then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
fi

# ------------------------------------------------------------------
# 5. Check for known stale DocFX root artifacts
# ------------------------------------------------------------------
echo ""
echo "5. Checking for stale DocFX root artifacts..."

# The 'public/' directory is a known DocFX build artifact that should never
# appear at the gh-pages root; its presence indicates a previous deploy did
# not clean up properly.
STALE_PATTERNS=("public")
found_stale=false

for p in "${STALE_PATTERNS[@]}"; do
  if [ -e "$WORK_DIR/$p" ]; then
    check_warn "Potentially stale artifact found at root: '$p'"
    found_stale=true
  fi
done

if [ "$found_stale" = "false" ]; then
  check_pass "No known stale DocFX artifacts found at root"
fi

# ------------------------------------------------------------------
# Summary
# ------------------------------------------------------------------
echo ""
echo "────────────────────────────────────────────────────────"
echo "  Results: $PASS passed, $FAIL failed"
echo "────────────────────────────────────────────────────────"
echo ""

if [ "$FAIL" -gt 0 ]; then
  echo "❌ Validation FAILED – review the issues listed above."
  exit 1
else
  echo "✅ Validation PASSED"
  exit 0
fi
