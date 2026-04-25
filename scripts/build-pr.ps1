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
    Minimum coverage percentage required. Defaults to 90.

.EXAMPLE
    pwsh ./scripts/build-pr.ps1
    pwsh ./scripts/build-pr.ps1 -SkipSecurity
    pwsh ./scripts/build-pr.ps1 -CoverageThreshold 80
#>
param(
    [switch]$SkipTests,
    [switch]$SkipCoverage,
    [switch]$SkipSecurity,
    [int]$CoverageThreshold = 90
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

    $testProjects = @(Get-ChildItem -Path './tests' -Recurse -File -Include '*.csproj', '*.vbproj', '*.fsproj' -ErrorAction SilentlyContinue)

    if ($testProjects.Count -eq 0) {
        Write-Host "No test projects found in ./tests — skipping"
    }
    else {
        foreach ($testProj in $testProjects) {
            Write-Host ""
            Write-Host "Testing: $($testProj.FullName)" -ForegroundColor White

            $content = Get-Content $testProj.FullName -Raw
            $tfmMatch = [regex]::Match($content, '<TargetFramework[s]?>([^<]+)</TargetFramework[s]?>')

            if (-not $tfmMatch.Success) {
                Write-Host "  No target frameworks found — skipping" -ForegroundColor Yellow
                continue
            }

            $frameworks = $tfmMatch.Groups[1].Value -split ';' |
                ForEach-Object { $_.Trim() } |
                Where-Object { $_ -match '^net(5\.0|6\.0|7\.0|8\.0|9\.0|10\.0|462|47|471|472|48|481|coreapp3\.1)$' }

            if ($frameworks.Count -eq 0) {
                Write-Host "  No compatible frameworks — skipping" -ForegroundColor Yellow
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

                dotnet test @testArgs

                if ($LASTEXITCODE -ne 0) {
                    Write-Fail "  Tests failed for $fw"
                    $failed += "Tests ($fw)"
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
    Write-Step "Step 3: Coverage Report (threshold: ${CoverageThreshold}%)"

    $coverageFiles = Get-ChildItem -Path TestResults -Recurse -Filter coverage.cobertura.xml -ErrorAction SilentlyContinue

    if (-not $coverageFiles) {
        Write-Host "No coverage files found — skipping"
    }
    else {
        # Install ReportGenerator if not present
        $rgPath = Get-Command reportgenerator -ErrorAction SilentlyContinue
        if (-not $rgPath) {
            Write-Host "Installing ReportGenerator..."
            dotnet tool install -g dotnet-reportgenerator-globaltool
        }

        reportgenerator `
            -reports:"TestResults/**/coverage.cobertura.xml" `
            -targetdir:"CoverageReport" `
            -reporttypes:"Html;TextSummary;MarkdownSummaryGithub;CsvSummary"

        if (Test-Path "CoverageReport/Summary.txt") {
            Write-Host ""
            Get-Content "CoverageReport/Summary.txt"
            Write-Host ""

            $failedProjects = @()
            foreach ($line in (Get-Content "CoverageReport/Summary.txt")) {
                if ($line -match '^\s*(\S+)\s+(\d+(?:\.\d+)?)%\s*$' -and $line -notmatch '^\s*Summary') {
                    $module = $Matches[1]
                    $percent = [int][math]::Floor([double]$Matches[2])

                    if ($percent -lt $CoverageThreshold) {
                        Write-Fail "  $module — ${percent}% (below ${CoverageThreshold}%)"
                        $failedProjects += "$module (${percent}%)"
                    }
                    else {
                        Write-Pass "  $module — ${percent}%"
                    }
                }
            }

            if ($failedProjects.Count -gt 0) {
                Write-Fail "Coverage gate FAILED: $($failedProjects -join ', ')"
                $failed += "Coverage"
            }
            else {
                Write-Pass "Coverage gate passed"
            }
        }
        else {
            Write-Host "Coverage report not generated — skipping threshold check"
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
        $version = "8.24.0"
        if ($IsWindows -or $env:OS -match 'Windows') {
            $archive = "gitleaks_${version}_windows_x64.zip"
            $url = "https://github.com/gitleaks/gitleaks/releases/download/v${version}/$archive"
            $dest = Join-Path $env:LOCALAPPDATA "gitleaks"
            New-Item -ItemType Directory -Force -Path $dest | Out-Null
            $zip = Join-Path $env:TEMP $archive
            Invoke-WebRequest -Uri $url -OutFile $zip -UseBasicParsing
            Expand-Archive -Path $zip -DestinationPath $dest -Force
            Remove-Item $zip -ErrorAction SilentlyContinue
            $env:PATH = "$dest;$env:PATH"
        }
        else {
            $archive = "gitleaks_${version}_linux_x64.tar.gz"
            $url = "https://github.com/gitleaks/gitleaks/releases/download/v${version}/$archive"
            curl -sSfL $url | tar xz -C /usr/local/bin gitleaks
        }
    }

    gitleaks detect --source . --verbose --redact
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
