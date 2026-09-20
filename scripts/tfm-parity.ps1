#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Warns when a src/ project targets a framework no test project exercises.

.DESCRIPTION
    Guard 3 of the test-matrix regression guards. Walks the ProjectReference
    graph from every test project the way the build does: for each test TFM,
    the referenced src project contributes the single asset NuGet/MSBuild would
    select for that consumer (the nearest compatible framework - see the table
    below), and that selected TFM is what carries on to the src project's own
    references. A src TFM that is never the selected asset for any test TFM is
    reported - it is built and shipped but never loaded by a test.

    Asset selection follows NuGet's nearest-framework rule:
      - exact match first;
      - else the highest asset of the consumer's own family not newer than the
        consumer: net48 loads net472/net462, net9.0 loads net8.0/net6.0,
        netcoreapp3.1 loads netcoreapp3.0, net8.0-windows loads net8.0-windows
        then net8.0 (a platform asset is never loaded by a neutral consumer);
      - else, for net5.0+ consumers, the highest netcoreapp asset;
      - else the highest netstandard the consumer supports: 2.1 for
        netcoreapp3.0+ / net5.0+, 2.0 for net461+ / netcoreapp2.x, 1.x by the
        .NET Standard support table for older Frameworks.
    Selection matrix (consumer -> chosen asset from net462;net472;netstandard2.0;netstandard2.1;net6.0;net8.0):
      net462 -> net462   net48 -> net472   netstandard2.0 -> netstandard2.0
      netcoreapp3.1 -> netstandard2.1      net6.0 -> net6.0   net9.0 -> net8.0
      net8.0-windows -> net8.0             net10.0-android -> net8.0

    Evaluation goes through `dotnet msbuild -getProperty` / `-getItem` with
    Configuration=Release and, for references, the consumer's TargetFramework,
    so inherited, conditional and per-TFM values are all seen. Test roots are
    the *.csproj / *.vbproj / *.fsproj under tests/ whose IsTestProject
    evaluates to true; other projects under tests/ (AOT smoke executables,
    fixtures, integration harnesses) are consumers the walk passes through,
    so a src reference at the end of such a chain still counts, but they do
    not by themselves mark a src TFM as tested.

    Emits GitHub `::warning` annotations (one per src project) and exits 0 on
    findings - a platform TFM may legitimately have no test story yet; the
    point is that the gap is visible, not silent. Exits 1 only when the
    evaluation itself fails. Run from the repository root; pr.yaml runs it on
    the Windows stage and build-pr.ps1 mirrors it locally.

.PARAMETER SelfTest
    Run the asset-selection matrix from the description against Select-Asset and
    exit 0/1 without touching any project. Run it after editing Select-Asset.

.EXAMPLE
    pwsh ./scripts/tfm-parity.ps1

.EXAMPLE
    pwsh ./scripts/tfm-parity.ps1 -SelfTest
#>
[CmdletBinding()]
param([switch]$SelfTest)

$ErrorActionPreference = 'Stop'
$projectFilter = @('*.csproj', '*.vbproj', '*.fsproj')

function Invoke-MsBuildEval {
    param([string]$Project, [string[]]$Arguments)
    $out = & dotnet msbuild $Project -noLogo -p:Configuration=Release @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "dotnet msbuild evaluation failed for $Project ($($Arguments -join ' ')): $($out -join ' ')"
    }
    return $out
}

function Get-Tfms([string]$Project) {
    $raw = (Invoke-MsBuildEval $Project @('-getProperty:TargetFrameworks') |
        Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
    if (-not $raw) {
        $raw = (Invoke-MsBuildEval $Project @('-getProperty:TargetFramework') |
            Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
    }
    $raw = ("$raw" -replace '^TargetFrameworks?[=:]\s*', '') -replace '\s', ''
    return @($raw -split ';' | Where-Object { $_ })
}

# ProjectReference items as the project sees them when built for $Tfm - a
# reference conditioned on $(TargetFramework) only shows up for that TFM.
function Get-ReferencedProjects([string]$Project, [string]$Tfm) {
    $json = (Invoke-MsBuildEval $Project @('-getItem:ProjectReference', "-p:TargetFramework=$Tfm") | Out-String)
    if (-not $json.Trim()) { return @() }
    $dir = Split-Path -Parent (Resolve-Path $Project)
    $items = (ConvertFrom-Json $json).Items.ProjectReference
    return @($items | ForEach-Object { [System.IO.Path]::GetFullPath((Join-Path $dir $_.Identity)) })
}

# Parses a TFM into family / version / platform. Families: netframework
# (net462, net48, net481), netcoreapp (netcoreapp2.1, 3.1), netstandard,
# net5plus (net6.0, net8.0-windows, net10.0-android35.0). Unknown monikers get
# family 'other' and only ever match themselves exactly.
function ConvertTo-FrameworkInfo([string]$Tfm) {
    $t = $Tfm.Trim().ToLowerInvariant()
    if ($t -match '^net(\d)(\d)(\d)?$') {
        $v = if ($Matches[3]) { "$($Matches[1]).$($Matches[2]).$($Matches[3])" } else { "$($Matches[1]).$($Matches[2])" }
        return @{ Family = 'netframework'; Version = [version]$v; Platform = '' }
    }
    if ($t -match '^netcoreapp(\d+\.\d+)$')  { return @{ Family = 'netcoreapp';  Version = [version]$Matches[1]; Platform = '' } }
    if ($t -match '^netstandard(\d+\.\d+)$') { return @{ Family = 'netstandard'; Version = [version]$Matches[1]; Platform = '' } }
    if ($t -match '^net(\d+\.\d+)(?:-([a-z]+)[\d.]*)?$') {
        return @{ Family = 'net5plus'; Version = [version]$Matches[1]; Platform = $(if ($Matches[2]) { $Matches[2] } else { '' }) }
    }
    return @{ Family = 'other'; Version = [version]'0.0'; Platform = '' }
}

# The newest netstandard a consumer can reference (NuGet's .NET Standard
# support table). $null when the consumer supports none.
function Get-MaxNetStandard($Consumer) {
    switch ($Consumer.Family) {
        'net5plus'    { return [version]'2.1' }
        'netstandard' { return $Consumer.Version }
        'netcoreapp'  {
            if ($Consumer.Version -ge [version]'3.0') { return [version]'2.1' }
            if ($Consumer.Version -ge [version]'2.0') { return [version]'2.0' }
            return [version]'1.6'
        }
        'netframework' {
            $v = $Consumer.Version
            if ($v -ge [version]'4.6.1') { return [version]'2.0' }
            if ($v -ge [version]'4.6')   { return [version]'1.3' }
            if ($v -ge [version]'4.5.1') { return [version]'1.2' }
            if ($v -ge [version]'4.5')   { return [version]'1.1' }
            return $null
        }
    }
    return $null
}

# Which asset of a multi-targeted project a consumer built for $ConsumerTfm
# loads, following NuGet's nearest-framework rule (see the header). Returns
# $null when nothing is compatible.
function Select-Asset([string]$ConsumerTfm, [string[]]$CandidateTfms) {
    if ($CandidateTfms -contains $ConsumerTfm) { return $ConsumerTfm }
    $consumer = ConvertTo-FrameworkInfo $ConsumerTfm
    if ($consumer.Family -eq 'other') { return $null }

    # Rank 0: same family, version <= consumer, platform neutral or the consumer's
    # own. Rank 1: netcoreapp assets for a net5.0+ consumer. Rank 2: netstandard
    # the consumer supports. Within a rank the highest version wins; at equal
    # version a platform-specific asset beats the neutral one.
    $maxNs = Get-MaxNetStandard $consumer
    $ranked = foreach ($candidateTfm in $CandidateTfms) {
        $c = ConvertTo-FrameworkInfo $candidateTfm
        $rank = $null
        if ($c.Family -eq $consumer.Family -and $c.Version -le $consumer.Version -and
            ($c.Platform -eq '' -or $c.Platform -eq $consumer.Platform)) { $rank = 0 }
        elseif ($consumer.Family -eq 'net5plus' -and $c.Family -eq 'netcoreapp') { $rank = 1 }
        elseif ($c.Family -eq 'netstandard' -and $consumer.Family -ne 'netstandard' -and $maxNs -and $c.Version -le $maxNs) { $rank = 2 }
        if ($null -ne $rank) {
            [pscustomobject]@{ Tfm = $candidateTfm; Rank = $rank; Version = $c.Version; PlatformMatch = [int]($c.Platform -ne '') }
        }
    }
    $best = @($ranked | Sort-Object Rank, @{ Expression = 'Version'; Descending = $true }, @{ Expression = 'PlatformMatch'; Descending = $true }) | Select-Object -First 1
    if ($best) { return $best.Tfm }
    return $null
}

# -SelfTest: run the selection matrix from the header and exit.
if ($SelfTest) {
    $candidates = @('net462', 'net472', 'netstandard2.0', 'netstandard2.1', 'net6.0', 'net8.0')
    $expected = [ordered]@{
        'net462' = 'net462'; 'net48' = 'net472'; 'netstandard2.0' = 'netstandard2.0'
        'netcoreapp3.1' = 'netstandard2.1'; 'net6.0' = 'net6.0'; 'net9.0' = 'net8.0'
        'net8.0-windows' = 'net8.0'; 'net10.0-android' = 'net8.0'; 'net45' = $null; 'netcoreapp2.1' = 'netstandard2.0'
    }
    $extra = [ordered]@{
        # a platform asset only for a platform consumer; a neutral consumer skips it
        'net8.0-windows|net8.0-windows;net8.0' = 'net8.0-windows'
        'net8.0|net8.0-windows;net6.0'         = 'net6.0'
        'net481|net48;net462'                  = 'net48'
        'netstandard2.1|netstandard2.0'        = 'netstandard2.0'
        'net462|netstandard2.1;net6.0'         = $null
    }
    $failures = 0
    foreach ($k in $expected.Keys) {
        $got = Select-Asset $k $candidates
        $ok = ($got -eq $expected[$k]); if (-not $ok) { $failures++ }
        Write-Host ("{0} {1,-16} -> {2}" -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $k, $(if ($got) { $got } else { '(none)' }))
    }
    foreach ($k in $extra.Keys) {
        $consumerTfm, $cands = $k -split '\|'
        $got = Select-Asset $consumerTfm ($cands -split ';')
        $ok = ($got -eq $extra[$k]); if (-not $ok) { $failures++ }
        Write-Host ("{0} {1,-16} from [{2}] -> {3}" -f $(if ($ok) { 'OK  ' } else { 'FAIL' }), $consumerTfm, $cands, $(if ($got) { $got } else { '(none)' }))
    }
    if ($failures) { Write-Host "$failures self-test failure(s)."; exit 1 }
    Write-Host 'Self-test passed.'; exit 0
}

$srcProjects = @(Get-ChildItem -Path src -Recurse -File -Include $projectFilter -ErrorAction SilentlyContinue)
$testsDirProjects = @(Get-ChildItem -Path tests -Recurse -File -Include $projectFilter -ErrorAction SilentlyContinue)
if ($srcProjects.Count -eq 0 -or $testsDirProjects.Count -eq 0) {
    Write-Host "No src/ or tests/ projects - skipping TFM parity check."
    exit 0
}

# Only projects that really run tests are roots; the rest of tests/ (AOT smoke
# executables, fixtures) are ordinary consumers the walk passes through.
# IsTestProject is set by Microsoft.NET.Test.Sdk's props, which only exist after
# a restore (obj/*.nuget.g.props), so an unrestored checkout is also recognised
# by the PackageReference itself - evaluated per TFM, because the reference is
# often conditioned on the target framework.
function Test-IsTestProject([string]$Project) {
    $evalIsTest = {
        param([string[]]$ExtraArgs)
        $raw = (Invoke-MsBuildEval $Project (@('-getProperty:IsTestProject') + $ExtraArgs) |
            Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
        return ("$raw" -replace '^IsTestProject[=:]\s*', '').Trim() -ieq 'true'
    }
    if (& $evalIsTest @()) { return $true }
    foreach ($tfm in (Get-Tfms $Project)) {
        if (& $evalIsTest @("-p:TargetFramework=$tfm")) { return $true }
        $json = (Invoke-MsBuildEval $Project @('-getItem:PackageReference', "-p:TargetFramework=$tfm") | Out-String)
        if ($json.Trim() -and ((ConvertFrom-Json $json).Items.PackageReference | Where-Object { $_.Identity -ieq 'Microsoft.NET.Test.Sdk' })) { return $true }
    }
    return $false
}
$testProjects = @($testsDirProjects | Where-Object { Test-IsTestProject $_.FullName })
foreach ($p in $testsDirProjects | Where-Object { $_ -notin $testProjects }) {
    $rel = [System.IO.Path]::GetRelativePath((Get-Location).Path, $p.FullName) -replace '\\', '/'
    Write-Host "not a test root (IsTestProject != true): $rel"
}
if ($testProjects.Count -eq 0) {
    Write-Host "::warning::No project under tests/ has IsTestProject=true - nothing exercises src/."
    exit 0
}

$srcSet = [System.Collections.Generic.HashSet[string]]::new([string[]]$srcProjects.FullName, [System.StringComparer]::OrdinalIgnoreCase)
$srcTfms = @{}
foreach ($src in $srcProjects) { $srcTfms[$src.FullName] = Get-Tfms $src.FullName }
# TFMs of any project the walk reaches (src or pass-through), evaluated once.
function Get-TfmsCached([string]$Project) {
    if (-not $srcTfms.ContainsKey($Project)) { $srcTfms[$Project] = Get-Tfms $Project }
    return $srcTfms[$Project]
}

# selected[src project] = the set of that project's TFMs some test actually loads.
$selected = @{}
foreach ($src in $srcProjects) { $selected[$src.FullName] = [System.Collections.Generic.HashSet[string]]::new() }
$refCache = @{}
function Get-RefsCached([string]$Project, [string]$Tfm) {
    $key = "$Project|$Tfm"
    if (-not $refCache.ContainsKey($key)) { $refCache[$key] = Get-ReferencedProjects $Project $Tfm }
    return $refCache[$key]
}

foreach ($test in $testProjects) {
    foreach ($testTfm in (Get-Tfms $test.FullName)) {
        # Breadth-first over (project, consumer TFM); each src project contributes
        # the one asset the consumer selects, and that asset's TFM is the consumer
        # TFM for the project's own references.
        $queue = [System.Collections.Generic.Queue[object]]::new()
        $seen = [System.Collections.Generic.HashSet[string]]::new()
        foreach ($ref in (Get-RefsCached $test.FullName $testTfm)) { $queue.Enqueue(@($ref, $testTfm)) }
        while ($queue.Count -gt 0) {
            $project, $consumerTfm = $queue.Dequeue()
            if (-not (Test-Path -LiteralPath $project)) { continue }
            # A non-src project (a fixture or smoke exe under tests/) is walked
            # through with the asset it would load, but only src assets count.
            $asset = Select-Asset $consumerTfm (Get-TfmsCached $project)
            if (-not $asset) { continue }
            if (-not $seen.Add("$project|$asset")) { continue }
            if ($srcSet.Contains($project)) { [void]$selected[$project].Add($asset) }
            foreach ($next in (Get-RefsCached $project $asset)) { $queue.Enqueue(@($next, $asset)) }
        }
    }
}

$gaps = 0
foreach ($src in $srcProjects) {
    $rel = [System.IO.Path]::GetRelativePath((Get-Location).Path, $src.FullName) -replace '\\', '/'
    $covered = @($selected[$src.FullName] | Sort-Object)
    $all = $srcTfms[$src.FullName]
    if ($covered.Count -eq 0) {
        Write-Host "::warning file=$rel::No test project reaches this src project - none of its TFMs ($($all -join ', ')) are tested."
        $gaps++
        continue
    }
    $uncovered = @($all | Where-Object { $covered -notcontains $_ })
    if ($uncovered.Count -gt 0) {
        Write-Host "::warning file=$rel::TFM(s) $($uncovered -join ', ') are never the asset a test loads (tests load: $($covered -join ', ')) - that build is shipped untested."
        $gaps++
    }
    else {
        Write-Host "OK  $rel [$($all -join ', ')] <- tests load [$($covered -join ', ')]"
    }
}
if ($gaps -eq 0) { Write-Host "Every src TFM is loaded by at least one test TFM." }
else { Write-Host "$gaps src project(s) with TFM gaps - see warnings above." }
exit 0
