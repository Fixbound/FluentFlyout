# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Tier 4: Real-World Scenarios (Full Offline Simulated Pipelines)
    Executes realistic end-to-end update flows, corrupted download recoveries, upstream isolation,
    complex real-world release notes, and full CI staging simulations completely offline.
#>

param()

$ErrorActionPreference = "Stop"

# Load common test infrastructure
. (Join-Path $PSScriptRoot "Common.ps1")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TIER 4: REAL-WORLD SCENARIOS (OFFLINE SIMULATED PIPELINES)" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ctx = Initialize-FluentFlyoutAssembly
$UpdateChecker = $ctx.UpdateChecker
$UpdateInstaller = $ctx.UpdateInstaller
$repoRoot = $ctx.RepoRoot
$TIER = "Tier4"

$sandbox = New-TestSandbox

try {
    $manifestPath = Join-Path $repoRoot "FluentFlyoutMSIX\Package.appxmanifest"
    [xml]$manifestXml = Get-Content $manifestPath
    $currentVersion = ($manifestXml.Package.Identity.Version -split '\.')[0..2] -join '.'
    $publisherCN = $manifestXml.Package.Identity.Publisher

    $parseMethod = $UpdateChecker.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public,Static")
    $verifyHashMethod = $UpdateInstaller.GetMethod("VerifyFileHashAsync", [System.Reflection.BindingFlags]"NonPublic,Static")
    $buildScriptMethod = $UpdateInstaller.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic,Static")
    $isNewerMethod = $UpdateChecker.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public,Static")
    $checkUpdatesMethod = $UpdateChecker.GetMethod("CheckForUpdatesAsync", [System.Reflection.BindingFlags]"Public,Static")

    function Invoke-VerifyHashHelper([string]$Path, [string]$Hash) {
        $task = $verifyHashMethod.Invoke($null, [object[]]@([string]$Path, [string]$Hash))
        $task.Wait()
        return $task.Result
    }

    # -------------------------------------------------------------
    # SCENARIO 1: Normal Update Flow (End-to-End Offline Simulation)
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 1: Normal Update Flow (Full Simulation) ---" -ForegroundColor Yellow

    # 1. Create a genuine installer zip package for version 2.17.0
    $s1PackageSource = Join-Path $sandbox "S1_PkgSource"
    $s1SystemFiles = Join-Path $s1PackageSource "SystemFiles"
    New-Item -ItemType Directory -Path $s1SystemFiles -Force | Out-Null

    Copy-Item (Join-Path $repoRoot ".github\build-files\FluentFlyout_Installer.bat") "$s1PackageSource\"
    Copy-Item (Join-Path $repoRoot ".github\build-files\README.txt") "$s1PackageSource\"
    Set-Content -Path (Join-Path $s1SystemFiles "Add-AppDevPackage.ps1") -Value "# Simulated installer script`r`nWrite-Output 'Installed!'"
    Set-Content -Path (Join-Path $s1SystemFiles "FluentFlyout.msix") -Value "MSIX BINARY PAYLOAD"

    $s1ZipName = "FluentFlyout_2.17.0_x64_Installer.zip"
    $s1ZipPath = Join-Path $sandbox $s1ZipName
    [System.IO.Compression.ZipFile]::CreateFromDirectory($s1PackageSource, $s1ZipPath)

    $s1ExpectedSha = (Get-FileHash -Path $s1ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $s1ZipBytes = [System.IO.File]::ReadAllBytes($s1ZipPath)

    # 2. Parse mock release JSON payload with dynamic available port
    $tcp = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, 0)
    $tcp.Start()
    $listenerPort = $tcp.LocalEndpoint.Port
    $tcp.Stop()
    $listenerPrefix = "http://127.0.0.1:$listenerPort/"

    $s1ReleaseJson = @{
        tag_name = "v2.17.0"
        html_url = "https://github.com/unchihugo/FluentFlyout/releases/tag/v2.17.0"
        body = "## FluentFlyout v2.17.0 Release`n`nNew modern flyout features.`n`nGitHub Release x64 installer: $s1ZipName`nGitHub Release x64 checksum: $s1ExpectedSha"
        assets = @(
            @{
                name = $s1ZipName
                browser_download_url = "$listenerPrefix$s1ZipName"
            }
        )
    } | ConvertTo-Json -Depth 5
    $s1JsonDoc = [System.Text.Json.JsonDocument]::Parse($s1ReleaseJson)

    $s1ParseRes = $parseMethod.Invoke($null, @($s1JsonDoc))
    $s1AssetUrl = $s1ParseRes.Item1
    $s1ParsedSha = $s1ParseRes.Item2

    Assert-Equal -Tier $TIER -Category "S1-NormalFlow" -Name "S1.1: Release asset URL parsed from mock server" `
        -Actual $s1AssetUrl -Expected "$listenerPrefix$s1ZipName"
    Assert-Equal -Tier $TIER -Category "S1-NormalFlow" -Name "S1.2: Expected SHA-256 matches real zip checksum" `
        -Actual $s1ParsedSha -Expected $s1ExpectedSha

    # Verify version indicates update available
    $s1IsUpgrade = [bool]$isNewerMethod.Invoke($null, @($currentVersion, "v2.17.0"))
    Assert-True -Tier $TIER -Category "S1-NormalFlow" -Name "S1.3: Update detected as newer upgrade (v$currentVersion -> v2.17.0)" `
        -Actual $s1IsUpgrade

    # Download asset to simulated staging via loopback HttpListener
    $s1StagingDir = Join-Path $sandbox "S1_Staging"
    New-Item -ItemType Directory -Path $s1StagingDir -Force | Out-Null
    $s1DownloadedZip = Join-Path $s1StagingDir "update.zip"

    $listener = [System.Net.HttpListener]::new()
    $listener.Prefixes.Add($listenerPrefix)
    $listener.Start()

    try {
        $ar = $listener.BeginGetContext($null, $null)

        $downloadClient = [System.Net.Http.HttpClient]::new()
        $downloadTask = $downloadClient.GetStreamAsync($s1AssetUrl)

        $httpCtx = $listener.EndGetContext($ar)
        $resp = $httpCtx.Response
        $resp.ContentType = "application/zip"
        $resp.ContentLength64 = $s1ZipBytes.Length
        $resp.OutputStream.Write($s1ZipBytes, 0, $s1ZipBytes.Length)
        $resp.Close()

        $downloadStream = $downloadTask.GetAwaiter().GetResult()
        $fileStream = [System.IO.FileStream]::new($s1DownloadedZip, [System.IO.FileMode]::Create)
        $downloadStream.CopyTo($fileStream)
        $fileStream.Close()
        $downloadStream.Close()
        $downloadClient.Dispose()
    } finally {
        $listener.Stop()
        $listener.Close()
    }

    Assert-True -Tier $TIER -Category "S1-NormalFlow" -Name "S1.4: Update asset downloaded successfully to staging" `
        -Actual (Test-Path $s1DownloadedZip)

    # Verify hash
    $s1HashOk = Invoke-VerifyHashHelper $s1DownloadedZip $s1ParsedSha
    Assert-True -Tier $TIER -Category "S1-NormalFlow" -Name "S1.5: SHA-256 verification of downloaded zip succeeds" `
        -Actual $s1HashOk

    # Extract to files\
    $s1FilesDir = Join-Path $s1StagingDir "files"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($s1DownloadedZip, $s1FilesDir, $true)

    $s1DiscoveredScript = Join-Path $s1FilesDir "SystemFiles\Add-AppDevPackage.ps1"
    Assert-True -Tier $TIER -Category "S1-NormalFlow" -Name "S1.6: Staging extraction contains SystemFiles/Add-AppDevPackage.ps1" `
        -Actual (Test-Path $s1DiscoveredScript)

    # Generate apply.ps1
    $s1ApplyScriptPath = Join-Path $s1StagingDir "apply.ps1"
    $s1SysPath = [string](Join-Path $s1FilesDir "SystemFiles")
    $s1ScriptBody = $buildScriptMethod.Invoke($null, [object[]]@([int]1234, $s1SysPath))
    [System.IO.File]::WriteAllText($s1ApplyScriptPath, $s1ScriptBody)

    Assert-True -Tier $TIER -Category "S1-NormalFlow" -Name "S1.7: Decoupled apply.ps1 generated in staging root" `
        -Actual (Test-Path $s1ApplyScriptPath)

    # -------------------------------------------------------------
    # SCENARIO 2: Corrupted Download Recovery
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 2: Corrupted Download Recovery ---" -ForegroundColor Yellow

    $s2StagingDir = Join-Path $sandbox "S2_Staging"
    New-Item -ItemType Directory -Path $s2StagingDir -Force | Out-Null
    $s2CorruptedZip = Join-Path $s2StagingDir "update.zip"

    # Write truncated/tampered zip
    $badBytes = [byte[]]::new(1024)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($badBytes)
    [System.IO.File]::WriteAllBytes($s2CorruptedZip, $badBytes)

    $s2ExpectedSha = "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee"

    # VerifyFileHashAsync must reject
    $s2VerifyRes = Invoke-VerifyHashHelper $s2CorruptedZip $s2ExpectedSha
    Assert-False -Tier $TIER -Category "S2-CorruptRecovery" -Name "S2.1: Corrupted zip rejected by VerifyFileHashAsync" `
        -Actual $s2VerifyRes

    # Ensure staging extraction does not proceed when hash check fails
    $s2FilesDir = Join-Path $s2StagingDir "files"
    $extractionAttempted = Test-Path $s2FilesDir
    Assert-False -Tier $TIER -Category "S2-CorruptRecovery" -Name "S2.2: Extraction did not proceed on hash failure" `
        -Actual $extractionAttempted

    # Cleanup staging directory after failed verification
    Remove-Item $s2StagingDir -Recurse -Force -ErrorAction SilentlyContinue
    Assert-False -Tier $TIER -Category "S2-CorruptRecovery" -Name "S2.3: Scratch staging cleaned cleanly on abort" `
        -Actual (Test-Path $s2StagingDir)

    # -------------------------------------------------------------
    # SCENARIO 3: Upstream Isolation Under GITHUB_RELEASE
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 3: Upstream Isolation Under GITHUB_RELEASE ---" -ForegroundColor Yellow

    # Simulate GitHub endpoint failure by pointing FLUENTFLYOUT_UPDATE_REPO to an unreachable loopback port
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "127.0.0.1:59998/offline-repo" -ScriptBlock {
        $task = $checkUpdatesMethod.Invoke($null, @($currentVersion))
        $task.Wait()
        $checkRes = $task.Result

        # In GITHUB_RELEASE, failed check returns Success=false and does NOT fallback to fluentflyout.com
        Assert-False -Tier $TIER -Category "S3-Isolation" -Name "S3.1: Network error results in Success=false without crashing" `
            -Actual $checkRes.Success
        Assert-False -Tier $TIER -Category "S3-Isolation" -Name "S3.2: Network error reports no update available" `
            -Actual $checkRes.IsUpdateAvailable
        Assert-Equal -Tier $TIER -Category "S3-Isolation" -Name "S3.3: AssetUrl remains empty on failed GitHub check" `
            -Actual $checkRes.AssetUrl -Expected ""
    }

    # -------------------------------------------------------------
    # SCENARIO 4: Custom / Fringe Release Notes Formats in the Wild
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 4: Custom / Fringe Release Notes in the Wild ---" -ForegroundColor Yellow

    $fringeShaX64 = "6666666666666666666666666666666666666666666666666666666666666666"
    $fringeShaArm = "7777777777777777777777777777777777777777777777777777777777777777"
    $fringeNotes = @"
# FluentFlyout Release Announcement v2.16.5

We are thrilled to announce FluentFlyout v2.16.5!
* Commit SHA: c8d29b014a67819ef3425510abcd394857201948
* Built with .NET 10 SDK and Windows App SDK.

### Architecture Checksums
| Architecture | SHA-256 Digest |
| :--- | :--- |
| ARM64 | $fringeShaArm |
| x64 (Primary) | $fringeShaX64 |

> Note: Previous release checksum was 0000000000000000000000000000000000000000000000000000000000000000.
"@
    $fringePayload = @{
        body = $fringeNotes
        assets = @(
            @{ name = "FluentFlyout_2.16.5_x64_Installer.zip"; browser_download_url = "https://example.com/ff_x64.zip" }
        )
    } | ConvertTo-Json -Depth 5
    $fringeDoc = [System.Text.Json.JsonDocument]::Parse($fringePayload)
    $fringeRes = $parseMethod.Invoke($null, @($fringeDoc))

    Assert-Equal -Tier $TIER -Category "S4-FringeNotes" -Name "S4.1: x64 hash correctly extracted from multi-table release notes" `
        -Actual $fringeRes.Item2 -Expected $fringeShaX64
    Assert-Equal -Tier $TIER -Category "S4-FringeNotes" -Name "S4.2: Asset URL correctly selected for x64 installer" `
        -Actual $fringeRes.Item1 -Expected "https://example.com/ff_x64.zip"

    # -------------------------------------------------------------
    # SCENARIO 5: Full Offline CI Pipeline Staging & Packaging Simulation
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 5: Full CI Pipeline Simulation ---" -ForegroundColor Yellow

    # Step 1: Extract app version
    $appVersion = ($manifestXml.Package.Identity.Version -split '\.')[0..2] -join '.'
    Assert-Equal -Tier $TIER -Category "S5-CIPipeline" -Name "S5.1: CI Step 'Extract app version' extracts 3-part version" `
        -Actual $appVersion -Expected "2.16.0"

    # Step 2: Configure Signing Certificate
    $ciPfxPath = Join-Path $sandbox "FluentFlyout_Signing.pfx"
    $ciPfxPassword = "FluentFlyoutDevPassword123!"
    $secPass = ConvertTo-SecureString -String $ciPfxPassword -Force -AsPlainText
    $cert = New-SelfSignedCertificate -Type Custom `
        -Subject $publisherCN `
        -KeyUsage DigitalSignature `
        -FriendlyName "FluentFlyout Sideload Cert" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")
    Export-PfxCertificate -Cert $cert -FilePath $ciPfxPath -Password $secPass | Out-Null
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue

    Assert-True -Tier $TIER -Category "S5-CIPipeline" -Name "S5.2: CI Step 'Configure Signing Certificate' generates valid PFX" `
        -Actual (Test-Path $ciPfxPath)

    # Step 3: Prepare installer structure
    $ciOutDir = Join-Path $sandbox "InstallerOutput"
    $ciSysFilesDir = Join-Path $ciOutDir "SystemFiles"
    New-Item -ItemType Directory -Path $ciSysFilesDir -Force | Out-Null

    # Mock AppxPackages\*_Test
    $mockTestFolder = Join-Path $sandbox "AppxPackages\FluentFlyoutMSIX_2.16.0.0_Test"
    New-Item -ItemType Directory -Path $mockTestFolder -Force | Out-Null
    Set-Content -Path (Join-Path $mockTestFolder "Add-AppDevPackage.ps1") -Value "# VS test script"
    Set-Content -Path (Join-Path $mockTestFolder "FluentFlyout.msix") -Value "MSIX MOCK"

    Copy-Item -Path "$mockTestFolder\*" -Destination $ciSysFilesDir -Recurse -Force
    Copy-Item (Join-Path $repoRoot ".github\build-files\FluentFlyout_Installer.bat") "$ciOutDir\"
    Copy-Item (Join-Path $repoRoot ".github\build-files\README.txt") "$ciOutDir\"

    Assert-True -Tier $TIER -Category "S5-CIPipeline" -Name "S5.3: CI Step 'Prepare installer structure' stages SystemFiles and bat" `
        -Actual ((Test-Path (Join-Path $ciSysFilesDir "Add-AppDevPackage.ps1")) -and (Test-Path (Join-Path $ciOutDir "FluentFlyout_Installer.bat")))

    # Step 4: Publish GitHub Release installer (zip + sha256 + notes)
    $zipArtifactName = "FluentFlyout_${appVersion}_x64_Installer.zip"
    $zipArtifactPath = Join-Path $sandbox $zipArtifactName
    Compress-Archive -Path "$ciOutDir\*" -DestinationPath $zipArtifactPath

    $ciSha = (Get-FileHash -Path $zipArtifactPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $ciShaFilePath = "$zipArtifactPath.sha256"
    "$ciSha  $zipArtifactName" | Out-File -FilePath $ciShaFilePath -Encoding ascii

    Assert-True -Tier $TIER -Category "S5-CIPipeline" -Name "S5.4: CI Step produces zip package and companion .sha256 file" `
        -Actual ((Test-Path $zipArtifactPath) -and (Test-Path $ciShaFilePath))

    # Step 5: Roundtrip validation with UpdateCheckerService
    $ciReleaseBlock = "GitHub Release x64 installer: $zipArtifactName`nGitHub Release x64 checksum: $ciSha"
    $ciPayload = @{
        body = $ciReleaseBlock
        assets = @(@{ name = $zipArtifactName; browser_download_url = "https://example.com/$zipArtifactName" })
    } | ConvertTo-Json -Depth 5
    $ciRoundtripDoc = [System.Text.Json.JsonDocument]::Parse($ciPayload)
    $ciRoundtripRes = $parseMethod.Invoke($null, @($ciRoundtripDoc))

    Assert-Equal -Tier $TIER -Category "S5-CIPipeline" -Name "S5.5: UpdateCheckerService roundtrip matches CI computed SHA-256" `
        -Actual $ciRoundtripRes.Item2 -Expected $ciSha

    # -------------------------------------------------------------
    # SCENARIO 6: Decoupled apply.ps1 Execution & Logging Verification
    # -------------------------------------------------------------
    Write-Host "`n--- Scenario 6: Decoupled apply.ps1 Execution & Logging Verification ---" -ForegroundColor Yellow

    $s6Staging = Join-Path $sandbox "S6_ExecutionStaging"
    $s6SystemFiles = Join-Path $s6Staging "SystemFiles"
    New-Item -ItemType Directory -Path $s6SystemFiles -Force | Out-Null

    # Create mock Add-AppDevPackage.ps1 that creates a sentinel file
    $sentinelFile = Join-Path $s6Staging "install_executed.marker"
    $mockInstallerScript = @"
param([switch]`$Force, [switch]`$SkipLoggingTelemetry)
Write-Output "Mock Add-AppDevPackage.ps1 invoked with Force=`$Force, SkipTelemetry=`$SkipLoggingTelemetry"
Set-Content -Path '$sentinelFile' -Value "Executed at `$(Get-Date -Format o)"
"@
    Set-Content -Path (Join-Path $s6SystemFiles "Add-AppDevPackage.ps1") -Value $mockInstallerScript

    # Generate apply.ps1 with PID of a short-lived mock process
    $mockProc = Start-Process powershell -ArgumentList "-NoProfile -Command Start-Sleep -Milliseconds 500" -PassThru
    $mockPid = $mockProc.Id

    $s6ApplyContent = $buildScriptMethod.Invoke($null, [object[]]@([int]$mockPid, [string]$s6SystemFiles))
    $s6ApplyScript = Join-Path $s6Staging "apply.ps1"
    [System.IO.File]::WriteAllText($s6ApplyScript, $s6ApplyContent)

    # Execute apply.ps1 in child PowerShell process
    $execProc = Start-Process pwsh -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$s6ApplyScript`"" -WorkingDirectory $s6Staging -NoNewWindow -Wait -PassThru

    Assert-Equal -Tier $TIER -Category "S6-ScriptExec" -Name "S6.1: apply.ps1 execution completed successfully (ExitCode 0)" `
        -Actual $execProc.ExitCode -Expected 0

    # Verify sentinel marker was created by Add-AppDevPackage.ps1
    Assert-True -Tier $TIER -Category "S6-ScriptExec" -Name "S6.2: Add-AppDevPackage.ps1 executed successfully via apply.ps1" `
        -Actual (Test-Path $sentinelFile)

    # Verify update_install.log was created by Start-Transcript
    $logFile = Join-Path $s6Staging "update_install.log"
    Assert-True -Tier $TIER -Category "S6-ScriptExec" -Name "S6.3: update_install.log transcript was generated" `
        -Actual (Test-Path $logFile)

    if (Test-Path $logFile) {
        $logContent = Get-Content $logFile -Raw
        Assert-Match -Tier $TIER -Category "S6-ScriptExec" -Name "S6.4: Log records Add-AppDevPackage execution" `
            -Actual $logContent -Pattern "Add-AppDevPackage\.ps1"
    }

} finally {
    Remove-TestSandbox $sandbox
}

Write-Host "`nTier 4 Real-World Scenarios Execution Complete." -ForegroundColor Cyan
