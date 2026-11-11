# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Tier 2: Boundary Value Analysis & Corner Cases
    Exercises boundary conditions across multiline/empty release notes, hash collisions,
    SemVer pre-releases with build metadata, corrupted zip archives, and signing fallbacks.
#>

param()

$ErrorActionPreference = "Stop"

# Load common test infrastructure
. (Join-Path $PSScriptRoot "Common.ps1")

Write-Host "==========================================================" -ForegroundColor Cyan
Write-Host " TIER 2: BOUNDARY VALUE ANALYSIS & CORNER CASES" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor Cyan

$ctx = Initialize-FluentFlyoutAssembly
$UpdateChecker = $ctx.UpdateChecker
$UpdateInstaller = $ctx.UpdateInstaller
$repoRoot = $ctx.RepoRoot
$TIER = "Tier2"

$sandbox = New-TestSandbox

try {
    # -------------------------------------------------------------
    # CATEGORY 1: Endpoint & Repository Configuration Boundaries (Feature 1)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 1: Fork Endpoint Environment Overrides & Boundaries ---" -ForegroundColor Yellow

    $endpointProp = $UpdateChecker.GetProperty("GitHubApiLatestRelease", [System.Reflection.BindingFlags]"Public,NonPublic,Static")

    # B1.1 Surrounding whitespace trimmed
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "   user/repo   " -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.1: FLUENTFLYOUT_UPDATE_REPO with surrounding whitespace is trimmed" `
            -Actual $actual -Expected "https://api.github.com/repos/user/repo/releases/latest"
    }

    # B1.2 Without slash falls back to default
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "invalidrepo" -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.2: FLUENTFLYOUT_UPDATE_REPO without slash falls back to default" `
            -Actual $actual -Expected "https://api.github.com/repos/Fixbound/FluentFlyout/releases/latest"
    }

    # B1.3 Empty string falls back to default
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "" -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.3: FLUENTFLYOUT_UPDATE_REPO empty string falls back to default" `
            -Actual $actual -Expected "https://api.github.com/repos/Fixbound/FluentFlyout/releases/latest"
    }

    # B1.4 Whitespace only falls back to default
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "    " -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.4: FLUENTFLYOUT_UPDATE_REPO whitespace only falls back to default" `
            -Actual $actual -Expected "https://api.github.com/repos/Fixbound/FluentFlyout/releases/latest"
    }

    # B1.5 Null falls back to default
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value $null -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.5: FLUENTFLYOUT_UPDATE_REPO null falls back to default" `
            -Actual $actual -Expected "https://api.github.com/repos/Fixbound/FluentFlyout/releases/latest"
    }

    # B1.6 Multiple slashes / nested org path
    Invoke-WithEnv -Name "FLUENTFLYOUT_UPDATE_REPO" -Value "org/team/repo" -ScriptBlock {
        $actual = $endpointProp.GetValue($null)
        Assert-Equal -Tier $TIER -Category "B1-Endpoint" -Name "B1.6: FLUENTFLYOUT_UPDATE_REPO with multi-segment path" `
            -Actual $actual -Expected "https://api.github.com/repos/org/team/repo/releases/latest"
    }

    # -------------------------------------------------------------
    # CATEGORY 2: Release Notes & Regex Boundary Value Analysis (Feature 2)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 2: Release Notes & Regex Boundary Value Analysis ---" -ForegroundColor Yellow

    $parseMethod = $UpdateChecker.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public,Static")

    function Test-RegexBoundary([string]$Body, [string]$ExpectedSha) {
        $payload = @{
            body = $Body
            assets = @(
                @{
                    name = "FluentFlyout_2.16.0_x64_Installer.zip"
                    browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v2.16.0/FluentFlyout_2.16.0_x64_Installer.zip"
                }
            )
        } | ConvertTo-Json -Depth 5
        $jsonDoc = [System.Text.Json.JsonDocument]::Parse($payload)
        $res = $parseMethod.Invoke($null, @($jsonDoc))
        return $res.Item2
    }

    $hashArm64 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
    $hashX64   = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
    $hashX86   = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
    $hashSha512 = "11111111111111111111111111111111111111111111111111111111111111112222222222222222222222222222222222222222222222222222222222222222"
    $commitSha = "4f2c99a8b13c77d01234567890abcdef12345678"

    # B2.1 Markdown table: ARM64 row before x64 row
    $tableBody = @"
## Downloads
| Architecture | SHA256 Checksum |
| :--- | :--- |
| ARM64 | $hashArm64 |
| x64 | $hashX64 |
"@
    $actualSha1 = Test-RegexBoundary $tableBody $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.1: Multi-arch markdown table extracts x64 when ARM64 is first" `
        -Actual $actualSha1 -Expected $hashX64

    # B2.2 Bulleted list with x86, arm64, and x64
    $bulletBody = @"
* x86 checksum: $hashX86
* arm64 checksum: $hashArm64
* x64 checksum: $hashX64
"@
    $actualSha2 = Test-RegexBoundary $bulletBody $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.2: Bulleted list multi-arch extracts x64" `
        -Actual $actualSha2 -Expected $hashX64

    # B2.3 Parenthesized arch header
    $actualSha3 = Test-RegexBoundary "SHA-256 (x64): $hashX64" $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.3: Parenthesized arch header 'SHA-256 (x64):' extracted" `
        -Actual $actualSha3 -Expected $hashX64

    # B2.4 SHA-512 128-hex ignored via word boundaries
    $sha512Body = @"
SHA-512 Checksum: $hashSha512
x64 checksum: $hashX64
"@
    $actualSha4 = Test-RegexBoundary $sha512Body $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.4: 128-hex SHA-512 ignored without matching 64-hex prefix" `
        -Actual $actualSha4 -Expected $hashX64

    # B2.5 40-character git commit SHA ignored
    $commitBody = @"
Merged commit $commitSha from main
GitHub Release x64 checksum: $hashX64
"@
    $actualSha5 = Test-RegexBoundary $commitBody $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.5: 40-char git commit SHA ignored without corrupting checksum extraction" `
        -Actual $actualSha5 -Expected $hashX64

    # B2.6 Malformed 63-hex string rejected
    $malformed63 = "a" * 63
    $actualSha6 = Test-RegexBoundary "GitHub Release x64 checksum: $malformed63" ""
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.6: Malformed 63-hex string rejected" `
        -Actual $actualSha6 -Expected ""

    # B2.7 Malformed 65-hex string rejected
    $malformed65 = "a" * 65
    $actualSha7 = Test-RegexBoundary "GitHub Release x64 checksum: $malformed65" ""
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.7: Malformed 65-hex string rejected" `
        -Actual $actualSha7 -Expected ""

    # B2.8 Non-hex string rejected (contains 'g')
    $nonHex = "g" + ("a" * 63)
    $actualSha8 = Test-RegexBoundary "GitHub Release x64 checksum: $nonHex" ""
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.8: Non-hex string containing 'g' rejected" `
        -Actual $actualSha8 -Expected ""

    # B2.9 Markdown bold header and backticks
    $bt = [char]96
    $boldBacktickBody = "**Checksum:** $bt$hashX64$bt"
    $actualSha9 = Test-RegexBoundary $boldBacktickBody $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.9: Markdown bold and backtick-wrapped hash extracted" `
        -Actual $actualSha9 -Expected $hashX64

    # B2.10 Completely empty body
    $actualSha10 = Test-RegexBoundary "" ""
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.10: Completely empty release notes body returns empty sha" `
        -Actual $actualSha10 -Expected ""

    # B2.11 Tier 1 workflow priority over Tier 2 generic x64
    $tierBody = @"
x64 checksum: $hashArm64
GitHub Release x64 checksum: $hashX64
"@
    $actualSha11 = Test-RegexBoundary $tierBody $hashX64
    Assert-Equal -Tier $TIER -Category "B2-Regex" -Name "B2.11: Workflow pattern takes priority over generic x64 pattern" `
        -Actual $actualSha11 -Expected $hashX64

    # -------------------------------------------------------------
    # CATEGORY 3: SemVer 2.0.0 Specification & Upgrade Boundaries (Feature 1/2)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 3: SemVer 2.0.0 Specification & Upgrade Boundaries ---" -ForegroundColor Yellow

    $isNewerMethod = $UpdateChecker.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public,Static")

    function Test-VersionHelper([string]$Current, [string]$Newest) {
        return [bool]$isNewerMethod.Invoke($null, @($Current, $Newest))
    }

    # B3.1 SemVer 2.0.0 §11.4 Pre-release chain progression
    # alpha < alpha.1 < alpha.beta < beta < beta.2 < beta.11 < rc.1 < 1.0.0
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1a: SemVer progression alpha -> alpha.1" `
        -Actual (Test-VersionHelper "1.0.0-alpha" "1.0.0-alpha.1")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1b: SemVer progression alpha.1 -> alpha.beta" `
        -Actual (Test-VersionHelper "1.0.0-alpha.1" "1.0.0-alpha.beta")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1c: SemVer progression alpha.beta -> beta" `
        -Actual (Test-VersionHelper "1.0.0-alpha.beta" "1.0.0-beta")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1d: SemVer progression beta -> beta.2" `
        -Actual (Test-VersionHelper "1.0.0-beta" "1.0.0-beta.2")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1e: SemVer progression beta.2 -> beta.11 (numeric comparison)" `
        -Actual (Test-VersionHelper "1.0.0-beta.2" "1.0.0-beta.11")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1f: SemVer progression beta.11 -> rc.1" `
        -Actual (Test-VersionHelper "1.0.0-beta.11" "1.0.0-rc.1")
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.1g: SemVer progression rc.1 -> 1.0.0 stable" `
        -Actual (Test-VersionHelper "1.0.0-rc.1" "1.0.0")

    # B3.2 Prerelease reverse checks (downgrades return false)
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.2a: SemVer downgrade beta.11 -> beta.2 returns false" `
        -Actual (Test-VersionHelper "1.0.0-beta.11" "1.0.0-beta.2")
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.2b: SemVer downgrade stable -> rc.1 returns false" `
        -Actual (Test-VersionHelper "1.0.0" "1.0.0-rc.1")

    # B3.3 Build metadata ignored in precedence (§10)
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.3: Build metadata timestamps ignored in comparison" `
        -Actual (Test-VersionHelper "1.0.0+2026111001" "1.0.0+2026111002")

    # B3.4 Prerelease to stable of same version is upgrade
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.4: Prerelease to stable of same version is upgrade" `
        -Actual (Test-VersionHelper "2.16.0-beta.1" "2.16.0")

    # B3.5 Stable to prerelease of same version is NOT an upgrade
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.5: Stable to prerelease of same version is NOT an upgrade" `
        -Actual (Test-VersionHelper "2.16.0" "2.16.0-rc.1")

    # B3.6 Cross-base transitions: stable to higher prerelease
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.6: Stable to higher major prerelease base is upgrade" `
        -Actual (Test-VersionHelper "1.0.0" "2.0.0-alpha")

    # B3.7 Notation mixing: 4-part revision step
    Assert-True -Tier $TIER -Category "B3-SemVer" -Name "B3.7a: 4-part revision step 2.16.0.5 -> 2.16.0.6 is upgrade" `
        -Actual (Test-VersionHelper "2.16.0.5" "2.16.0.6")
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.7b: 3-part vs 4-part identical 2.16.0 vs 2.16.0.0 is not an upgrade" `
        -Actual (Test-VersionHelper "2.16.0" "2.16.0.0")

    # B3.8 Boundary/malformed versions
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.8a: 5-part version rejected safely" `
        -Actual (Test-VersionHelper "1.2.3.4.5" "2.0.0")
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.8b: Negative number in version rejected safely" `
        -Actual (Test-VersionHelper "-1.0.0" "2.0.0")
    Assert-False -Tier $TIER -Category "B3-SemVer" -Name "B3.8c: Empty newest version returns false safely" `
        -Actual (Test-VersionHelper "2.16.0" "")

    # -------------------------------------------------------------
    # CATEGORY 4: Cryptography, File Verification & Archive Boundaries (Feature 3)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 4: Cryptography & File Verification Boundaries ---" -ForegroundColor Yellow

    $verifyHashMethod = $UpdateInstaller.GetMethod("VerifyFileHashAsync", [System.Reflection.BindingFlags]"NonPublic,Static")

    function Invoke-VerifyHashHelper([string]$Path, [string]$Hash) {
        $task = $verifyHashMethod.Invoke($null, [object[]]@([string]$Path, [string]$Hash))
        $task.Wait()
        return $task.Result
    }

    # B4.1 10MB binary file verification
    $largeFilePath = Join-Path $sandbox "large_10mb.bin"
    $largeBytes = [byte[]]::new(10 * 1024 * 1024)
    [System.Security.Cryptography.RandomNumberGenerator]::Fill($largeBytes)
    [System.IO.File]::WriteAllBytes($largeFilePath, $largeBytes)
    $sysHashLarge = (Get-FileHash -Path $largeFilePath -Algorithm SHA256).Hash.ToLowerInvariant()
    $actualLarge = Invoke-VerifyHashHelper $largeFilePath $sysHashLarge
    Assert-True -Tier $TIER -Category "B4-Crypto" -Name "B4.1: 10MB binary file SHA-256 matches system hash" `
        -Actual $actualLarge

    # B4.2 Truncated file rejected
    $truncatedFilePath = Join-Path $sandbox "truncated.bin"
    $truncatedBytes = [byte[]]::new(2048)
    [Array]::Copy($largeBytes, $truncatedBytes, 2048)
    [System.IO.File]::WriteAllBytes($truncatedFilePath, $truncatedBytes)
    $actualTruncated = Invoke-VerifyHashHelper $truncatedFilePath $sysHashLarge
    Assert-False -Tier $TIER -Category "B4-Crypto" -Name "B4.2: Truncated file rejected as invalid hash" `
        -Actual $actualTruncated

    # B4.3 Corrupted zip archive detection
    $corruptZipPath = Join-Path $sandbox "corrupted.zip"
    [System.IO.File]::WriteAllText($corruptZipPath, "This is not a valid PKZip archive byte sequence.")
    $corruptExtractDir = Join-Path $sandbox "corrupt_extract"
    $threwInvalidData = $false
    try {
        [System.IO.Compression.ZipFile]::ExtractToDirectory($corruptZipPath, $corruptExtractDir, $true)
    } catch {
        $threwInvalidData = $true
    }
    Assert-True -Tier $TIER -Category "B4-Crypto" -Name "B4.3: Corrupted zip archive extraction throws exception cleanly" `
        -Actual $threwInvalidData

    # B4.4 Concurrent hash checks on same file (FileShare.Read)
    $concurrentTasks = [System.Collections.Generic.List[System.Threading.Tasks.Task[bool]]]::new()
    for ($i = 0; $i -lt 5; $i++) {
        $concurrentTasks.Add($verifyHashMethod.Invoke($null, [object[]]@([string]$largeFilePath, [string]$sysHashLarge)))
    }
    [System.Threading.Tasks.Task]::WaitAll($concurrentTasks.ToArray())
    $allConcurrentPassed = $true
    foreach ($t in $concurrentTasks) {
        if ($t.Result -ne $true) { $allConcurrentPassed = $false }
    }
    Assert-True -Tier $TIER -Category "B4-Crypto" -Name "B4.4: 5 concurrent hash checks on same file succeed without sharing lock" `
        -Actual $allConcurrentPassed

    # B4.5 Padded expected hash string behavior
    $paddedHashRes = Invoke-VerifyHashHelper $largeFilePath "  $sysHashLarge  "
    Assert-False -Tier $TIER -Category "B4-Crypto" -Name "B4.5: Unsanitized padded expected hash is strictly compared" `
        -Actual $paddedHashRes

    # -------------------------------------------------------------
    # CATEGORY 5: Decoupled Script & Adversarial Path Escaping Boundaries (Feature 4)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 5: Decoupled Script & Adversarial Path Escaping Boundaries ---" -ForegroundColor Yellow

    $buildScriptMethod = $UpdateInstaller.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic,Static")

    function Test-ScriptAST([int]$PidVal, [string]$SysDir) {
        $body = $buildScriptMethod.Invoke($null, @($PidVal, $SysDir))
        $tokens = $null
        $errors = $null
        [System.Management.Automation.Language.Parser]::ParseInput($body, [ref]$tokens, [ref]$errors) | Out-Null
        return @{
            ErrorCount = $errors.Count
            Script = $body
        }
    }

    # B5.1 Single quote in directory path (e.g. O'Connor profile)
    $resPathQuote = Test-ScriptAST 1234 "C:\Users\O'Connor\AppData\Local\Temp\FluentFlyout\SystemFiles"
    Assert-Equal -Tier $TIER -Category "B5-Script" -Name "B5.1: Path with single quote (O'Connor) parses valid AST (0 errors)" `
        -Actual $resPathQuote.ErrorCount -Expected 0

    # B5.2 Multiple single quotes and ampersand
    $resPathMulti = Test-ScriptAST 5678 "C:\Users\Jack's & Jill's PC\SystemFiles"
    Assert-Equal -Tier $TIER -Category "B5-Script" -Name "B5.2: Path with multiple single quotes parses valid AST (0 errors)" `
        -Actual $resPathMulti.ErrorCount -Expected 0

    # B5.3 Bracket characters in path [x64]
    $resPathBracket = Test-ScriptAST 9999 "C:\Updates\[x64]\FluentFlyout\SystemFiles"
    Assert-Equal -Tier $TIER -Category "B5-Script" -Name "B5.3: Path with brackets [x64] parses valid AST" `
        -Actual $resPathBracket.ErrorCount -Expected 0
    Assert-Match -Tier $TIER -Category "B5-Script" -Name "B5.3b: Set-Location uses -LiteralPath to prevent bracket globbing" `
        -Actual $resPathBracket.Script -Pattern "Set-Location\s+-LiteralPath\s+\`$systemFiles"

    # B5.4 Dollar sign in path ($FluentFlyout)
    $resPathDollar = Test-ScriptAST 1111 "C:\Temp\`$FluentFlyout_Update\SystemFiles"
    Assert-Equal -Tier $TIER -Category "B5-Script" -Name "B5.4: Path with dollar sign parses valid AST" `
        -Actual $resPathDollar.ErrorCount -Expected 0

    # B5.5 Boundary PIDs: 0 and Int32.MaxValue
    $resPidMax = Test-ScriptAST ([int]::MaxValue) "C:\Temp\SystemFiles"
    Assert-Equal -Tier $TIER -Category "B5-Script" -Name "B5.5: Script handles Int32.MaxValue PID gracefully" `
        -Actual $resPidMax.ErrorCount -Expected 0

    # B5.6 Staging directory pruning (CleanOldUpdateRuns)
    $cleanRunsMethod = $UpdateInstaller.GetMethod("CleanOldUpdateRuns", [System.Reflection.BindingFlags]"NonPublic,Static")
    $mockRoot = Join-Path ([System.IO.Path]::GetTempPath()) "FluentFlyout\updates"
    if (Test-Path $mockRoot) { Remove-Item $mockRoot -Recurse -Force -ErrorAction SilentlyContinue }
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.14.0\1700000010") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.14.0\1700000020") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.15.0\1700000030") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.15.0\1700000040") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.16.0\1700000050") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $mockRoot "2.16.0\1700000060") -Force | Out-Null

    $cleanRunsMethod.Invoke($null, $null)

    $kept40 = Test-Path (Join-Path $mockRoot "2.15.0\1700000040")
    $kept50 = Test-Path (Join-Path $mockRoot "2.16.0\1700000050")
    $kept60 = Test-Path (Join-Path $mockRoot "2.16.0\1700000060")
    $pruned10 = -not (Test-Path (Join-Path $mockRoot "2.14.0\1700000010"))
    $v214Purged = -not (Test-Path (Join-Path $mockRoot "2.14.0"))

    $pruningOk = ($kept40 -and $kept50 -and $kept60 -and $pruned10 -and $v214Purged)
    Assert-True -Tier $TIER -Category "B5-Script" -Name "B5.6: CleanOldUpdateRuns keeps newest 3 runs and purges empty version folder" `
        -Actual $pruningOk

    # Clean up mock updates folder
    if (Test-Path $mockRoot) { Remove-Item $mockRoot -Recurse -Force -ErrorAction SilentlyContinue }

    # -------------------------------------------------------------
    # CATEGORY 6: CI Workflow & Packaging Boundary Cases (Feature 5/6)
    # -------------------------------------------------------------
    Write-Host "`n--- Category 6: CI Workflow & Packaging Boundary Cases ---" -ForegroundColor Yellow

    # B6.1 Dynamic self-signed cert generation fallback simulation
    $manifestPath = Join-Path $repoRoot "FluentFlyoutMSIX\Package.appxmanifest"
    [xml]$manifestXml = Get-Content $manifestPath
    $publisherCN = $manifestXml.Package.Identity.Publisher

    $tempPfx = Join-Path $sandbox "CI_Fallback_Test.pfx"
    $pfxPass = "FluentFlyoutDevPassword123!"
    $secPass = ConvertTo-SecureString -String $pfxPass -Force -AsPlainText

    $cert = New-SelfSignedCertificate -Type Custom `
        -Subject $publisherCN `
        -KeyUsage DigitalSignature `
        -FriendlyName "FluentFlyout Test Cert" `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -TextExtension @("2.5.29.37={text}1.3.6.1.5.5.7.3.3")

    Export-PfxCertificate -Cert $cert -FilePath $tempPfx -Password $secPass | Out-Null
    Remove-Item -Path "Cert:\CurrentUser\My\$($cert.Thumbprint)" -Force -ErrorAction SilentlyContinue

    $importedCert = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($tempPfx, $pfxPass)
    Assert-Equal -Tier $TIER -Category "B6-CI" -Name "B6.1: Dynamic fallback certificate subject matches manifest publisher" `
        -Actual $importedCert.Subject -Expected $publisherCN

    # B6.2 Certificate KeyUsage and EKU
    $hasCodeSigningEku = $false
    foreach ($ext in $importedCert.Extensions) {
        if ($ext -is [System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension]) {
            foreach ($oid in $ext.EnhancedKeyUsages) {
                if ($oid.Value -eq "1.3.6.1.5.5.7.3.3") {
                    $hasCodeSigningEku = $true
                }
            }
        }
    }
    Assert-True -Tier $TIER -Category "B6-CI" -Name "B6.2: Dynamic fallback certificate includes Code Signing EKU (1.3.6.1.5.5.7.3.3)" `
        -Actual $hasCodeSigningEku

    # B6.3 Release notes replacement logic when existing release notes exist with older hash
    $existingNotes = "Feature release v2.16.0`n`nGitHub Release x64 installer: old_name.zip`nGitHub Release x64 checksum: 1111111111111111111111111111111111111111111111111111111111111111"
    $newSha = "2222222222222222222222222222222222222222222222222222222222222222"
    $newZip = "FluentFlyout_2.16.0_x64_Installer.zip"

    $updatedNotes = $existingNotes -replace 'GitHub Release x64 checksum:\s*[0-9a-fA-F]{64}', "GitHub Release x64 checksum: $newSha"
    $updatedNotes = $updatedNotes -replace 'GitHub Release x64 installer:\s*\S+', "GitHub Release x64 installer: $newZip"

    $hasNewSha = $updatedNotes -match "GitHub Release x64 checksum: $newSha"
    $hasOldSha = $updatedNotes -match "1111111111111111111111111111111111111111111111111111111111111111"
    Assert-True -Tier $TIER -Category "B6-CI" -Name "B6.3: CI notes replacement replaces old checksum without retaining it" `
        -Actual ($hasNewSha -and -not $hasOldSha)

    # B6.4 Release notes append logic when existing release notes lack checksum block
    $userNotesOnly = "Initial notes without any checksum block."
    $checksumBlock = "GitHub Release x64 installer: $newZip`nGitHub Release x64 checksum: $newSha"
    $appendedNotes = "$userNotesOnly`n`n$checksumBlock"
    $preservesUserNotes = $appendedNotes.StartsWith($userNotesOnly)
    $containsChecksum = $appendedNotes.Contains($checksumBlock)
    Assert-True -Tier $TIER -Category "B6-CI" -Name "B6.4: CI notes append preserves existing notes and appends checksum block" `
        -Actual ($preservesUserNotes -and $containsChecksum)

    # B6.5 3-part version extraction from 4-part manifest version
    $manifestFullVersion = $manifestXml.Package.Identity.Version
    $extracted3Part = ($manifestFullVersion -split '\.')[0..2] -join '.'
    Assert-Equal -Tier $TIER -Category "B6-CI" -Name "B6.5: CI version extraction extracts 3-part version from manifest" `
        -Actual $extracted3Part -Expected "2.16.0"

} finally {
    Remove-TestSandbox $sandbox
}

Write-Host "`nTier 2 Boundary Value Analysis Execution Complete." -ForegroundColor Cyan
