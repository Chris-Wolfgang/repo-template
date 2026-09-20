#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Generates THIRD-PARTY-NOTICES.md for every src/ project from its NuGet dependency closure.

.DESCRIPTION
    For each *.csproj under src/ (or the one given with -Project) runs `nuget-license`
    over the project's full transitive dependency closure - the same policy files and
    tool the License audit workflow uses - and renders the result as a Markdown table
    (package, version(s), license, copyright, project URL) at
    <project dir>/obj/THIRD-PARTY-NOTICES.md. Directory.Build.props packs that file
    into the package root when it exists, so release.yaml runs this script between
    restore and pack and every shipped package carries the attribution of what it
    actually depends on.

    Packages the project references with PrivateAssets="all" (analyzers, SourceLink)
    are build-time only and never distributed, so they are left out; the SourceLink
    build-task packages they pull in are left out for the same reason. Anything else
    in the closure is listed, which errs on the side of extra attribution.

    The output is deterministic (sorted, no timestamp) so two runs on the same
    restore produce the same file. nuget-license comes from .config/dotnet-tools.json;
    the script runs `dotnet tool restore` first. Projects must be restored.

    A project whose closure nuget-license rejects (a licence outside the allow-list, or a
    repository whose licence policy lives in another tool) gets a ::warning and no notices
    file rather than failing the run: the licence GATE is license-audit.yaml's job, this
    script only renders attribution, and a missing attribution file must not block a
    release. -Strict turns those warnings into a non-zero exit (what license-audit.yaml
    uses on pull requests, so the drift is visible there).

.PARAMETER Project
    One project file to generate for. Default: every *.csproj under src/.

.PARAMETER OutputPath
    Where to write the file. Default: <project dir>/obj/THIRD-PARTY-NOTICES.md. Only
    valid together with -Project.

.PARAMETER PolicyDirectory
    Directory holding allowed-licenses.json, ignored-packages.json,
    url-license-mappings.json and package-overrides.json. Default: .github/license-audit.

.PARAMETER Strict
    Exit 1 when nuget-license fails for any project (default: warn and skip that project).

.EXAMPLE
    pwsh ./scripts/third-party-notices.ps1

.EXAMPLE
    pwsh ./scripts/third-party-notices.ps1 -Project src/My.Lib/My.Lib.csproj -OutputPath ./notices.md
#>
[CmdletBinding()]
param(
    [string]$Project,
    [string]$OutputPath,
    [string]$PolicyDirectory = '.github/license-audit',
    [switch]$Strict
)

$ErrorActionPreference = 'Stop'

if ($OutputPath -and -not $Project) { throw '-OutputPath requires -Project.' }
foreach ($f in 'allowed-licenses.json', 'ignored-packages.json', 'url-license-mappings.json', 'package-overrides.json') {
    if (-not (Test-Path (Join-Path $PolicyDirectory $f))) { throw "Policy file not found: $(Join-Path $PolicyDirectory $f)" }
}

$projects = if ($Project) { @(Get-Item -LiteralPath $Project) }
            else { @(Get-ChildItem -Path src -Recurse -File -Filter *.csproj -ErrorAction SilentlyContinue) }
if ($projects.Count -eq 0) {
    Write-Host 'No src/ projects - nothing to generate.'
    exit 0
}

& dotnet tool restore | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'dotnet tool restore failed - is .config/dotnet-tools.json present?' }

function Invoke-MsBuildEval {
    param([string]$Path, [string[]]$Arguments)
    $out = & dotnet msbuild $Path -noLogo -p:Configuration=Release @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "dotnet msbuild evaluation failed for $Path ($($Arguments -join ' ')): $($out -join ' ')" }
    return $out
}

function Get-Tfms([string]$Path) {
    $raw = (Invoke-MsBuildEval $Path @('-getProperty:TargetFrameworks') | Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
    if (-not $raw) {
        $raw = (Invoke-MsBuildEval $Path @('-getProperty:TargetFramework') | Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
    }
    $raw = ("$raw" -replace '^TargetFrameworks?[=:]\s*', '') -replace '\s', ''
    return @($raw -split ';' | Where-Object { $_ })
}

# Direct references marked PrivateAssets="all" on any TFM: build-time only.
function Get-BuildOnlyPackages([string]$Path) {
    $ids = [System.Collections.Generic.HashSet[string]]::new([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($tfm in (Get-Tfms $Path)) {
        $json = (Invoke-MsBuildEval $Path @('-getItem:PackageReference', "-p:TargetFramework=$tfm") | Out-String)
        if (-not $json.Trim()) { continue }
        foreach ($item in (ConvertFrom-Json $json).Items.PackageReference) {
            $private = "$($item.PrivateAssets)".Trim()
            if ($private -ieq 'all') { [void]$ids.Add($item.Identity) }
        }
    }
    return $ids
}

function Escape-Cell([string]$Text) {
    return (("$Text" -replace '\|', '\|') -replace '\s+', ' ').Trim()
}

$failed = 0
foreach ($proj in $projects) {
    $projDir = Split-Path -Parent $proj.FullName
    $name = [System.IO.Path]::GetFileNameWithoutExtension($proj.Name)
    $target = if ($OutputPath) { $OutputPath } else { Join-Path $projDir 'obj' 'THIRD-PARTY-NOTICES.md' }
    Write-Host "== $name =="

    $buildOnly = Get-BuildOnlyPackages $proj.FullName

    $json = & dotnet nuget-license -i $proj.FullName -t `
        -a (Join-Path $PolicyDirectory 'allowed-licenses.json') `
        -ignore (Join-Path $PolicyDirectory 'ignored-packages.json') `
        -mapping (Join-Path $PolicyDirectory 'url-license-mappings.json') `
        -override (Join-Path $PolicyDirectory 'package-overrides.json') `
        -o JsonPretty 2>&1
    if ($LASTEXITCODE -ne 0) {
        $level = if ($Strict) { 'error' } else { 'warning' }
        Write-Host "::${level} file=$($proj.FullName)::nuget-license failed for $name (exit $LASTEXITCODE) - no THIRD-PARTY-NOTICES.md for this project; see the License audit workflow for the licence gate."
        Write-Host ($json -join "`n")
        $failed++
        continue
    }
    $entries = @(($json | Out-String) | ConvertFrom-Json)

    # One row per package + license; versions differ per TFM and are merged.
    $rows = @{}
    foreach ($e in $entries) {
        if ($buildOnly.Contains($e.PackageId)) { continue }
        # SourceLink's build tasks flow in through a PrivateAssets="all" reference and
        # are never distributed either.
        if ($e.PackageId -like 'Microsoft.SourceLink.*' -or $e.PackageId -eq 'Microsoft.Build.Tasks.Git') { continue }
        $key = "$($e.PackageId)|$($e.License)"
        if (-not $rows.ContainsKey($key)) {
            $rows[$key] = [ordered]@{
                Package   = $e.PackageId
                Versions  = [System.Collections.Generic.SortedSet[string]]::new()
                License   = $(if ($e.License) { $e.License } else { 'unknown' })
                Copyright = $e.Copyright
                Url       = $(if ($e.PackageProjectUrl) { $e.PackageProjectUrl } elseif ($e.LicenseUrl) { $e.LicenseUrl } else { '' })
            }
        }
        [void]$rows[$key].Versions.Add("$($e.PackageVersion)")
    }

    $lines = [System.Collections.Generic.List[string]]::new()
    $lines.Add("# Third-party notices - $name")
    $lines.Add('')
    $lines.Add('This package depends on the NuGet packages below (full transitive closure across every')
    $lines.Add('target framework), each distributed under its own license. Build-time-only packages')
    $lines.Add('(analyzers, SourceLink) are not distributed with this package and are not listed.')
    $lines.Add('Generated by scripts/third-party-notices.ps1 at release time.')
    $lines.Add('')
    if ($rows.Count -eq 0) {
        $lines.Add('This package has no third-party NuGet dependencies.')
    }
    else {
        $lines.Add('| Package | Version(s) | License | Copyright | Project |')
        $lines.Add('|---|---|---|---|---|')
        foreach ($r in ($rows.Values | Sort-Object { $_.Package }, { $_.License })) {
            $url = if ($r.Url) { "<$($r.Url)>" } else { '' }
            $lines.Add("| $(Escape-Cell $r.Package) | $(($r.Versions | ForEach-Object { Escape-Cell $_ }) -join ', ') | $(Escape-Cell $r.License) | $(Escape-Cell $r.Copyright) | $url |")
        }
    }
    $lines.Add('')

    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null
    [System.IO.File]::WriteAllText($target, ($lines -join "`n"), [System.Text.UTF8Encoding]::new($false))
    Write-Host "   $($rows.Count) package(s) -> $target"
}

if ($failed) {
    Write-Host "$failed project(s) without notices."
    if ($Strict) { exit 1 }
}
exit 0
