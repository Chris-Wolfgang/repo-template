# Security Policy

## Supported Versions

Security fixes are released for the **latest published version** only. If you are on an older
version, upgrade to the latest release to receive the fix. Pre-1.0 releases (0.x) follow the same
rule: the newest 0.x release is the supported one.

## Reporting a Vulnerability

If you discover a security vulnerability, please follow these steps:

1. **Do not** create a public issue on this repository.
2. Open the private report form: {{GITHUB_REPO_URL}}/security/advisories/new
   (or, from the repository's **Security** tab, click **Report a vulnerability**).
   GitHub's guide to this process: https://docs.github.com/en/code-security/security-advisories/guidance-on-reporting-and-writing-information-about-vulnerabilities/privately-reporting-a-security-vulnerability
3. Fill out the provided form with:
   - A description of the vulnerability
   - Steps to reproduce the issue
   - Potential impact
   - Suggested fix (if you have one)

## Response Timeline

This is a single-maintainer project; the commitments below are realistic for that, not aspirational.

| Stage | Target |
|-------|--------|
| Acknowledgement of the report | Within 48 hours |
| Initial assessment (confirmed / not a vulnerability / need more information) and severity | Within 7 days |
| Fix for **Critical** severity | Within 30 days |
| Fix for **High** or **Medium** severity | Within 90 days |
| Fix for **Low** severity | Next scheduled release |

If a target is going to slip, you will hear that from the maintainer in the advisory thread before
the deadline passes, not after.

## Disclosure Process

1. **Report** — you open a private advisory (above). Only you and the maintainer can see it.
2. **Triage** — the maintainer confirms the issue and assigns a severity, discussed with you in the
   advisory thread.
3. **Fix** — the fix is developed in a temporary private fork attached to the advisory, so nothing
   about the vulnerability is visible in public pull requests until the fix is released.
4. **Release** — a new version ships with the fix. The release notes say a security issue was fixed
   without giving details that would help exploit unpatched versions.
5. **Publish** — the advisory is published, which notifies dependents through Dependabot. A CVE is
   requested from GitHub for confirmed vulnerabilities; assignment is GitHub's decision, so the
   advisory may publish without one. Publication happens at release time, or after 90 days from the
   initial report if no fix is possible, whichever comes first.

Please keep the details private until the advisory is published.

## Credit

Reporters are credited in the published advisory and in the release notes, unless you ask not to be.
Tell us in the report how you would like to be named.

## Thank You

Your help is greatly appreciated!
Responsible disclosure of security vulnerabilities helps protect our entire community.
