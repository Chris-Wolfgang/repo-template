# DocFX Version Picker

The docs site shows an in-page version picker (a `<select>` dropdown in
the header) so readers on any page can jump between published doc
versions. The picker is a self-contained JavaScript snippet — DocFX's
`default`/`modern`/`modern-dark` templates don't ship one natively, so
this repo implements its own.

The same picker is in `repo-template` and fans out unchanged to every
downstream `.NET` repo in the fleet.

---

## How a reader experiences it

| URL | What happens |
|---|---|
| `/<repo>/` | Root redirect → lands on `/<repo>/versions/latest/` (Microsoft Docs-style UX) |
| `/<repo>/versions/latest/` (or any version) | Real DocFX docs render. The header shows a `<select>` between the app title and the theme toggle, populated from `versions.json` and pre-selecting whichever version the current URL is under. |
| Pick a different version in the dropdown | Browser navigates to `/<repo>/versions/<picked>/` |

The "latest" alias is filtered out of the dropdown (redundant — the
highest-numbered `v*` row already represents latest); `versions.json`
still includes it so external links / scripts can resolve it.

---

## The four moving parts

### 1. `docfx_project/public/version-picker.js`

Browser-side picker (~160 lines). On `DOMContentLoaded`:

- Detects whether the host is `*.github.io` and computes the repo
  prefix accordingly — same file works on github.io, on
  `docfx build --serve` localhost, and on CNAME-served custom domains.
- Fetches `versions.json` from the site root (default browser cache
  policy — the file changes infrequently).
- Builds a themed `<select>` (uses Bootstrap CSS variables so it
  follows DocFX modern's light/dark theme; `color-scheme: light dark`
  makes the OS-rendered popup readable in both modes).
- Inserts the picker into the DocFX header using a prioritised anchor
  list (theme toggle → navbar → search → header); the `header`
  fallback appends INTO the header, not as a sibling under `<html>`.
- Strips the gh-pages `/<repo>/` prefix from navigation URLs when
  off-github.io so localhost / CNAME navigation resolves to
  `/versions/<v>/` rather than `/<repo>/versions/<v>/`.

Falls back silently (no broken page, no empty dropdown) if
`versions.json` is missing, malformed, or contains only a `latest`
alias after filtering.

### 2. `docfx_project/docfx.json`

Two changes from a stock DocFX project:

```jsonc
"resource": [
  {
    "files": [
      "logo.svg",
      "images/**",
      "public/**",         // ← copies version-picker.js into _site/public/
      "versions.json"      // ← stub for local dev; workflow overwrites on deploy
    ]
  }
],

"globalMetadata": {
  // ...
  "_appFooter": "Made with DocFX <script>...</script>"
  //                              ^ tiny inline bootstrap that computes
  //                                the site root and lazy-loads
  //                                /<repo>/public/version-picker.js
  //                                into document.head. Inline (not
  //                                external) because _appFooter is a
  //                                plain string field, not a Liquid
  //                                template — page-relative paths
  //                                wouldn't resolve from nested pages
  //                                like /api/Foo.html.
}
```

### 3. `docfx_project/versions.json` (stub)

Committed as `[]` (empty array). The `docfx.yaml` workflow regenerates
the real `versions.json` at deploy time from the set of actual `v*`
tags that have versioned docs deployed (D6 derivation) and writes it
to the gh-pages site root. The empty stub is the fanout-safe default —
no DateTime-Extensions paths leak into other repos when this folder is
synced fleet-wide.

**Local picker testing** requires populating `versions.json` manually
with mock entries (see "Testing locally" below). The picker
gracefully falls back to "no dropdown" if the stub is empty.

### 4. `.github/version-picker-template.html`

Used by the `docfx.yaml` "Generate version-picker index.html" step.
Renders an auto-redirect page at the gh-pages root:

- `meta http-equiv="refresh"` for instant redirect
- `setTimeout` JS backup if meta-refresh is blocked
- `<noscript>` link covers the everything-else case

`{{TITLE}}` is substituted with the repo name at deploy time;
`{{VERSION_LIST}}` is intentionally omitted from the template. A missing
pattern is a true no-op for PowerShell's `-replace` (returns the original
string unchanged), so the workflow runs unchanged; nothing gets injected
into the root redirect page because the in-page dropdown is now the
canonical version-selector UI.

---

## How it gets to gh-pages

```
push to main / release tag
  └─ docfx.yaml fires
       ├─ docfx build  → _site/  (includes public/version-picker.js,
       │                          inline bootstrap in every page's
       │                          footer via _appFooter)
       ├─ Generate versions.json from v* tags → _site/versions.json
       ├─ Deploy _site/ to gh-pages /versions/<v>/ + /versions/latest/
       └─ Generate root index.html from version-picker-template.html
                  → deploy to gh-pages /
```

Result on gh-pages:

```
/                      ← redirect to /versions/latest/
/versions.json         ← available-versions list (drives the picker)
/versions/latest/      ← latest docs (with picker in header)
/versions/v1.3.0/      ← versioned docs (with picker)
/versions/v1.2.0/      ← versioned docs (with picker)
...
```

---

## Testing locally

`docfx build --serve` doesn't replicate the gh-pages layout — there's
no `/versions/<v>/` tree and no auto-generated `versions.json`. To
exercise the picker locally:

```bash
cd docfx_project

# Build src first (DocFX metadata needs the assemblies)
dotnet build ../src/<package>/<package>.csproj -c Release

# Generate API metadata + build site
docfx metadata
docfx build

# Drop a mock versions.json with the URLs the picker will navigate to.
# Use the repo's own /<repo>/versions/<v>/ scheme so the JS's
# prefix-stripping path is exercised.
cat > _site/versions.json <<'JSON'
[
  { "version": "latest", "url": "/<repo>/versions/latest/" },
  { "version": "v1.0.0", "url": "/<repo>/versions/v1.0.0/" }
]
JSON

# Optionally, copy _site/* into _site/versions/latest/ etc.
# so the navigation lands on real pages instead of 404s.

# Serve and visit http://localhost:8081/
docfx serve _site --port 8081
```

The picker fetches `versions.json` from `/versions.json` (no repo
prefix on localhost), builds the dropdown, and navigates to
`/versions/<v>/` on selection (with the `/<repo>/` prefix stripped
because we're not on github.io).

---

## Troubleshooting

| Symptom | Likely cause | Where to look |
|---|---|---|
| Dropdown missing entirely | `version-picker.js` not loaded on the page | DevTools → Network. The page should fetch `/<repo>/public/version-picker.js`. If 404, check `docfx.json` `resource.files` includes `public/**`. |
| Dropdown shows wrong selection | `currentVersion` derivation in the JS didn't find a `/versions/<v>/` segment in the URL | DevTools → Console — log `window.location.pathname` and re-derive |
| Dropdown empty | `versions.json` fetch failed or returned an array without any non-"latest" entries | DevTools → Network. The page should fetch `/<repo>/versions.json` (or `/versions.json` on localhost) and get a JSON array with `version`+`url` entries. |
| Popup text invisible (light-on-light or dark-on-dark) | `color-scheme: light dark` missing or Bootstrap CSS vars not loaded | Verify `version-picker.js` is the current version |
| Picker appears as sibling of `<header>` instead of inside it | Anchor fallback selected `header` with the wrong insertion mode | Verify the anchors table has `['header', 'append']` (not `'before'`) |
| Root `/` shows old "Select a documentation version" landing page | The `version-picker-template.html` change didn't deploy | Check the workflow run's "Generate version-picker index.html" step output |

For workflow-level issues (failed deploys, stale `versions.json`,
missing version subtrees), the `docfx.yaml` run's per-step output is
the canonical place to look. `scripts/Validate-DocsDeploy.sh` runs
at the end of every deploy and catches structural drift.

---

## Manual recovery for a broken `gh-pages`

If gh-pages ends up in a state the workflow can't repair, **do not run
a manual cleanup against the gh-pages root** — every versioned subtree
under `versions/` is unrecoverable once deleted (the source git tag
still exists, but the rendered HTML would have to be regenerated by
running `docfx.yaml` once per tag via `workflow_dispatch`).

Safe recovery: re-run `docfx.yaml` with `workflow_dispatch` for each
affected tag in turn (oldest first). The worktree-based replace
rebuilds `versions/<tag>/` cleanly without affecting the others.
