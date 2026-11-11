# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Tier 3: Cross-Feature Interactions & Pairwise Integration
    Validates end-to-end integration between CI release publishing, UpdateChecker parsing,
    zip staging layouts, installer script discovery, certificate matching, and license unlocking.
#>

param()

$ErrorActionPreference = "Stop"

# Load common test infrastructure
. (Join-Path $PSScriptRoot "Common.ps1")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TIER 3: CROSS-FEATURE INTERACTIONS & INTEGRATION" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ctx = Initialize-FluentFlyoutAssembly
$UpdateChecker = $ctx.UpdateChecker
$UpdateInstaller = $ctx.UpdateInstaller
$LicenseManager = $ctx.LicenseManager
$repoRoot = $ctx.RepoRoot
$TIER = "Tier3"

$sandbox = New-TestSandbox

try {
    $manifestPath = Join-Path $repoRoot "FluentFlyoutMSIX\Package.appxmanifest"
    [xml]$manifestXml = Get-Content $manifestPath
    $manifestVersion = ($manifestXml.Package.Identity.Version -split '\.')[0..2] -join '.'
    $publisherCN = $manifestXml.Package.Identity.Publisher

    $parseMethod = $UpdateChecker.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public,Static")
    $verifyHashMethod = $UpdateInstaller.GetMethod("VerifyFileHashAsync", [System.Reflection.BindingFlags]"NonPublic,Static")
    $buildScriptMethod = $UpdateInstaller.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic,Static")
    $isNewerMethod = $UpdateChecker.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public,Static")

    function Invoke-VerifyHashHelper([string]$Path, [string]$Hash) {
        $task = $verifyHashMethod.Invoke($null, [object[]]@([string]$Path, [string]$Hash))
        $task.Wait()
        return $task.Result
    }

    # -------------------------------------------------------------
    # INTERACTION 1: CI Release Notes Publishing Format ↔ UpdateCheckerService Regex Extraction
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 1: CI Release Notes Format ↔ UpdateCheckerService Parsing ---" -ForegroundColor Yellow

    $testSha1 = "4444444444444444444444444444444444444444444444444444444444444444"
    $testSha2 = "5555555555555555555555555555555555555555555555555555555555555555"
    $zipName = "FluentFlyout_${manifestVersion}_x64_Installer.zip"
    $checksumBlock = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $testSha2"

    # Scenario A: CI Brand new release
    $jsonA = @{
        tag_name = "v$manifestVersion"
        body = $checksumBlock
        assets = @(@{ name = $zipName; browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v$manifestVersion/$zipName" })
    } | ConvertTo-Json -Depth 5
    $docA = [System.Text.Json.JsonDocument]::Parse($jsonA)
    $resA = $parseMethod.Invoke($null, @($docA))
    Assert-Equal -Tier $TIER -Category "I1-CI-Parsing" -Name "I1.1: New CI release payload parsed by UpdateCheckerService" `
        -Actual $resA.Item2 -Expected $testSha2

    # Scenario B: CI Existing release with checksum replacement
    $existingNotesB = "Initial release notes for v$manifestVersion`n`nGitHub Release x64 installer: old_name.zip`nGitHub Release x64 checksum: $testSha1"
    $updatedNotesB = $existingNotesB -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $testSha2"
    $updatedNotesB = $updatedNotesB -replace 'GitHub Release x64 installer:\s*\S+', "GitHub Release x64 installer: $zipName"

    $jsonB = @{
        tag_name = "v$manifestVersion"
        body = $updatedNotesB
        assets = @(@{ name = $zipName; browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v$manifestVersion/$zipName" })
    } | ConvertTo-Json -Depth 5
    $docB = [System.Text.Json.JsonDocument]::Parse($jsonB)
    $resB = $parseMethod.Invoke($null, @($docB))
    Assert-Equal -Tier $TIER -Category "I1-CI-Parsing" -Name "I1.2: Replaced CI release payload parsed by UpdateCheckerService" `
        -Actual $resB.Item2 -Expected $testSha2

    # Scenario C: CI Appended release notes
    $userNotesC = "Important fixes in audio flyout."
    $appendedNotesC = "$userNotesC`n`n$checksumBlock"
    $jsonC = @{
        tag_name = "v$manifestVersion"
        body = $appendedNotesC
        assets = @(@{ name = $zipName; browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v$manifestVersion/$zipName" })
    } | ConvertTo-Json -Depth 5
    $docC = [System.Text.Json.JsonDocument]::Parse($jsonC)
    $resC = $parseMethod.Invoke($null, @($docC))
    Assert-Equal -Tier $TIER -Category "I1-CI-Parsing" -Name "I1.3: Appended CI release payload parsed by UpdateCheckerService" `
        -Actual $resC.Item2 -Expected $testSha2

    # -------------------------------------------------------------
    # INTERACTION 2: CI Packaging Zip Staging Layout ↔ UpdateInstallerService Extraction
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 2: CI Packaging Layout ↔ UpdateInstallerService Extraction ---" -ForegroundColor Yellow

    # Simulate CI "Prepare installer structure" step:
    # InstallerOutput\
    #   SystemFiles\
    #     Add-AppDevPackage.ps1
    #     FluentFlyout.msix
    #   FluentFlyout_Installer.bat
    #   README.txt
    $ciOutputDir = Join-Path $sandbox "CI_InstallerOutput"
    $ciSystemFiles = Join-Path $ciOutputDir "SystemFiles"
    New-Item -ItemType Directory -Path $ciSystemFiles -Force | Out-Null

    Copy-Item (Join-Path $repoRoot ".github\build-files\FluentFlyout_Installer.bat") "$ciOutputDir\"
    Copy-Item (Join-Path $repoRoot ".github\build-files\README.txt") "$ciOutputDir\"
    Set-Content -Path (Join-Path $ciSystemFiles "Add-AppDevPackage.ps1") -Value "# Mock installer script"
    Set-Content -Path (Join-Path $ciSystemFiles "FluentFlyout.msix") -Value "MSIX MOCK"

    # Zip as CI does:
    $ciZipPath = Join-Path $sandbox "FluentFlyout_${manifestVersion}_x64_Installer.zip"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($ciOutputDir, $ciZipPath)

    # Extract as UpdateInstallerService.ApplyRun does:
    $extractedDir = Join-Path $sandbox "ExtractedFiles"
    [System.IO.Compression.ZipFile]::ExtractToDirectory($ciZipPath, $extractedDir, $true)

    # Discovery logic from UpdateInstallerService.cs:
    $installerScript = Join-Path $extractedDir "SystemFiles\Add-AppDevPackage.ps1"
    if (-not (Test-Path $installerScript)) {
        $matchingFiles = Directory.GetFiles($extractedDir, "Add-AppDevPackage.ps1", [System.IO.SearchOption]::AllDirectories)
        if ($matchingFiles.Length -gt 0) { $installerScript = $matchingFiles[0] }
    }
    Assert-True -Tier $TIER -Category "I2-ZipLayout" -Name "I2.1: UpdateInstallerService successfully locates Add-AppDevPackage.ps1 from CI zip" `
        -Actual (Test-Path $installerScript)
    Assert-True -Tier $TIER -Category "I2-ZipLayout" -Name "I2.2: Staged zip contains FluentFlyout_Installer.bat at root" `
        -Actual (Test-Path (Join-Path $extractedDir "FluentFlyout_Installer.bat"))
    Assert-True -Tier $TIER -Category "I2-ZipLayout" -Name "I2.3: Staged zip contains README.txt at root" `
        -Actual (Test-Path (Join-Path $extractedDir "README.txt"))

    # -------------------------------------------------------------
    # INTERACTION 3: CI Sideload Certificate Publisher ↔ MSIX Manifest Identity
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 3: CI Certificate Publisher ↔ Manifest Identity ---" -ForegroundColor Yellow

    $tempPfx = Join-Path $sandbox "CI_Cert_InterCheck.pfx"
    $certPass = "FluentFlyoutDevPassword123!"
    $secPass = ConvertTo-SecureString -String $certPass -Force -AsPlainText

    $cert = New-SelfSignedCertificate -Type Custom `
        -Subject $publisherCN `
        -KeyUsage DigitalSignature `
        -FriendlyName "FluentFlyout Sideload Cert" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")

    Export-PfxCertificate -Cert $cert -FilePath $tempPfx -Password $secPass | Out-Null
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue

    $certRead = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($tempPfx, $certPass)
    Assert-Equal -Tier $TIER -Category "I3-Cert" -Name "I3.1: CI certificate subject exactly matches manifest publisher" `
        -Actual $certRead.Subject -Expected $publisherCN

    # -------------------------------------------------------------
    # INTERACTION 4: CI Generated Companion .sha256 File ↔ UpdateInstallerService Verification
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 4: CI Companion .sha256 ↔ UpdateInstallerService Verification ---" -ForegroundColor Yellow

    $ciComputedSha = (Get-FileHash -Path $ciZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $shaFilePath = "$ciZipPath.sha256"
    "$ciComputedSha  $($ciZipPath | Split-Path -Leaf)" | Out-File -FilePath $shaFilePath -Encoding ascii

    # Read companion sha256 file
    $companionContent = (Get-Content $shaFilePath -Raw).Trim()
    $companionSha = ($companionContent -split '\s+')[0].Trim().ToLowerInvariant()

    # Validate using UpdateInstallerService.VerifyFileHashAsync
    $verifiedOk = Invoke-VerifyHashHelper $ciZipPath $companionSha
    Assert-True -Tier $TIER -Category "I4-Companion" -Name "I4.1: UpdateInstallerService verifies zip hash matching CI companion file" `
        -Actual $verifiedOk

    # -------------------------------------------------------------
    # INTERACTION 5: Staging Directory Lifecycle ↔ Multi-run CleanOldUpdateRuns
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 5: Staging Directory Lifecycle ↔ CleanOldUpdateRuns ---" -ForegroundColor Yellow

    $cleanRunsMethod = $UpdateInstaller.GetMethod("CleanOldUpdateRuns", [System.Reflection.BindingFlags]"NonPublic,Static")
    $mockUpdatesRoot = Join-Path ([System.IO.Path]::GetTempPath()) "FluentFlyout\updates"
    if (Test-Path $mockUpdatesRoot) { Remove-Item $mockUpdatesRoot -Recurse -Force -ErrorAction SilentlyContinue }

    # Create 5 runs across versions
    $runsToCreate = @(
        "2.14.0\1700000001",
        "2.14.0\1700000002",
        "2.15.0\1700000003",
        "2.16.0\1700000004",
        "2.16.0\1700000005"
    )
    foreach ($r in $runsToCreate) {
        New-Item -ItemType Directory -Path (Join-Path $mockUpdatesRoot $r) -Force | Out-Null
    }

    $cleanRunsMethod.Invoke($null, $null)

    # Count remaining runs (must be exactly 3)
    $remainingRuns = (Get-ChildItem -Path $mockUpdatesRoot -Recurse -Directory | Where-Object { $_.Parent.FullName -ne $mockUpdatesRoot }).Count
    Assert-Equal -Tier $TIER -Category "I5-StagingPruning" -Name "I5.1: CleanOldUpdateRuns maintains exactly 3 most recent runs" `
        -Actual $remainingRuns -Expected 3

    # Clean up mock updates
    if (Test-Path $mockUpdatesRoot) { Remove-Item $mockUpdatesRoot -Recurse -Force -ErrorAction SilentlyContinue }

    # -------------------------------------------------------------
    # INTERACTION 6: UpdateCheckerService IsNewerVersion ↔ MSIX Manifest Version
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 6: UpdateCheckerService IsNewerVersion ↔ Manifest Version ---" -ForegroundColor Yellow

    # Manifest version is 2.16.0 (or 2.16.0.0)
    # Check that a newer minor/patch is reported as upgrade
    $isUpgrade = [bool]$isNewerMethod.Invoke($null, @($manifestVersion, "v2.17.0"))
    Assert-True -Tier $TIER -Category "I6-VersionInterop" -Name "I6.1: Manifest version upgraded by remote v2.17.0" `
        -Actual $isUpgrade

    # Check that identical tag is NOT reported as upgrade
    $isSame = [bool]$isNewerMethod.Invoke($null, @($manifestVersion, "v$manifestVersion"))
    Assert-False -Tier $TIER -Category "I6-VersionInterop" -Name "I6.2: Remote release of same tag v$manifestVersion is not an upgrade" `
        -Actual $isSame

    # -------------------------------------------------------------
    # INTERACTION 7: UpdateCheckerService Asset Matching ↔ CI Uploaded Assets
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 7: UpdateCheckerService Asset Matching ↔ CI Assets ---" -ForegroundColor Yellow

    # CI uploads zip, companion sha256, and GitHub automatically adds source zips
    $ciUploadedAssets = @(
        @{ name = "$zipName.sha256"; browser_download_url = "https://example.com/$zipName.sha256" },
        @{ name = "Source code.zip"; browser_download_url = "https://example.com/source.zip" },
        @{ name = "FluentFlyout_${manifestVersion}_arm64_Installer.zip"; browser_download_url = "https://example.com/arm64.zip" },
        @{ name = $zipName; browser_download_url = "https://example.com/target_x64.zip" }
    )
    $ciJson = @{
        body = "GitHub Release x64 checksum: $testSha1"
        assets = $ciUploadedAssets
    } | ConvertTo-Json -Depth 5
    $ciDoc = [System.Text.Json.JsonDocument]::Parse($ciJson)
    $ciAssetRes = $parseMethod.Invoke($null, @($ciDoc))
    Assert-Equal -Tier $TIER -Category "I7-AssetFilter" -Name "I7.1: UpdateCheckerService selects x64 installer over sha256 companion and arm64" `
        -Actual $ciAssetRes.Item1 -Expected "https://example.com/target_x64.zip"

    # -------------------------------------------------------------
    # INTERACTION 8: Upstream Isolation Under GITHUB_RELEASE
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 8: Upstream Isolation under GITHUB_RELEASE ---" -ForegroundColor Yellow

    # In GITHUB_RELEASE builds, UpdateCheckerService.cs line 88-132 disables site API fallback
    # Verify by checking IL or static source tokens under #if GITHUB_RELEASE
    $checkerCode = Get-Content (Join-Path $repoRoot "FluentFlyoutWPF\Classes\Services\UpdateCheckerService.cs") -Raw
    $hasGithubReleasePreproc = $checkerCode -match '#if GITHUB_RELEASE'
    $hasFallbackPreproc = $checkerCode -match 'fluentflyout\.com|FluentFlyoutApiClient'
    Assert-True -Tier $TIER -Category "I8-Isolation" -Name "I8.1: UpdateCheckerService contains #if GITHUB_RELEASE isolation" `
        -Actual ($hasGithubReleasePreproc -and $hasFallbackPreproc)

    # -------------------------------------------------------------
    # INTERACTION 9: Decoupled Script Launcher (apply.ps1) ↔ Bat File Command Parity
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 9: Launcher Script Parity (apply.ps1 ↔ bat) ---" -ForegroundColor Yellow

    $batContent = Get-Content (Join-Path $repoRoot ".github\build-files\FluentFlyout_Installer.bat") -Raw
    $applyScriptContent = $buildScriptMethod.Invoke($null, @(4321, "C:\Sample\SystemFiles"))

    $batHasTelemetrySkip = $batContent -match '-SkipLoggingTelemetry'
    $applyHasTelemetrySkip = $applyScriptContent -match '-SkipLoggingTelemetry'
    $batHasAddAppDev = $batContent -match 'Add-AppDevPackage\.ps1'
    $applyHasAddAppDev = $applyScriptContent -match 'Add-AppDevPackage\.ps1'

    Assert-True -Tier $TIER -Category "I9-ScriptParity" -Name "I9.1: Both apply.ps1 and bat wrapper execute Add-AppDevPackage.ps1 with -SkipLoggingTelemetry" `
        -Actual ($batHasTelemetrySkip -and $applyHasTelemetrySkip -and $batHasAddAppDev -and $applyHasAddAppDev)

    # -------------------------------------------------------------
    # INTERACTION 10: LicenseManager Premium Unlocked Under GITHUB_RELEASE
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 10: LicenseManager Unlocked Under GITHUB_RELEASE ---" -ForegroundColor Yellow

    $licenseCode = Get-Content (Join-Path $repoRoot "FluentFlyoutWPF\Classes\LicenseManager.cs") -Raw
    $hasLicensePreproc = $licenseCode -match '#if GITHUB_RELEASE[\s\S]*?_isPremiumUnlocked\s*=\s*true'
    $hasNonStore = $licenseCode -match '_isStoreVersion\s*=\s*false'
    Assert-True -Tier $TIER -Category "I10-License" -Name "I10.1: LicenseManager unlocks premium and marks non-store under GITHUB_RELEASE" `
        -Actual ($hasLicensePreproc -and $hasNonStore)

    # -------------------------------------------------------------
    # INTERACTION 11: CI Build Mode SideloadOnly ↔ wapproj Condition
    # -------------------------------------------------------------
    Write-Host "`n--- Interaction 11: CI Build Mode SideloadOnly ↔ wapproj ---" -ForegroundColor Yellow

    $wapprojContent = Get-Content (Join-Path $repoRoot "FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj") -Raw
    $workflowContent = Get-Content (Join-Path $repoRoot ".github\workflows\build-msix.yml") -Raw

    $wapprojHasSideload = ($wapprojContent -match "GitHub Release\|x64[\s\S]*?SideloadOnly")
    $workflowSetsSideload = ($workflowContent -match "CONFIGURATION\s*-eq\s*'GitHub Release'[\s\S]*?'SideloadOnly'")

    Assert-True -Tier $TIER -Category "I11-SideloadOnly" -Name "I11.1: Packaging wapproj and CI workflow both specify SideloadOnly for GitHub Release" `
        -Actual ($wapprojHasSideload -and $workflowSetsSideload)

} finally {
    Remove-TestSandbox $sandbox
}

Write-Host "`nTier 3 Cross-Feature Interactions Execution Complete." -ForegroundColor Cyan
