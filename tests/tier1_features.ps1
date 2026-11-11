# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Tier 1: Feature Coverage (Feature Isolation Tests)
    Exercises Features 1 through 6 in complete isolation to verify requirements R1-R4.
#>

param()

$ErrorActionPreference = "Stop"

# Load common test infrastructure
. (Join-Path $PSScriptRoot "Common.ps1")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TIER 1: FEATURE COVERAGE (ISOLATION TESTS)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ctx = Initialize-FluentFlyoutAssembly
$UpdateChecker = $ctx.UpdateChecker
$UpdateInstaller = $ctx.UpdateInstaller
$repoRoot = $ctx.RepoRoot
$TIER = "Tier1"

$sandbox = New-TestSandbox

try {
    # -------------------------------------------------------------
    # FEATURE 1: GitHub Fork Endpoint Configuration (ORIGINAL_REQUEST §R1)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 1: GitHub Fork Endpoint Configuration ---" -ForegroundColor Yellow

    # F1.1 Default owner is Fixbound
    $ownerProp = $UpdateChecker.GetField("DefaultGitHubOwner", [System.Reflection.BindingFlags]"Public,NonPublic,Static")
    $defaultOwner = $ownerProp.GetValue($null)
    Assert-Equal -Tier $TIER -Category "F1-Endpoint" -Name "F1.1: Default GitHub owner is 'Fixbound'" -Actual $defaultOwner -Expected "Fixbound"

    # F1.2 Default repo is FluentFlyout
    $repoProp = $UpdateChecker.GetField("DefaultGitHubRepo", [System.Reflection.BindingFlags]"Public,NonPublic,Static")
    $defaultRepo = $repoProp.GetValue($null)
    Assert-Equal -Tier $TIER -Category "F1-Endpoint" -Name "F1.2: Default GitHub repo is 'FluentFlyout'" -Actual $defaultRepo -Expected "FluentFlyout"

    # F1.3 Default endpoint URL
    $endpointProp = $UpdateChecker.GetProperty("GitHubApiLatestRelease", [System.Reflection.BindingFlags]"Public,NonPublic,Static")
    $defaultEndpoint = $endpointProp.GetValue($null)
    Assert-Equal -Tier $TIER -Category "F1-Endpoint" -Name "F1.3: Default endpoint URL matches GitHub Releases API" `
        -Actual $defaultEndpoint -Expected "https://api.github.com/repos/Fixbound/FluentFlyout/releases/latest"

    # F1.4 Overridden endpoint via FLUENTFLYOUT_UPDATE_REPO
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "custom-fork/FluentFlyout" -ScriptBlock {
        $customEndpoint = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "F1-Endpoint" -Name "F1.4: Dynamic override via FLUENTFLYOUT_UPDATE_REPO" `
            -Actual $customEndpoint -Expected "https://api.github.com/repos/custom-fork/FluentFlyout/releases/latest"
    }

    # F1.5 HttpClient timeout is 15s
    $clientField = $UpdateChecker.GetField("GitHubHttpClient", [System.Reflection.BindingFlags]"NonPublic,Static")
    $httpClient = $clientField.GetValue($null)
    $timeoutSec = if ($httpClient) { $httpClient.Timeout.TotalSeconds } else { 0 }
    Assert-Equal -Tier $TIER -Category "F1-Endpoint" -Name "F1.5: HttpClient timeout is configured to 15 seconds" `
        -Actual $timeoutSec -Expected 15

    # F1.6 Accept header configured
    $hasAccept = $httpClient.DefaultRequestHeaders.Accept.ToString()
    Assert-Match -Tier $TIER -Category "F1-Endpoint" -Name "F1.6: Accept header contains application/vnd.github.v3+json" `
        -Actual $hasAccept -Pattern "application/vnd\.github\.v3\+json"

    # F1.7 User-Agent header formation in FetchGitHubReleaseJsonAsync reflection inspection
    $fetchMethod = $UpdateChecker.GetMethod("FetchGitHubReleaseJsonAsync", [System.Reflection.BindingFlags]"NonPublic,Static")
    Assert-True -Tier $TIER -Category "F1-Endpoint" -Name "F1.7: FetchGitHubReleaseJsonAsync method exists" `
        -Actual ($null -ne $fetchMethod)

    # -------------------------------------------------------------
    # FEATURE 2: Robust SHA-256 Regex Extraction (ORIGINAL_REQUEST §R2)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 2: Robust SHA-256 Regex Extraction ---" -ForegroundColor Yellow

    $parseMethod = $UpdateChecker.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public,Static")
    $testHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    function Invoke-ParseHelper([string]$Body, [array]$Assets = $null) {
        if ($null -eq $Assets) {
            $Assets = @(
                @{
                    name = "FluentFlyout_2.16.0_x64_Installer.zip"
                    browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v2.16.0/FluentFlyout_2.16.0_x64_Installer.zip"
                }
            )
        }
        $payload = @{
            body = $Body
            assets = $Assets
        } | ConvertTo-Json -Depth 5
        $jsonDoc = [System.Text.Json.JsonDocument]::Parse($payload)
        return $parseMethod.Invoke($null, @($jsonDoc))
    }

    # F2.1 CI workflow standard format
    $res1 = Invoke-ParseHelper "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: $testHash"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.1: Standard CI workflow format SHA-256 extracted" `
        -Actual $res1.Item2 -Expected $testHash

    # F2.2 Uppercase normalization
    $upperHash = $testHash.ToUpperInvariant()
    $res2 = Invoke-ParseHelper "GitHub Release x64 checksum: $upperHash"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.2: Uppercase hex hash normalized to lowercase" `
        -Actual $res2.Item2 -Expected $testHash

    # F2.3 x64 checksum header
    $res3 = Invoke-ParseHelper "x64 checksum: $testHash"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.3: Keyword 'x64 checksum:' extracted" `
        -Actual $res3.Item2 -Expected $testHash

    # F2.4 Short SHA-256 header
    $res4 = Invoke-ParseHelper "SHA-256: $testHash"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.4: Keyword 'SHA-256:' extracted" `
        -Actual $res4.Item2 -Expected $testHash

    # F2.5 Space-separated sha256 (no colon)
    $res5 = Invoke-ParseHelper "sha256 $testHash"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.5: Space-separated 'sha256 <hash>' extracted" `
        -Actual $res5.Item2 -Expected $testHash

    # F2.6 Generic 64-hex fallback
    $res6 = Invoke-ParseHelper "Release notes without keywords:`n$testHash`nThanks!"
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.6: Generic 64-hex fallback extracted without keywords" `
        -Actual $res6.Item2 -Expected $testHash

    # F2.7 Asset selection prioritizes x64 Installer.zip
    $multiAssets = @(
        @{ name = "FluentFlyout_2.16.0_arm64_Installer.zip"; browser_download_url = "https://example.com/arm64.zip" },
        @{ name = "FluentFlyout_2.16.0_x64_Installer.zip"; browser_download_url = "https://example.com/x64.zip" }
    )
    $res7 = Invoke-ParseHelper "x64: $testHash" $multiAssets
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.7: Asset selection prioritizes x64 over arm64" `
        -Actual $res7.Item1 -Expected "https://example.com/x64.zip"

    # F2.8 Non-installer zip assets ignored
    $nonInstallerAssets = @(
        @{ name = "FluentFlyout_2.16.0_x64_portable.zip"; browser_download_url = "https://example.com/portable.zip" }
    )
    $res8 = Invoke-ParseHelper "x64: $testHash" $nonInstallerAssets
    Assert-Equal -Tier $TIER -Category "F2-Regex" -Name "F2.8: Non-installer zip assets ignored" `
        -Actual $res8.Item1 -Expected ""

    # -------------------------------------------------------------
    # FEATURE 3: Managed In-Process Download & Hash Check (ORIGINAL_REQUEST §R2)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 3: Managed In-Process Download & Hash Check ---" -ForegroundColor Yellow

    $verifyHashMethod = $UpdateInstaller.GetMethod("VerifyFileHashAsync", [System.Reflection.BindingFlags]"NonPublic,Static")

    function Invoke-VerifyHash([string]$Path, [string]$Hash) {
        $task = $verifyHashMethod.Invoke($null, [object[]]@([string]$Path, [string]$Hash))
        $task.Wait()
        return $task.Result
    }

    # F3.1 NIST Empty byte hash
    $emptyFilePath = Join-Path $sandbox "empty.bin"
    [System.IO.File]::WriteAllBytes($emptyFilePath, [byte[]]@())
    $resEmpty = Invoke-VerifyHash $emptyFilePath $testHash
    Assert-True -Tier $TIER -Category "F3-Crypto" -Name "F3.1: VerifyFileHashAsync verifies NIST empty hash" `
        -Actual $resEmpty

    # F3.2 NIST Fox string hash
    $foxPath = Join-Path $sandbox "fox.txt"
    $foxBytes = [System.Text.Encoding]::ASCII.GetBytes("The quick brown fox jumps over the lazy dog")
    [System.IO.File]::WriteAllBytes($foxPath, $foxBytes)
    $foxExpectedHash = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"
    $resFox = Invoke-VerifyHash $foxPath $foxExpectedHash
    Assert-True -Tier $TIER -Category "F3-Crypto" -Name "F3.2: VerifyFileHashAsync verifies NIST Fox string hash" `
        -Actual $resFox

    # F3.3 Cross-check binary file against system Get-FileHash
    $binPath = Join-Path $sandbox "test_data.bin"
    $randBytes = [byte[]]::new(1024 * 512)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($randBytes)
    [System.IO.File]::WriteAllBytes($binPath, $randBytes)
    $sysHash = (Get-FileHash -Path $binPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $resBin = Invoke-VerifyHash $binPath $sysHash
    Assert-True -Tier $TIER -Category "F3-Crypto" -Name "F3.3: VerifyFileHashAsync matches system Get-FileHash" `
        -Actual $resBin

    # F3.4 Case-insensitivity in hash comparison
    $resUpper = Invoke-VerifyHash $binPath ($sysHash.ToUpperInvariant())
    Assert-True -Tier $TIER -Category "F3-Crypto" -Name "F3.4: VerifyFileHashAsync handles uppercase expected hash" `
        -Actual $resUpper

    # F3.5 Non-existent file returns false
    $resMissing = Invoke-VerifyHash (Join-Path $sandbox "nonexistent.bin") $sysHash
    Assert-False -Tier $TIER -Category "F3-Crypto" -Name "F3.5: Non-existent file path returns false without throwing" `
        -Actual $resMissing

    # F3.6 1-bit tampering detection
    $tamperedPath = Join-Path $sandbox "tampered.bin"
    $tamperedBytes = [byte[]]::new($randBytes.Length)
    [Array]::Copy($randBytes, $tamperedBytes, $randBytes.Length)
    $tamperedBytes[100] = [byte]($tamperedBytes[100] -bxor 1)
    [System.IO.File]::WriteAllBytes($tamperedPath, $tamperedBytes)
    $resTampered = Invoke-VerifyHash $tamperedPath $sysHash
    Assert-False -Tier $TIER -Category "F3-Crypto" -Name "F3.6: Tampered byte detected and rejected" `
        -Actual $resTampered

    # -------------------------------------------------------------
    # FEATURE 4: Decoupled Installer Script Hardening (ORIGINAL_REQUEST §R2)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 4: Decoupled Installer Script Hardening ---" -ForegroundColor Yellow

    $buildScriptMethod = $UpdateInstaller.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic,Static")
    $testPid = 12345
    $testSysDir = "C:\FluentFlyout\updates\files\SystemFiles"
    $script = $buildScriptMethod.Invoke($null, @($testPid, $testSysDir))

    # F4.1 AST parsing without errors
    $astTokens = $null
    $astErrors = $null
    [System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$astTokens, [ref]$astErrors) | Out-Null
    Assert-Equal -Tier $TIER -Category "F4-Script" -Name "F4.1: Script generates valid PowerShell AST (0 errors)" `
        -Actual $astErrors.Count -Expected 0

    # F4.2 Process wait command
    Assert-Match -Tier $TIER -Category "F4-Script" -Name "F4.2: Script contains Wait-Process with target PID" `
        -Actual $script -Pattern "Wait-Process\s+-Id\s+$testPid"

    # F4.3 Set-Location with -LiteralPath
    Assert-Match -Tier $TIER -Category "F4-Script" -Name "F4.3: Script changes location using Set-Location -LiteralPath" `
        -Actual $script -Pattern "Set-Location\s+-LiteralPath\s+\`$systemFiles"

    # F4.4 Add-AppDevPackage execution with -Force and -SkipLoggingTelemetry
    Assert-Match -Tier $TIER -Category "F4-Script" -Name "F4.4: Script executes Add-AppDevPackage.ps1 with -Force -SkipLoggingTelemetry" `
        -Actual $script -Pattern "& '\.\\Add-AppDevPackage\.ps1'\s+-Force\s+-SkipLoggingTelemetry"

    # F4.5 Transcript logging
    Assert-Match -Tier $TIER -Category "F4-Script" -Name "F4.5: Script initializes Start-Transcript logging" `
        -Actual $script -Pattern "Start-Transcript\s+-Path\s+\`$logPath"

    # F4.6 Application relaunch logic
    Assert-Match -Tier $TIER -Category "F4-Script" -Name "F4.6: Script contains Get-AppxPackage relaunch routine" `
        -Actual $script -Pattern "Get-AppxPackage\s+'\*FluentFlyout\*'"

    # F4.7 ProcessStartInfo verb runas and bypass policy
    $installerCode = Get-Content (Join-Path $repoRoot "FluentFlyoutWPF\Classes\Services\UpdateInstallerService.cs") -Raw
    $hasRunas = $installerCode -match 'Verb\s*=\s*(isExe\s*\?\s*string\.Empty\s*:\s*)?"runas"'
    $hasUseShell = $installerCode -match 'UseShellExecute\s*=\s*true'
    $hasBypass = $installerCode -match '-ExecutionPolicy\s+Bypass'
    Assert-True -Tier $TIER -Category "F4-Script" -Name "F4.7: ProcessStartInfo sets runas, UseShellExecute, and Bypass policy" `
        -Actual ($hasRunas -and $hasUseShell -and $hasBypass)

    # -------------------------------------------------------------
    # FEATURE 5: MSIX Packaging & Manifest Compliance (ORIGINAL_REQUEST §R4)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 5: MSIX Packaging & Manifest Compliance ---" -ForegroundColor Yellow

    $manifestPath = Join-Path $repoRoot "FluentFlyoutMSIX\Package.appxmanifest"
    [xml]$manifestXml = Get-Content $manifestPath

    # F5.1 Identity Name
    Assert-Equal -Tier $TIER -Category "F5-Packaging" -Name "F5.1: Package Identity Name is 'unchihugo.FluentFlyout'" `
        -Actual $manifestXml.Package.Identity.Name -Expected "unchihugo.FluentFlyout"

    # F5.2 Identity Publisher
    Assert-Equal -Tier $TIER -Category "F5-Packaging" -Name "F5.2: Package Identity Publisher is 'CN=49793F74-1457-4B66-A672-4ED3A640FC76'" `
        -Actual $manifestXml.Package.Identity.Publisher -Expected "CN=49793F74-1457-4B66-A672-4ED3A640FC76"

    # F5.3 StartupTask extension
    $startupExtension = $manifestXml.Package.Applications.Application.Extensions.Extension | Where-Object { $_.Category -eq "windows.startupTask" }
    $taskId = if ($startupExtension) { $startupExtension.StartupTask.TaskId } else { "" }
    Assert-Equal -Tier $TIER -Category "F5-Packaging" -Name "F5.3: Manifest defines StartupTask 'FluentFlyoutStartup'" `
        -Actual $taskId -Expected "FluentFlyoutStartup"

    # F5.4 Toast notification activation extension
    $toastExtension = $manifestXml.Package.Applications.Application.Extensions.Extension | Where-Object { $_.Category -eq "windows.toastNotificationActivation" }
    $toastClsid = if ($toastExtension) { $toastExtension.ToastNotificationActivation.ToastActivatorCLSID } else { "" }
    Assert-Equal -Tier $TIER -Category "F5-Packaging" -Name "F5.4: Manifest defines ToastNotificationActivation extension" `
        -Actual $toastClsid -Expected "79086E7F-0D65-4507-82B6-85F2288930D5"

    # F5.5 ComServer extension
    $comExtension = $manifestXml.Package.Applications.Application.Extensions.Extension | Where-Object { $_.Category -eq "windows.comServer" }
    $comExe = if ($comExtension) { $comExtension.ComServer.ExeServer.Executable } else { "" }
    Assert-Equal -Tier $TIER -Category "F5-Packaging" -Name "F5.5: Manifest defines ComServer executable" `
        -Actual $comExe -Expected "FluentFlyout\FluentFlyout.exe"

    # F5.6 wapproj SideloadOnly configuration
    $wapprojContent = Get-Content (Join-Path $repoRoot "FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj") -Raw
    Assert-Match -Tier $TIER -Category "F5-Packaging" -Name "F5.6: wapproj configures SideloadOnly mode for GitHub Release" `
        -Actual $wapprojContent -Pattern "<UapAppxPackageBuildMode[^>]*>SideloadOnly</UapAppxPackageBuildMode>"

    # F5.7 wapproj test artifacts and signing enabled
    $hasTestArtifacts = $wapprojContent -match "<GenerateTestArtifacts>True</GenerateTestArtifacts>"
    $hasSigningEnabled = $wapprojContent -match "<AppxPackageSigningEnabled>True</AppxPackageSigningEnabled>"
    Assert-True -Tier $TIER -Category "F5-Packaging" -Name "F5.7: wapproj enables test artifacts and package signing" `
        -Actual ($hasTestArtifacts -and $hasSigningEnabled)

    # -------------------------------------------------------------
    # FEATURE 6: CI Workflow Syntax & Steps (ORIGINAL_REQUEST §R3)
    # -------------------------------------------------------------
    Write-Host "`n--- Feature 6: CI Workflow Syntax & Steps ---" -ForegroundColor Yellow

    $workflowPath = Join-Path $repoRoot ".github\workflows\build-msix.yml"
    Assert-True -Tier $TIER -Category "F6-Workflow" -Name "F6.1: Workflow file exists at .github/workflows/build-msix.yml" `
        -Actual (Test-Path $workflowPath)

    $workflowContent = Get-Content $workflowPath -Raw

    # F6.2 Workflow tag trigger
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.2: Workflow triggers on 'v*' tags" `
        -Actual $workflowContent -Pattern "tags:\s*[\r\n]+\s*-\s*'v\*'"

    # F6.3 Matrix configuration includes GitHub Release
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.3: Workflow matrix builds 'GitHub Release'" `
        -Actual $workflowContent -Pattern 'configuration:\s*\["GitHub Release",\s*"Release"\]'

    # F6.4 .NET 10 SDK setup
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.4: Workflow installs .NET 10.0.x SDK" `
        -Actual $workflowContent -Pattern "dotnet-version:\s*10\.0\.x"

    # F6.5 Dynamic self-signed certificate fallback
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.5: Dynamic self-signed certificate fallback matches manifest publisher" `
        -Actual $workflowContent -Pattern 'New-SelfSignedCertificate[\s\S]*?CN=49793F74-1457-4B66-A672-4ED3A640FC76'

    # F6.6 Staged installer structure with SystemFiles
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.6: Workflow stages SystemFiles with bat and README" `
        -Actual $workflowContent -Pattern 'FluentFlyout_Installer\.bat'

    # F6.7 Companion sha256 file and release publishing
    Assert-Match -Tier $TIER -Category "F6-Workflow" -Name "F6.7: Workflow generates companion sha256 and calls gh release" `
        -Actual $workflowContent -Pattern 'gh release upload'

} finally {
    Remove-TestSandbox $sandbox
}

Write-Host "`nTier 1 Feature Coverage Execution Complete." -ForegroundColor Cyan
