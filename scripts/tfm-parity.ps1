#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Warns when a src/ project targets a framework no test project exercises.

.DESCRIPTION
    Guard 3 of the test-matrix regression guards. For every src/**/*.csproj,
    collects the target frameworks of every test project that reaches it (by
    ProjectReference, directly or through other src projects) and reports any
    src TFM none of them can exercise. netstandard targets have no runtime of
    their own and count as covered by any test TFM that can consume them; any
    other TFM needs an exact match, because reference resolution picks the
    nearest compatible src asset and an unmatched one is simply never loaded.

    Emits GitHub `::warning` annotations (one per src project) and always exits
    0 - a platform TFM may legitimately have no test story yet; the point is
    that the gap is visible, not silent. Run from the repository root; pr.yaml
    runs it on the Windows stage and build-pr.ps1 mirrors it locally.

.EXAMPLE
    pwsh ./scripts/tfm-parity.ps1
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-Tfms([string]$Project) {
  $raw = (dotnet msbuild $Project -noLogo -getProperty:TargetFrameworks 2>$null |
    Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
  if (-not $raw) {
    $raw = (dotnet msbuild $Project -noLogo -getProperty:TargetFramework 2>$null |
      Where-Object { $_ -and $_.Trim() } | Select-Object -Last 1)
  }
  $raw = ("$raw" -replace '^TargetFrameworks?[=:]\s*', '') -replace '\s', ''
  return @($raw -split ';' | Where-Object { $_ })
}

function Get-ReferencedProjects([string]$Project) {
  $json = (dotnet msbuild $Project -noLogo -getItem:ProjectReference 2>$null | Out-String)
  if (-not $json.Trim()) { return @() }
  $dir = Split-Path -Parent (Resolve-Path $Project)
  $items = (ConvertFrom-Json $json).Items.ProjectReference
  return @($items | ForEach-Object {
    [System.IO.Path]::GetFullPath((Join-Path $dir $_.Identity))
  })
}

# Which test TFMs can exercise a src TFM. netstandard has no runtime of its
# own, so it is covered by any test TFM that can consume it; everything else
# needs an exact match, because NuGet/ProjectReference resolution picks the
# nearest compatible src asset and a src TFM with no matching test TFM is
# simply never loaded.
function Test-Covered([string]$SrcTfm, [string[]]$TestTfms) {
  switch -Regex ($SrcTfm) {
    '^netstandard2\.0$' { return [bool]($TestTfms | Where-Object { $_ -match '^(net4(6[1-9]|[7-9]\d*)|netcoreapp[23]\.\d|net[5-9]\.0|net[1-9]\d\.0)' }) }
    '^netstandard2\.1$' { return [bool]($TestTfms | Where-Object { $_ -match '^(netcoreapp3\.\d|net[5-9]\.0|net[1-9]\d\.0)' }) }
    default             { return [bool]($TestTfms | Where-Object { $_ -eq $SrcTfm }) }
  }
}

$srcProjects = @(Get-ChildItem -Path src -Recurse -Filter *.csproj -ErrorAction SilentlyContinue)
$testProjects = @(Get-ChildItem -Path tests -Recurse -Filter *.csproj -ErrorAction SilentlyContinue)
if ($srcProjects.Count -eq 0 -or $testProjects.Count -eq 0) {
  Write-Host "No src/ or tests/ projects - skipping TFM parity check."
  exit 0
}

# Map each src project to the union of TFMs of the test projects that reach it,
# directly or through other src projects (a test that references A exercises
# the src projects A references too, via the same nearest-TFM asset selection).
$srcRefs = @{}
foreach ($src in $srcProjects) { $srcRefs[$src.FullName] = @(Get-ReferencedProjects $src.FullName | Where-Object { $srcProjects.FullName -contains $_ }) }
$coverage = @{}
foreach ($src in $srcProjects) { $coverage[$src.FullName] = [System.Collections.Generic.HashSet[string]]::new() }
foreach ($test in $testProjects) {
  $testTfms = Get-Tfms $test.FullName
  $queue = [System.Collections.Generic.Queue[string]]::new()
  $seen = [System.Collections.Generic.HashSet[string]]::new()
  foreach ($ref in (Get-ReferencedProjects $test.FullName)) { $queue.Enqueue($ref) }
  while ($queue.Count -gt 0) {
    $ref = $queue.Dequeue()
    if (-not $seen.Add($ref) -or -not $coverage.ContainsKey($ref)) { continue }
    foreach ($t in $testTfms) { [void]$coverage[$ref].Add($t) }
    foreach ($next in $srcRefs[$ref]) { $queue.Enqueue($next) }
  }
}

$gaps = 0
foreach ($src in $srcProjects) {
  $srcTfms = Get-Tfms $src.FullName
  $testTfms = @($coverage[$src.FullName])
  $rel = [System.IO.Path]::GetRelativePath((Get-Location).Path, $src.FullName) -replace '\\', '/'
  if ($testTfms.Count -eq 0) {
    Write-Host "::warning file=$rel::No test project references this src project - none of its TFMs ($($srcTfms -join ', ')) are tested."
    $gaps++
    continue
  }
  $uncovered = @($srcTfms | Where-Object { -not (Test-Covered $_ $testTfms) })
  if ($uncovered.Count -gt 0) {
    Write-Host "::warning file=$rel::TFM(s) $($uncovered -join ', ') have no matching test TFM (tests cover: $($testTfms -join ', ')) - that asset is never exercised."
    $gaps++
  } else {
    Write-Host "OK  $rel [$($srcTfms -join ', ')] <- tests [$($testTfms -join ', ')]"
  }
}
if ($gaps -eq 0) { Write-Host "All src TFMs are covered by a test project TFM." }
else { Write-Host "$gaps src project(s) with TFM gaps - see warnings above." }
