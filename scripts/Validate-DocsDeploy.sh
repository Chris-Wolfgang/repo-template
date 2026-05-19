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
if ! git ls-remote --heads origin gh-pages | grep -q gh-pages; then
  check_fail "gh-pages branch does not exist on remote"
  echo ""
  echo "Total: $PASS passed, $FAIL failed"
  exit 1
fi
check_pass "gh-pages branch exists on remote"

# ------------------------------------------------------------------
# 2. Set up a temporary worktree to inspect the branch contents
# ------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
cleanup() {
  git worktree remove "$WORK_DIR" --force 2>/dev/null || true
  rm -rf "$WORK_DIR"
}
trap cleanup EXIT

git fetch origin gh-pages 2>/dev/null
git show-ref --verify --quiet refs/heads/gh-pages \
  || git branch gh-pages origin/gh-pages
git worktree add "$WORK_DIR" gh-pages 2>/dev/null

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
  check_warn ".nojekyll not found; GitHub Pages may apply Jekyll processing to the site"
fi

# ------------------------------------------------------------------
# 3. Validate versions.json structure
# ------------------------------------------------------------------
echo ""
echo "3. Validating versions.json..."

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

for entry in data:
    if "version" not in entry or "url" not in entry:
        print(f"  ❌ Entry is missing 'version' or 'url': {entry}")
        sys.exit(1)

print(f"  ✅ versions.json is valid ({len(data)} version(s))")
for v in data:
    print(f"       {v['version']:20s}  ->  {v['url']}")
PYEOF
  then
    PASS=$((PASS + 1))
  else
    FAIL=$((FAIL + 1))
  fi
fi

# ------------------------------------------------------------------
# 4. Verify every version entry has a matching folder with index.html
# ------------------------------------------------------------------
echo ""
echo "4. Checking version folders match versions.json..."

if [ -f "$WORK_DIR/versions.json" ]; then
  FOLDER_CHECK_RESULT=0
  python3 - "$WORK_DIR" <<'PYEOF' || FOLDER_CHECK_RESULT=1
import json, os, sys

work_dir = sys.argv[1]
with open(os.path.join(work_dir, "versions.json")) as f:
    versions = json.load(f)

missing = []
for v in versions:
    ver = v["version"]
    url = v["url"]
    # 'latest' with url '/' resolves to the root, not a subfolder – skip here.
    # If 'latest' points to a subfolder (e.g. '/latest/'), validate that folder.
    if ver == "latest" and url == "/":
        continue
    folder_name = ver if url == f"/{ver}/" else url.strip("/")
    folder = os.path.join(work_dir, folder_name)
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
# 5. Verify the 'latest/' alias folder exists
# ------------------------------------------------------------------
echo ""
echo "5. Checking latest/ alias folder..."

if [ -d "$WORK_DIR/latest" ]; then
  if [ -f "$WORK_DIR/latest/index.html" ]; then
    check_pass "latest/ folder exists and contains index.html"
  else
    check_warn "latest/ folder exists but index.html is missing"
  fi
else
  check_warn "latest/ alias folder not found (may not have been deployed yet)"
fi

# ------------------------------------------------------------------
# 6. Check for known stale DocFX root artifacts
# ------------------------------------------------------------------
echo ""
echo "6. Checking for stale DocFX root artifacts..."

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
