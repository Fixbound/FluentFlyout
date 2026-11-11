# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Single self-contained test runner for FluentFlyout end-to-end verification suites (Tiers 1-4).
    Executes entirely offline without making remote network calls or git commits.

.PARAMETER Tier
    Specify which tier to execute: 'All' (default), '1', '2', '3', or '4'.

.PARAMETER Detailed
    Display verbose per-assertion diagnostic output.

.EXAMPLE
    pwsh ./tests/run_all_tests.ps1
    pwsh ./tests/run_all_tests.ps1 -Tier 1
    pwsh ./tests/run_all_tests.ps1 -Tier 4 -Detailed
#>

[CmdletBinding()]
param(
    [ValidateSet("All", "1", "2", "3", "4")]
    [string]$Tier = "All",

    [switch]$Detailed
)

$ErrorActionPreference = "Stop"

# Auto-relaunch into pwsh (PowerShell 7+) if running under Windows PowerShell 5.1
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        Write-Host "Detected Windows PowerShell $($PSVersionTable.PSVersion). Relaunching in pwsh (PowerShell 7+) for .NET 10 runtime support..." -ForegroundColor Yellow
        $boundArgs = @()
        if ($PSBoundParameters.ContainsKey('Tier')) { $boundArgs += "-Tier", $Tier }
        if ($Detailed) { $boundArgs += "-Detailed" }
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @boundArgs
        exit $LASTEXITCODE
    } else {
        Write-Error "PowerShell 7+ (pwsh) is required to run FluentFlyout .NET 10 assembly test suites."
        exit 1
    }
}

$testsDir = $PSScriptRoot
. (Join-Path $testsDir "Common.ps1")

Reset-TestResults
$stopwatch = [System.Diagnostics.Stopwatch]::StartNew()

Write-Host @"
================================================================================
           FLUENTFLYOUT END-TO-END VERIFICATION SUITE (TIERS 1-4)
================================================================================
Mode: Offline / Local Simulation Only
Runtime: PowerShell $($PSVersionTable.PSVersion) (.NET $([System.Environment]::Version))
Target: FluentFlyoutWPF (Configuration: 'GitHub Release', Platform: x64)
Execution Selection: Tier $Tier
================================================================================
"@ -ForegroundColor Cyan

# Pre-build verification to ensure compiled assembly is fresh
Write-Host "Verifying target assembly build..." -ForegroundColor Gray
$repoRoot = (Resolve-Path (Join-Path $testsDir "..")).Path
$init = Initialize-FluentFlyoutAssembly -RepoRoot $repoRoot
Write-Host "Loaded assembly: $($init.Assembly.FullName)" -ForegroundColor Gray
Write-Host "Assembly path:   $($init.DllPath)" -ForegroundColor Gray

# Execute selected tiers
$tierScripts = @()
if ($Tier -eq "All" -or $Tier -eq "1") { $tierScripts += (Join-Path $testsDir "tier1_features.ps1") }
if ($Tier -eq "All" -or $Tier -eq "2") { $tierScripts += (Join-Path $testsDir "tier2_boundaries.ps1") }
if ($Tier -eq "All" -or $Tier -eq "3") { $tierScripts += (Join-Path $testsDir "tier3_interactions.ps1") }
if ($Tier -eq "All" -or $Tier -eq "4") { $tierScripts += (Join-Path $testsDir "tier4_scenarios.ps1") }

foreach ($scriptPath in $tierScripts) {
    $scriptName = Split-Path -Leaf $scriptPath
    Write-Host "`n>>> Running: $scriptName" -ForegroundColor Magenta
    try {
        & $scriptPath
    } catch {
        Write-Error "Execution error while running $scriptName : $_"
        Record-TestResult -Tier "Runner" -Category "Execution" -Name "Execution of $scriptName" -Status "FAIL" -Details $_.Exception.Message
    }
}

$stopwatch.Stop()

# --------------------------------------------------------------------------------
# COMPREHENSIVE RESULTS & COVERAGE SUMMARY
# --------------------------------------------------------------------------------
$allResults = $global:TestResults
$totalCount = $allResults.Count
$passedCount = ($allResults | Where-Object { $_.Status -eq "PASS" }).Count
$failedCount = ($allResults | Where-Object { $_.Status -eq "FAIL" }).Count
$passRate = if ($totalCount -gt 0) { [Math]::Round(($passedCount / $totalCount) * 100, 2) } else { 0.0 }

Write-Host "`n================================================================================" -ForegroundColor Cyan
Write-Host "                         STRUCTURED TEST SUMMARY REPORT" -ForegroundColor Cyan
Write-Host "================================================================================" -ForegroundColor Cyan

# Group breakdown by Tier and Category
$breakdown = $allResults | Group-Object Tier, Category | ForEach-Object {
    $tierName = $_.Values[0]
    $categoryName = $_.Values[1]
    $groupTotal = $_.Group.Count
    $groupPass = ($_.Group | Where-Object { $_.Status -eq "PASS" }).Count
    $groupFail = ($_.Group | Where-Object { $_.Status -eq "FAIL" }).Count
    $groupRate = if ($groupTotal -gt 0) { [Math]::Round(($groupPass / $groupTotal) * 100, 1) } else { 0 }
    $groupStatus = if ($groupFail -eq 0) { "PASS" } else { "FAIL" }

    [PSCustomObject]@{
        Tier      = $tierName
        Category  = $categoryName
        Total     = $groupTotal
        Passed    = $groupPass
        Failed    = $groupFail
        Rate      = "$groupRate %"
        Status    = $groupStatus
    }
}

$breakdown | Format-Table -AutoSize -Property Tier, Category, Total, Passed, Failed, Rate, Status | Out-String | Write-Host

Write-Host "--------------------------------------------------------------------------------" -ForegroundColor Cyan
Write-Host "OVERALL METRICS:" -ForegroundColor Cyan
Write-Host "  Total Tests:       $totalCount"
Write-Host "  Passed:            $passedCount" -ForegroundColor Green
if ($failedCount -gt 0) {
    Write-Host "  Failed:            $failedCount" -ForegroundColor Red
} else {
    Write-Host "  Failed:            0" -ForegroundColor Green
}
Write-Host "  Pass Rate:         $passRate %" -ForegroundColor $(if ($failedCount -eq 0) { "Green" } else { "Red" })
Write-Host "  Elapsed Time:      $([Math]::Round($stopwatch.Elapsed.TotalSeconds, 2)) seconds"
Write-Host "================================================================================" -ForegroundColor Cyan

if ($failedCount -eq 0) {
    Write-Host "`n[SUCCESS] 100% of all executed tests passed successfully. Exit code: 0`n" -ForegroundColor Green
    exit 0
} else {
    Write-Host "`n[FAILURE] $failedCount test(s) failed. Exit code: 1`n" -ForegroundColor Red
    exit 1
}
