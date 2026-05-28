// Version picker for Wolfgang.* DocFX sites.
//
// Reads versions.json from the site root and inserts a <select> dropdown
// into the header navbar so readers can switch between published doc
// versions. Falls back silently if versions.json is missing or malformed
// — the page renders normally without a picker.
//
// Designed to live in the canonical repo-template's docfx_project/public/
// directory and fan out unchanged to all downstream repos. The script
// detects the repo segment from window.location.pathname so the same
// file works on github.io and on `docfx build --serve` localhost.
//
// Tracking issue: #170 (fleet-wide).
(function () {
    'use strict';

    function init() {
        // Compute where versions.json lives.
        //  - On GitHub Pages (*.github.io): the first path segment is the
        //    repo name, e.g. /DateTime-Extensions/... → /DateTime-Extensions/versions.json
        //  - On localhost (`docfx build --serve`): just /versions.json
        //  - On custom domain (CNAME): same as localhost — versions.json is
        //    at the document root.
        var pathSegments = window.location.pathname.split('/').filter(function (s) { return s.length > 0; });
        var versionsUrl;
        if (window.location.hostname.endsWith('.github.io') && pathSegments.length > 0) {
            versionsUrl = '/' + pathSegments[0] + '/versions.json';
        } else {
            versionsUrl = '/versions.json';
        }

        // Use the browser's default caching policy: versions.json changes
        // infrequently (only on a new release deploy) so forcing a network
        // request on every page view is wasteful. The workflow emits the
        // file with normal HTTP cache headers; the browser handles
        // conditional revalidation correctly.
        fetch(versionsUrl)
            .then(function (r) { return r.ok ? r.json() : null; })
            .then(function (data) {
                if (!data || !Array.isArray(data) || data.length === 0) {
                    return; // silent — no picker to show
                }
                renderPicker(data);
            })
            .catch(function () {
                // silent — no picker, but the page is still usable
            });
    }

    function renderPicker(versions) {
        // Detect the currently-viewed version from the URL.
        var currentVersion = 'latest';
        var m = window.location.pathname.match(/\/versions\/([^\/]+)(?:\/|$)/);
        if (m) {
            currentVersion = m[1];
        }

        // Build the <select>.
        var select = document.createElement('select');
        select.className = 'wolfgang-version-picker';
        select.setAttribute('aria-label', 'Documentation version');

        // Light styling — neutral, follows theme colors.
        //
        // `color-scheme: light dark` tells the browser the element's
        // popup can render in either color scheme; the browser then
        // picks the right one based on the page's data-bs-theme / OS
        // preference. Without this, the OS-rendered popup defaults to
        // light mode and the option text ends up white-on-white in
        // DocFX modern's dark theme.
        select.style.cssText = [
            'margin-left: 0.75rem',
            'margin-right: 0.5rem',
            'padding: 0.25rem 0.5rem',
            'background: transparent',
            'color: inherit',
            'color-scheme: light dark',
            'border: 1px solid currentColor',
            'border-radius: 4px',
            'font: inherit',
            'cursor: pointer',
            'opacity: 0.85'
        ].join('; ');

        var optionCount = 0;
        versions.forEach(function (v) {
            if (!v || !v.version || !v.url) return;
            // Skip the "latest" alias — the highest-numbered v* entry
            // already represents the latest release; surfacing both is
            // redundant in the picker. versions.json keeps the "latest"
            // entry so other consumers (links, scripts) can still
            // resolve it.
            if (v.version === 'latest') return;
            var opt = document.createElement('option');
            opt.value = v.url;
            opt.textContent = v.version;
            if (v.version === currentVersion) {
                opt.selected = true;
            }
            // Explicit option styling so the OS-rendered popup is
            // readable in both themes. Bootstrap variables (used by
            // DocFX's modern template) flip automatically with
            // data-bs-theme; the fallback values cover non-Bootstrap
            // hosts.
            opt.style.backgroundColor = 'var(--bs-body-bg, Canvas)';
            opt.style.color = 'var(--bs-body-color, CanvasText)';
            select.appendChild(opt);
            optionCount++;
        });

        // No selectable versions (e.g. versions.json contained only the
        // "latest" alias, or all entries were malformed) — don't insert
        // an empty dropdown.
        if (optionCount === 0) return;

        select.addEventListener('change', function (e) {
            var target = e.target.value;
            if (!target) return;
            // versions.json's `url` fields include the gh-pages repo prefix
            // (e.g. /DateTime-Extensions/versions/v1.2.0/) because that's
            // the correct absolute path on github.io. On localhost or on a
            // CNAME-served custom domain, that prefix isn't a directory
            // and the navigation 404s. Strip the first path segment when
            // we're not on github.io so the URL becomes relative to the
            // actual document root.
            if (!window.location.hostname.endsWith('.github.io') && target.charAt(0) === '/') {
                target = target.replace(/^\/[^\/]+\//, '/');
            }
            window.location.href = target;
        });

        // Insert into the DocFX modern-template navbar.
        // Anchors are pairs of [selector, mode]:
        //   - "before" inserts the picker as a sibling immediately before
        //     the matched element (preferred for the theme toggle / nav
        //     groups / search box — keeps the picker inline with them).
        //   - "append" inserts the picker as the LAST child of the matched
        //     element (used for the <header> fallback so the picker lands
        //     INSIDE the header, not as a sibling under <html>).
        // First match wins.
        var anchors = [
            ['header #mode', 'before'],
            ['header .navbar-nav', 'before'],
            ['header form[role="search"]', 'before'],
            ['header nav', 'append'],
            ['header', 'append']
        ];
        var inserted = false;
        for (var i = 0; i < anchors.length; i++) {
            var sel = anchors[i][0];
            var mode = anchors[i][1];
            var anchor = document.querySelector(sel);
            if (!anchor) continue;
            if (mode === 'before' && anchor.parentNode) {
                anchor.parentNode.insertBefore(select, anchor);
            } else {
                anchor.appendChild(select);
            }
            inserted = true;
            break;
        }
        if (!inserted) {
            // Last-resort fallback — pin to top-right.
            select.style.position = 'fixed';
            select.style.top = '0.5rem';
            select.style.right = '1rem';
            select.style.zIndex = '1000';
            document.body.appendChild(select);
        }
    }

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
})();
