#!/usr/bin/env pwsh
#Requires -Version 7.0

<#
.SYNOPSIS
    Turns open GitHub security alerts into tracked issues, and closes those issues when the alert closes.
.DESCRIPTION
    Called nightly by .github/workflows/security-alerts.yml; runnable locally with a token that can read alerts.

    For every open code-scanning, secret-scanning, and Dependabot alert the script opens one issue
    (title "Alert: <tool> <rule> in <path>", label "security"). Each issue body carries a marker
    "<!-- security-alert: <kind>#<number> -->" that is used to deduplicate on later runs. When an alert
    is no longer open the matching issue is closed with a comment. Secret-scanning alerts whose push
    protection was bypassed get a second, separate issue so the bypass itself is reviewed.

    -WeeklySummary opens (or comments on) one summary issue listing alerts open longer than -StaleDays.
    -RequestAutofix asks GitHub for a Copilot Autofix on the listed code-scanning alerts (needs
    security-events: write) and records the outcome on the alert's issue.

    A 403 on any alert listing is reported as a notice and that alert kind is skipped for the run —
    nothing is closed on the strength of a listing that failed.
.PARAMETER Repository
    owner/name. Defaults to GITHUB_REPOSITORY.
.PARAMETER WeeklySummary
    Produce the "open longer than N days" summary issue.
.PARAMETER StaleDays
    Age threshold for the summary. Default 7.
.PARAMETER RequestAutofix
    Request Copilot Autofix for the code-scanning alert numbers in -AlertNumbers.
.PARAMETER AlertNumbers
    Comma-separated code-scanning alert numbers for -RequestAutofix.
.PARAMETER DryRun
    Print what would be created, closed, or commented without doing it.
#>

[CmdletBinding()]
param
(
    [string]$Repository = $env:GITHUB_REPOSITORY,
    [switch]$WeeklySummary,
    [int]$StaleDays = 7,
    [switch]$RequestAutofix,
    [string]$AlertNumbers = '',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (-not $Repository) { throw 'Repository is required (owner/name)' }

$label = 'security'
$summaryMarker = '<!-- security-alert-summary -->'



function Invoke-Api
{
    # Returns @{ ok; data; status } — never throws on HTTP errors so callers can degrade per alert kind.
    param([string]$Path, [string]$Method = 'GET', [switch]$Paginate)

    $args = @('api', '-X', $Method, '-H', 'Accept: application/vnd.github+json', '-H', 'X-GitHub-Api-Version: 2022-11-28')
    if ($Paginate) { $args += @('--paginate', '--slurp') }
    $args += $Path
    $raw = & gh @args 2>&1
    $ok = $LASTEXITCODE -eq 0
    $text = ($raw | Out-String)
    $status = if ($text -match '\(HTTP (\d{3})\)') { [int]$Matches[1] } elseif ($ok) { 200 } else { 0 }
    $data = $null
    if ($ok -and $text.Trim())
    {
        $data = $text | ConvertFrom-Json -Depth 20
        if ($Paginate) { $data = @($data | ForEach-Object { @($_) }) }   # --slurp gives one array per page; flatten
    }
    return @{ ok = $ok; status = $status; data = $data }
}



function Get-Alerts
{
    # Normalises the three alert kinds to: kind, number, tool, rule, path, severity, url, created, extra
    param([string]$Kind)

    $path = switch ($Kind)
    {
        'code-scanning'   { "repos/$Repository/code-scanning/alerts?state=open&per_page=100" }
        'secret-scanning' { "repos/$Repository/secret-scanning/alerts?state=open&per_page=100" }
        'dependabot'      { "repos/$Repository/dependabot/alerts?state=open&per_page=100" }
    }
    $r = Invoke-Api $path -Paginate
    if (-not $r.ok)
    {
        $hint = switch ($r.status)
        {
            403 { 'token lacks permission — for Dependabot alerts set a SECURITY_ALERTS_TOKEN secret (fine-grained PAT, Dependabot alerts: read)' }
            404 { 'feature not enabled or no analyses yet' }
            default { "HTTP $($r.status)" }
        }
        Write-Host "::notice::$Kind alerts skipped: $hint"
        return $null
    }
    $list = @($r.data)
    $out = @()
    foreach ($a in $list)
    {
        switch ($Kind)
        {
            'code-scanning'
            {
                $sev = if ($a.rule.PSObject.Properties['security_severity_level'] -and $a.rule.security_severity_level) { $a.rule.security_severity_level } else { $a.rule.severity }
                $out += [pscustomobject]@{
                    kind = $Kind; number = $a.number; tool = $a.tool.name; rule = $a.rule.id
                    path = $a.most_recent_instance.location.path; severity = $sev; url = $a.html_url
                    created = [datetime]$a.created_at; extra = $a.rule.description; bypass = $false
                }
            }
            'secret-scanning'
            {
                $loc = Invoke-Api "repos/$Repository/secret-scanning/alerts/$($a.number)/locations" -Paginate
                $p = 'unknown location'
                if ($loc.ok -and @($loc.data).Count -gt 0)
                {
                    $d = @($loc.data)[0].details
                    $p = if ($d.PSObject.Properties['path']) { $d.path } else { @($loc.data)[0].type }
                }
                $out += [pscustomobject]@{
                    kind = $Kind; number = $a.number; tool = 'Secret scanning'; rule = $a.secret_type_display_name
                    path = $p; severity = 'critical'; url = $a.html_url
                    created = [datetime]$a.created_at; extra = "validity: $($a.validity)"
                    bypass = [bool]$a.push_protection_bypassed
                }
            }
            'dependabot'
            {
                $out += [pscustomobject]@{
                    kind = $Kind; number = $a.number; tool = 'Dependabot'
                    rule = "$($a.security_advisory.ghsa_id) ($($a.dependency.package.name))"
                    path = $a.dependency.manifest_path; severity = $a.security_advisory.severity; url = $a.html_url
                    created = [datetime]$a.created_at; extra = $a.security_advisory.summary; bypass = $false
                }
            }
        }
    }
    return , $out
}



function Get-TrackedIssues
{
    # All issues (open and closed) carrying an alert marker, keyed by marker.
    $raw = & gh issue list -R $Repository --label $label --state all --limit 1000 --json number,title,body,state 2>&1
    if ($LASTEXITCODE -ne 0) { throw "gh issue list failed: $raw" }
    $issues = @(($raw -join "`n") | ConvertFrom-Json)
    $map = @{}
    foreach ($i in $issues)
    {
        if ($i.body -match '<!-- security-alert: ([a-z-]+#\d+(?:-bypass)?) -->') { $map[$Matches[1]] = $i }
        elseif ($i.body -match [regex]::Escape($summaryMarker)) { $map['summary'] = $i }
    }
    return $map
}



function New-AlertIssue
{
    param([pscustomobject]$Alert, [switch]$Bypass)

    $marker = "$($Alert.kind)#$($Alert.number)$(if ($Bypass) { '-bypass' })"
    $title = if ($Bypass) { "Alert: Push protection bypassed for $($Alert.rule) in $($Alert.path)" }
             else { "Alert: $($Alert.tool) $($Alert.rule) in $($Alert.path)" }
    $body = @"
<!-- security-alert: $marker -->
| | |
|---|---|
| **Kind** | $($Alert.kind) |
| **Tool** | $($Alert.tool) |
| **Rule** | $($Alert.rule) |
| **Severity** | $($Alert.severity) |
| **Path** | ``$($Alert.path)`` |
| **Alert opened** | $($Alert.created.ToString('yyyy-MM-dd')) |
| **Link** | $($Alert.url) |

$(if ($Bypass) { "**Push protection was bypassed** for this secret. Review who bypassed it and why, rotate the secret if it is real, and dismiss the alert only after that.`n`n" })$($Alert.extra)

_Opened automatically by the security-alerts workflow. It closes when the alert is closed._
"@
    if ($DryRun) { Write-Host "DRY-RUN create: $title"; return $null }
    $url = & gh issue create -R $Repository --title $title --body $body --label $label 2>&1
    if ($LASTEXITCODE -ne 0) { Write-Warning "create failed for ${title}: $url"; return $null }
    Write-Host "opened: $url  [$title]"
    return ($url | Select-String -Pattern '/issues/(\d+)' | ForEach-Object { [int]$_.Matches[0].Groups[1].Value })
}



function Close-AlertIssue
{
    param([pscustomobject]$Issue, [string]$Reason)

    if ($DryRun) { Write-Host "DRY-RUN close #$($Issue.number): $Reason"; return }
    & gh issue close $Issue.number -R $Repository --comment "Closing: $Reason" | Out-Null
    Write-Host "closed #$($Issue.number): $Reason"
}



function Confirm-Label
{
    $existing = @(& gh label list -R $Repository --limit 200 --json name --jq '.[].name')
    if ($label -notin $existing)
    {
        if ($DryRun) { Write-Host "DRY-RUN create label $label"; return }
        & gh label create $label -R $Repository --color 'd93f0b' --description 'Security-related' | Out-Null
    }
}

# ---------------------------------------------------------------------------
# Autofix mode: a separate, narrower invocation from the workflow's autofix job.
# ---------------------------------------------------------------------------
if ($RequestAutofix)
{
    $numbers = @($AlertNumbers -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\d+$' })
    if ($numbers.Count -eq 0) { Write-Host 'no code-scanning alert numbers given'; exit 0 }
    $tracked = Get-TrackedIssues
    foreach ($n in $numbers)
    {
        $existing = Invoke-Api "repos/$Repository/code-scanning/alerts/$n/autofix"
        $result = if ($existing.ok) { "Autofix already exists (status: $($existing.data.status))" }
        else
        {
            if ($DryRun) { "DRY-RUN would request autofix for alert $n" }
            else
            {
                $req = Invoke-Api "repos/$Repository/code-scanning/alerts/$n/autofix" -Method POST
                if ($req.ok) { "Copilot Autofix requested (status: $($req.data.status))" } else { "Autofix not available (HTTP $($req.status))" }
            }
        }
        Write-Host "alert ${n}: $result"
        $issue = $tracked["code-scanning#$n"]
        if ($issue -and -not $DryRun) { & gh issue comment $issue.number -R $Repository --body $result | Out-Null }
    }
    exit 0
}

# ---------------------------------------------------------------------------
# Triage mode
# ---------------------------------------------------------------------------
Confirm-Label
$tracked = Get-TrackedIssues
$openByKind = @{}
$allOpen = @()
foreach ($kind in @('code-scanning', 'secret-scanning', 'dependabot'))
{
    $alerts = Get-Alerts $kind
    if ($null -eq $alerts) { continue }          # listing failed → do not touch this kind
    $openByKind[$kind] = @($alerts)
    $allOpen += @($alerts)
    Write-Host "${kind}: $(@($alerts).Count) open alert(s)"
}

$newCodeAlerts = @()
foreach ($a in $allOpen)
{
    $marker = "$($a.kind)#$($a.number)"
    if (-not $tracked.ContainsKey($marker))
    {
        $num = New-AlertIssue $a
        if ($a.kind -eq 'code-scanning' -and $num) { $newCodeAlerts += $a.number }
    }
    elseif ($tracked[$marker].state -eq 'CLOSED')
    {
        Write-Host "alert $marker still open but issue #$($tracked[$marker].number) was closed manually — leaving it"
    }
    if ($a.bypass -and -not $tracked.ContainsKey("$marker-bypass")) { New-AlertIssue $a -Bypass | Out-Null }
}

# Close issues whose alert is gone (only for kinds we listed successfully).
foreach ($marker in @($tracked.Keys))
{
    if ($marker -eq 'summary') { continue }
    $issue = $tracked[$marker]
    if ($issue.state -ne 'OPEN') { continue }
    $kind, $rest = $marker -split '#', 2
    if (-not $openByKind.ContainsKey($kind)) { continue }
    $number = [int]($rest -replace '-bypass$', '')
    if ($openByKind[$kind] | Where-Object { $_.number -eq $number }) { continue }
    $detail = Invoke-Api "repos/$Repository/$kind/alerts/$number"
    $state = if ($detail.ok) { $detail.data.state } else { 'unknown' }
    if ($state -in @('open', 'unknown')) { continue }
    Close-AlertIssue $issue "alert $kind #$number is now '$state'"
}

if ($WeeklySummary)
{
    $cutoff = (Get-Date).ToUniversalTime().AddDays(-$StaleDays)
    $stale = @($allOpen | Where-Object { $_.created -lt $cutoff } | Sort-Object created)
    $summaryIssue = if ($tracked.ContainsKey('summary')) { $tracked['summary'] } else { $null }
    if ($stale.Count -eq 0)
    {
        if ($summaryIssue -and $summaryIssue.state -eq 'OPEN') { Close-AlertIssue $summaryIssue "no alerts open longer than $StaleDays days" }
        else { Write-Host "no alerts older than $StaleDays days" }
    }
    else
    {
        $table = ($stale | ForEach-Object { "| $($_.kind) | $($_.severity) | $($_.rule) | ``$($_.path)`` | $($_.created.ToString('yyyy-MM-dd')) | $($_.url) |" }) -join "`n"
        $text = @"
$summaryMarker
**$($stale.Count) alert(s) open longer than $StaleDays days** as of $(Get-Date -Format 'yyyy-MM-dd').

| Kind | Severity | Rule | Path | Opened | Link |
|---|---|---|---|---|---|
$table

_Updated weekly by the security-alerts workflow._
"@
        if ($summaryIssue -and $summaryIssue.state -eq 'OPEN')
        {
            if ($DryRun) { Write-Host "DRY-RUN comment on summary #$($summaryIssue.number)" }
            else { & gh issue comment $summaryIssue.number -R $Repository --body $text | Out-Null; Write-Host "updated summary #$($summaryIssue.number)" }
        }
        else
        {
            $title = "Security alerts open longer than $StaleDays days"
            if ($DryRun) { Write-Host "DRY-RUN create summary: $title" }
            else { $u = & gh issue create -R $Repository --title $title --body $text --label $label; Write-Host "opened summary: $u" }
        }
    }
}

if ($env:GITHUB_OUTPUT) { "new-code-alerts=$($newCodeAlerts -join ',')" | Add-Content $env:GITHUB_OUTPUT }
Write-Host "done: $($allOpen.Count) open alert(s), $($newCodeAlerts.Count) new code-scanning issue(s)"
