#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Runs the same checks as the Windows section of pr.yaml locally.

.DESCRIPTION
    Replicates the PR workflow's Windows stage locally so you can verify
    your changes will pass before pushing. Runs in order:
      1. Restore and build (Release)
      2. Run all tests across all target frameworks
      3. Generate coverage report and enforce threshold
      4. Run DevSkim security scan
      5. Run gitleaks secrets scan

.PARAMETER SkipTests
    Skip test execution (build only).

.PARAMETER SkipCoverage
    Skip coverage report generation and threshold enforcement.

.PARAMETER SkipSecurity
    Skip DevSkim and gitleaks scans.

.PARAMETER CoverageThreshold
    Minimum line coverage for PRODUCTION assemblies (anything under src/).
    Defaults to 90. Mirrors CODECOV_MINIMUM in pr.yaml.

.PARAMETER TestCoverageThreshold
    Minimum line coverage for TEST assemblies (anything under tests/).
    Defaults to 100 — test code that never executes has no purpose. Mirrors
    CODECOV_TEST_MINIMUM in pr.yaml.

.EXAMPLE
    pwsh ./scripts/build-pr.ps1
    pwsh ./scripts/build-pr.ps1 -SkipSecurity
    pwsh ./scripts/build-pr.ps1 -CoverageThreshold 80
#>
param(
    [switch]$SkipTests,
    [switch]$SkipCoverage,
    [switch]$SkipSecurity,
    [int]$CoverageThreshold = 90,
    [int]$TestCoverageThreshold = 100
)

$ErrorActionPreference = 'Stop'
$failed = @()

function Write-Step($message) {
    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host $message -ForegroundColor Cyan
    Write-Host "==========================================" -ForegroundColor Cyan
}

function Write-Pass($message) {
    Write-Host $message -ForegroundColor Green
}

function Write-Fail($message) {
    Write-Host $message -ForegroundColor Red
}

# ============================================================================
# STEP 1: Restore and Build
# ============================================================================
Write-Step "Step 1: Restore and Build (Release)"

dotnet restore
if ($LASTEXITCODE -ne 0) {
    Write-Fail "Restore failed"
    $failed += "Restore"
}
else {
    dotnet build --no-restore --configuration Release
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Build failed"
        $failed += "Build"
    }
    else {
        Write-Pass "Build succeeded"
    }
}

# ============================================================================
# STEP 2: Run Tests
# ============================================================================
if (-not $SkipTests -and $failed.Count -eq 0) {
    Write-Step "Step 2: Run Tests (all target frameworks)"

    # Results from an earlier run would be merged into this run's coverage report and could
    # hide or invent misses; start every run from a clean slate.
    foreach ($stale in @('TestResults', 'CoverageReport')) {
        if (Test-Path $stale) { Remove-Item $stale -Recurse -Force }
    }

    # Mirrors pr.yaml's Stage 2 TFM parity check (guard 3). Findings are
    # warnings (exit 0); a non-zero exit means the evaluation itself broke and
    # is a failure here exactly as it is in CI.
    if (Test-Path './scripts/tfm-parity.ps1') {
        & pwsh -NoProfile -File './scripts/tfm-parity.ps1'
        if ($LASTEXITCODE -ne 0) {
            Write-Fail "TFM parity guard failed to run (exit $LASTEXITCODE)"
            $failed += "TFM parity"
        }
    }

    $testProjects = @(Get-ChildItem -Path './tests' -Recurse -File -Include '*.csproj', '*.vbproj', '*.fsproj' -ErrorAction SilentlyContinue)

    if ($testProjects.Count -eq 0) {
        # If ./src has projects, fail — silent skip would diverge from CI's
        # strict gate. If neither ./src nor ./tests has projects (template-pack
        # / in-dev repos), the skip is legitimate.
        $srcHasProjects = @(Get-ChildItem -Path './src' -Recurse -File -Include '*.csproj','*.vbproj','*.fsproj' -ErrorAction SilentlyContinue).Count -gt 0
        if ($srcHasProjects) {
            Write-Fail "./tests has no test projects but ./src contains projects — refusing to silently skip the coverage gate."
            $failed += "Tests"
        }
        else {
            Write-Host "No test projects found in ./tests and no ./src projects — skipping (template-pack / in-dev shape)."
        }
    }
    else {
        foreach ($testProj in $testProjects) {
            Write-Host ""
            Write-Host "Testing: $($testProj.FullName)" -ForegroundColor White

            # Evaluate the TFMs through MSBuild exactly as pr.yaml does, so
            # values inherited from Directory.Build.props or set conditionally
            # are seen; a regex over the raw csproj misses both.
            $tfmRaw = (dotnet msbuild $testProj.FullName -noLogo -p:Configuration=Release -getProperty:TargetFrameworks 2>$null |
                Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
            if (-not $tfmRaw) {
                $tfmRaw = (dotnet msbuild $testProj.FullName -noLogo -p:Configuration=Release -getProperty:TargetFramework 2>$null |
                    Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
            }
            $tfmRaw = ("$tfmRaw" -replace '^TargetFrameworks?[=:]\s*', '') -replace '\s', ''

            if (-not $tfmRaw) {
                Write-Host "  No target frameworks found — skipping" -ForegroundColor Yellow
                continue
            }

            $frameworks = @($tfmRaw -split ';' |
                Where-Object { $_ -match '^net(5\.0|6\.0|7\.0|8\.0|9\.0|10\.0|462|47|471|472|48|481|coreapp3\.1)$' })

            if ($frameworks.Count -eq 0) {
                Write-Host "  No compatible frameworks — skipping" -ForegroundColor Yellow
                continue
            }

            # Only projects that really run tests: an AOT smoke executable or a
            # fixture under tests/ has nothing for the test adapter to execute and
            # would trip the zero-tests guard below. IsTestProject comes from
            # Microsoft.NET.Test.Sdk's props, imported per TFM after restore, so
            # check it per framework and fall back to the PackageReference itself
            # (mirrors scripts/tfm-parity.ps1).
            $isTestProject = $false
            foreach ($fw in $frameworks) {
                $isTest = (dotnet msbuild $testProj.FullName -noLogo -p:Configuration=Release "-p:TargetFramework=$fw" -getProperty:IsTestProject 2>$null |
                    Where-Object { $_ -and "$_".Trim() } | Select-Object -Last 1)
                if (("$isTest" -replace '^IsTestProject[=:]\s*', '').Trim() -ieq 'true') { $isTestProject = $true; break }
                $refs = (dotnet msbuild $testProj.FullName -noLogo -p:Configuration=Release "-p:TargetFramework=$fw" -getItem:PackageReference 2>$null | Out-String)
                if ($refs.Trim() -and ((ConvertFrom-Json $refs).Items.PackageReference | Where-Object { $_.Identity -ieq 'Microsoft.NET.Test.Sdk' })) { $isTestProject = $true; break }
            }
            if (-not $isTestProject) {
                Write-Host "  Not a test project (no IsTestProject / Microsoft.NET.Test.Sdk) — skipping dotnet test" -ForegroundColor Yellow
                continue
            }

            Write-Host "  Frameworks: $($frameworks -join ', ')"

            foreach ($fw in $frameworks) {
                Write-Host "  Testing: $fw" -ForegroundColor Yellow

                $testArgs = @(
                    $testProj.FullName,
                    '--configuration', 'Release',
                    '--framework', $fw,
                    '--logger', 'console;verbosity=normal'
                )

                if ($fw -match '^net([5-9]|[1-9][0-9]+)\.') {
                    $testArgs += '--collect:XPlat Code Coverage'
                    $testArgs += '--results-directory'
                    $testArgs += './TestResults'
                    if (Test-Path 'coverlet.runsettings') {
                        $testArgs += '--settings'
                        $testArgs += 'coverlet.runsettings'
                    }
                }

                # Mirrors pr.yaml's zero-tests-ran guard: `dotnet test` exits 0
                # when the runner finds NO tests, so check the summary too.
                $testLog = [System.IO.Path]::GetTempFileName()
                dotnet test @testArgs 2>&1 | Tee-Object -FilePath $testLog

                if ($LASTEXITCODE -ne 0) {
                    Write-Fail "  Tests failed for $fw"
                    $failed += "Tests ($fw)"
                    break
                }
                $testOutput = Get-Content $testLog -Raw
                Remove-Item $testLog -Force -ErrorAction SilentlyContinue
                # verbosity=normal prints "Total tests: N"; minimal (pr.yaml) prints "Total: N" — accept both.
                if ($testOutput -match 'No test is available' -or $testOutput -notmatch '(?i)total(?: tests)?:\s*[1-9][0-9]*') {
                    Write-Fail "  Zero tests ran for $fw — the test adapter found nothing to execute (missing/incompatible xunit.runner.visualstudio for this TFM?)"
                    $failed += "Tests (${fw}: zero ran)"
                    break
                }
            }

            if ($failed.Count -gt 0) { break }
        }

        if ($failed.Count -eq 0) {
            Write-Pass "All tests passed"
        }
    }
}

# ============================================================================
# STEP 3: Coverage Report and Threshold
# ============================================================================
if (-not $SkipTests -and -not $SkipCoverage -and $failed.Count -eq 0) {
    Write-Step "Step 3: Coverage Report (src ${CoverageThreshold}%, tests ${TestCoverageThreshold}%)"

    $coverageFiles = Get-ChildItem -Path TestResults -Recurse -Filter coverage.cobertura.xml -ErrorAction SilentlyContinue

    if (-not $coverageFiles) {
        Write-Host "No coverage files found — skipping"
    }
    else {
        # Install ReportGenerator if not present
        $rgPath = Get-Command reportgenerator -ErrorAction SilentlyContinue
        if (-not $rgPath) {
            Write-Host "Installing ReportGenerator..."
            dotnet tool update -g dotnet-reportgenerator-globaltool 2>$null
            if ($LASTEXITCODE -ne 0) { dotnet tool install -g dotnet-reportgenerator-globaltool }
            # Ensure global tools dir is on PATH for this session. The .NET
            # installer normally adds it to the user's profile, but a fresh
            # shell or a pwsh-invoked-from-script session may not have it yet.
            $globalToolsDir = if ($IsWindows -or $env:OS -eq 'Windows_NT') {
                Join-Path $env:USERPROFILE '.dotnet\tools'
            } else {
                Join-Path $HOME '.dotnet/tools'
            }
            if (Test-Path $globalToolsDir -PathType Container) {
                $sep = [IO.Path]::PathSeparator
                $pathSegments = $env:PATH -split [regex]::Escape($sep)
                if ($pathSegments -notcontains $globalToolsDir) {
                    $env:PATH = "$globalToolsDir$sep$env:PATH"
                }
            }
        }

        reportgenerator `
            -reports:"TestResults/**/coverage.cobertura.xml" `
            -targetdir:"CoverageReport" `
            -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"

        if (Test-Path "CoverageReport/Summary.txt") {
            Write-Host ""
            Get-Content "CoverageReport/Summary.txt"
            Write-Host ""

            # Assembly names produced by projects under tests/ — mirrors pr.yaml.
            # Identify test assemblies by LOCATION, never by name: shipped product
            # packages such as Wolfgang.Etl.TestKit contain "Test" and live in src/.
            $testAssemblies = @()
            if (Test-Path "tests") {
                Get-ChildItem -Path "tests" -Recurse -File -Include *.csproj,*.vbproj,*.fsproj | ForEach-Object {
                    $m = [regex]::Match((Get-Content $_.FullName -Raw), '<AssemblyName>([^<]+)</AssemblyName>')
                    $testAssemblies += $(if ($m.Success) { $m.Groups[1].Value.Trim() } else { $_.BaseName })
                }
            }

            $failedProjects = @()
            $matched = 0
            foreach ($line in (Get-Content "CoverageReport/Summary.txt")) {
                # Anchor on `^(\S+)` — NOT `^\s*(\S+)`. The leading `\s*` used to
                # let ReportGenerator's indented per-class rows match, so individual
                # classes were gated as if they were projects (the same defect
                # pr.yaml's Stage 1 had via a bare `read -r`). Only assembly rows
                # are gated; an assembly only reaches 100% when every class does.
                if ($line -match '^(\S+)\s+(\d+(?:\.\d+)?)%\s*$' -and $line -notmatch '^Summary') {
                    $module = $Matches[1]
                    $percent = [int][math]::Floor([double]$Matches[2])
                    $matched++

                    $isTest    = $testAssemblies -contains $module
                    $applies   = if ($isTest) { $TestCoverageThreshold } else { $CoverageThreshold }

                    if ($percent -lt $applies) {
                        Write-Fail "  $module — ${percent}% (below ${applies}%)"
                        $failedProjects += "$module (${percent}%, needs ${applies}%)"
                    }
                    else {
                        Write-Pass "  $module — ${percent}%"
                    }
                }
            }

            if ($matched -eq 0) {
                # Mirror pr.yaml: a parser/format drift that matches zero modules
                # must fail loudly, not silently pass the gate.
                Write-Fail "Coverage parser matched 0 modules in Summary.txt — regex or report format is out of sync. Refusing to silently pass the gate."
                $failed += "Coverage"
            }
            elseif ($failedProjects.Count -gt 0) {
                Write-Fail "Coverage gate FAILED: $($failedProjects -join ', ')"
                $failed += "Coverage"
            }
            else {
                Write-Pass "Coverage gate passed"
            }
        }
        else {
            # Diverged from pr.yaml behavior in the past — that would let a local
            # "All checks passed" silently hide ReportGenerator failures while CI
            # rejected the same situation. Fail loudly here too, so local matches CI.
            Write-Fail "Coverage report not generated (CoverageReport/Summary.txt missing) — ReportGenerator likely failed."
            $failed += "Coverage"
        }
    }
}

# ============================================================================
# STEP 4: DevSkim Security Scan
# ============================================================================
if (-not $SkipSecurity) {
    Write-Step "Step 4: DevSkim Security Scan"

    $devskim = Get-Command devskim -ErrorAction SilentlyContinue
    if (-not $devskim) {
        Write-Host "Installing DevSkim CLI..."
        dotnet tool install --global Microsoft.CST.DevSkim.CLI
    }

    devskim analyze `
        --source-code . `
        --file-format text `
        --output-file devskim-results.txt `
        --ignore-rule-ids DS176209 `
        --ignore-globs "**/api/**,**/CoverageReport/**,**/TestResults/**"

    if (Test-Path "devskim-results.txt") {
        $results = Get-Content "devskim-results.txt" -Raw
        if ($results -and $results -match '(?i)(error|critical|high)') {
            Write-Host $results
            Write-Fail "DevSkim found security issues"
            $failed += "DevSkim"
        }
        else {
            Write-Pass "No critical security issues found"
        }
        Remove-Item "devskim-results.txt" -ErrorAction SilentlyContinue
    }
    else {
        Write-Pass "No security issues found"
    }
}

# ============================================================================
# STEP 5: Gitleaks Secrets Scan
# ============================================================================
if (-not $SkipSecurity) {
    Write-Step "Step 5: Gitleaks Secrets Scan"

    $gitleaks = Get-Command gitleaks -ErrorAction SilentlyContinue
    if (-not $gitleaks) {
        Write-Host "gitleaks not found — installing..."
        # Keep in step with GITLEAKS_VERSION in .github/workflows/pr.yaml.
        $version = "8.30.1"
        if ($IsWindows -or $env:OS -match 'Windows') {
            $archive = "gitleaks_${version}_windows_x64.zip"
            $url = "https://github.com/gitleaks/gitleaks/releases/download/v${version}/$archive"
            $dest = Join-Path $env:LOCALAPPDATA "gitleaks"
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            $zip = Join-Path $env:TEMP $archive
            # -UseBasicParsing: required on Windows PowerShell 5.1, where the
            # default parser uses the IE engine and throws on stock/minimal
            # Windows installs. PowerShell 7+ accepts it as a no-op.
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $dest -Force
            Remove-Item $zip -ErrorAction SilentlyContinue
            $env:PATH = "$dest;$env:PATH"
        }
        else {
            # gitleaks ships separate darwin / linux builds, and on both we
            # also have to pick between x64 and arm64 (Apple Silicon on macOS,
            # ARM64 dev boards / cloud VMs on Linux). Without this branch the
            # POSIX path would download the wrong-OS tarball or install an
            # incompatible binary. Comparing to the strongly-typed enum value
            # (rather than the string "Arm64") avoids implicit-conversion
            # surprises across PowerShell hosts.
            $arm64 = [System.Runtime.InteropServices.Architecture]::Arm64
            $arch = if ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture -eq $arm64) { 'arm64' } else { 'x64' }
            if ($IsMacOS) {
                $archive = "gitleaks_${version}_darwin_${arch}.tar.gz"
            }
            else {
                $archive = "gitleaks_${version}_linux_${arch}.tar.gz"
            }
            $url = "https://github.com/gitleaks/gitleaks/releases/download/v${version}/$archive"
            # Install to a user-writable location instead of /usr/local/bin
            # (which would require sudo for most local dev shells). $HOME/.local/bin
            # is on PATH by default on most Linux distros and macOS; if not, prepend it.
            $localBin = Join-Path $HOME ".local/bin"
            New-Item -ItemType Directory -Force -Path $localBin | Out-Null
            # Use 'tar -f -' so extraction reads the gitleaks archive from
            # stdin. GNU tar without '-f' defaults to /dev/tape (or another
            # default depending on the TAPE env var), which can hang silently
            # in CI / fresh shells.
            curl -sSfL $url | tar -xz -f - -C $localBin gitleaks
            if (-not ($env:PATH -split [IO.Path]::PathSeparator | Where-Object { $_ -eq $localBin })) {
                $env:PATH = "$localBin$([IO.Path]::PathSeparator)$env:PATH"
            }
        }
    }

    # `gitleaks git` (8.19+) replaces the deprecated `detect --source`.
    gitleaks git --verbose --redact .
    if ($LASTEXITCODE -ne 0) {
        Write-Fail "Gitleaks found secrets"
        $failed += "Gitleaks"
    }
    else {
        Write-Pass "No secrets detected"
    }
}

# ============================================================================
# Summary
# ============================================================================
Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "SUMMARY" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan

if ($failed.Count -gt 0) {
    Write-Fail "FAILED: $($failed -join ', ')"
    exit 1
}
else {
    Write-Pass "All checks passed"
    exit 0
}
