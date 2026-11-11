# Empirical Adversarial Test Harness for Challenger M1
param()

$ErrorActionPreference = "Stop"

$results = [System.Collections.Generic.List[PSObject]]::new()

function Record-Result {
    param(
        [string]$Category,
        [string]$TestName,
        [string]$Status,
        [string]$Expected,
        [string]$Actual,
        [string]$Details = ""
    )
    $obj = [PSCustomObject]@{
        Category = $Category
        TestName = $TestName
        Status   = $Status
        Expected = $Expected
        Actual   = $Actual
        Details  = $Details
    }
    $results.Add($obj)
    $color = if ($Status -eq "PASS") { "Green" } elseif ($Status -eq "FAIL") { "Red" } else { "Yellow" }
    Write-Host "[$Status] ($Category) ${TestName}: Actual='$Actual' (Expected='$Expected') $Details" -ForegroundColor $color
}

# 1. Load compiled assembly
$assemblyPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"
if (-not (Test-Path -LiteralPath $assemblyPath)) {
    Write-Error "Assembly not found at $assemblyPath"
    exit 1
}

[System.Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null
$UpdateCheckerType = [Type]::GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService, FluentFlyout")
$UpdateInstallerType = [Type]::GetType("FluentFlyoutWPF.Classes.Services.UpdateInstallerService, FluentFlyout")

if ($null -eq $UpdateCheckerType) {
    Write-Error "Could not find UpdateCheckerService type in assembly"
    exit 1
}

Write-Host "=== AREA 1: SHA-256 REGEX EXTRACTION & ASSET PARSING ===" -ForegroundColor Cyan

function Run-ParseTest {
    param(
        [string]$Name,
        [string]$Body,
        [string]$ExpectedSha,
        [string]$ExpectedAssetUrl = "",
        [string]$AssetName = "FluentFlyout_2.16.0_x64_Installer.zip",
        [string]$AssetUrl = "https://github.com/unchihugo/FluentFlyout/releases/download/v2.16.0/FluentFlyout_2.16.0_x64_Installer.zip"
    )

    $jsonObj = @{
        body = $Body
        assets = @(
            @{
                name = $AssetName
                browser_download_url = $AssetUrl
            }
        )
    }
    $jsonStr = $jsonObj | ConvertTo-Json -Depth 5
    $jsonDoc = [System.Text.Json.JsonDocument]::Parse($jsonStr)

    $parseMethod = $UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")
    $res = $parseMethod.Invoke($null, @($jsonDoc))

    $actualAssetUrl = $res.Item1
    $actualSha = $res.Item2

    $shaPass = ($actualSha -eq $ExpectedSha.ToLowerInvariant())
    $urlPass = if ($ExpectedAssetUrl) { $actualAssetUrl -eq $ExpectedAssetUrl } else { $true }

    if ($shaPass -and $urlPass) {
        Record-Result "Regex" $Name "PASS" $ExpectedSha $actualSha "URL: $actualAssetUrl"
    } else {
        Record-Result "Regex" $Name "FAIL" $ExpectedSha $actualSha "URL: Actual='$actualAssetUrl', Expected='$ExpectedAssetUrl'"
    }
}

$sampleHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
$sampleHashUpper = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855"

# R1.1 Standard format from build-msix.yml
Run-ParseTest "Standard workflow format" "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: $sampleHash" $sampleHash

# R1.2 Uppercase standard format
Run-ParseTest "Uppercase hex hash" "GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: $sampleHashUpper" $sampleHash

# R1.3 Alternative sha256 keyword
Run-ParseTest "Keyword sha256" "GitHub Release x64 sha256: $sampleHash" $sampleHash

# R1.4 Short header SHA-256
Run-ParseTest "Header SHA-256:" "SHA-256: $sampleHash" $sampleHash

# R1.5 Short header sha256 (no dash)
Run-ParseTest "Header sha256:" "sha256: $sampleHash" $sampleHash

# R1.6 Generic prefix checksum
Run-ParseTest "Prefix checksum:" "checksum: $sampleHash" $sampleHash

# R1.7 Space separated, no colon
Run-ParseTest "Space separated sha256" "sha256 $sampleHash" $sampleHash

# R1.8 Multi-line noisy notes with commit SHA preceding the checksum
$noisyBody1 = @"
## Release notes for v2.16.0
* Fix bug in flyout positioning
* Merged commit 4f2c99a8b13c77d01234567890abcdef12345678
* Built on Windows Server 2025

GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip
GitHub Release x64 checksum: $sampleHash
Thanks to all contributors!
"@
Run-ParseTest "Noisy body with 40-char git commit SHA" $noisyBody1 $sampleHash

# R1.9 Markdown bold header
Run-ParseTest "Markdown bold **Checksum:**" "**Checksum:** $sampleHash" $sampleHash

# R1.10 Backtick-wrapped hash
Run-ParseTest 'Backtick wrapped hash `hash`' ('checksum: `' + $sampleHash + '`') $sampleHash

# R1.11 Multi-arch collision test: ARM64 listed before x64!
$multiArchBody = @"
## Downloads
ARM64 checksum: 1111111111111111111111111111111111111111111111111111111111111111
GitHub Release x64 checksum: $sampleHash
"@
Run-ParseTest "Multi-arch notes (ARM64 before x64)" $multiArchBody $sampleHash

# R1.12 Previous release hash mentioned in notes
$prevReleaseBody = @"
Previous release checksum was 3333333333333333333333333333333333333333333333333333333333333333
GitHub Release x64 checksum: $sampleHash
"@
Run-ParseTest "Previous release hash mentioned" $prevReleaseBody $sampleHash

# R1.13 Malformed hash: 63 characters (one short)
Run-ParseTest "Malformed 63-hex string" "GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b85" ""

# R1.14 Malformed hash: 65 characters (one too long)
Run-ParseTest "Malformed 65-hex string" "GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a" ""

# R1.15 Non-hex chars in 64-char string
Run-ParseTest "Non-hex string (contains 'g')" "GitHub Release x64 checksum: g3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ""

# R1.16 No checksum present
Run-ParseTest "No checksum present in notes" "Bug fixes and improvements" ""

# R1.17 Empty body
Run-ParseTest "Empty body" "" ""

# R1.18 Asset matching: x64 priority over non-x64
$multiAssetJson = @{
    body = "GitHub Release x64 checksum: $sampleHash"
    assets = @(
        @{
            name = "FluentFlyout_2.16.0_arm64_Installer.zip"
            browser_download_url = "https://example.com/arm64.zip"
        },
        @{
            name = "FluentFlyout_2.16.0_x64_Installer.zip"
            browser_download_url = "https://example.com/x64.zip"
        }
    )
} | ConvertTo-Json -Depth 5
$multiAssetDoc = [System.Text.Json.JsonDocument]::Parse($multiAssetJson)
$parseRes = ($UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")).Invoke($null, @($multiAssetDoc))
if ($parseRes.Item1 -eq "https://example.com/x64.zip") {
    Record-Result "Asset" "Prefers x64 Installer.zip over arm64" "PASS" "https://example.com/x64.zip" $parseRes.Item1
} else {
    Record-Result "Asset" "Prefers x64 Installer.zip over arm64" "FAIL" "https://example.com/x64.zip" $parseRes.Item1
}

# R1.19 Asset matching: ignores non-installer zip
$nonInstallerAssetJson = @{
    body = "GitHub Release x64 checksum: $sampleHash"
    assets = @(
        @{
            name = "FluentFlyout_2.16.0_x64_portable.zip"
            browser_download_url = "https://example.com/portable.zip"
        }
    )
} | ConvertTo-Json -Depth 5
$nonInstallerDoc = [System.Text.Json.JsonDocument]::Parse($nonInstallerAssetJson)
$nonParseRes = ($UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")).Invoke($null, @($nonInstallerDoc))
if ($nonParseRes.Item1 -eq "") {
    Record-Result "Asset" "Ignores non-Installer.zip assets" "PASS" "" $nonParseRes.Item1
} else {
    Record-Result "Asset" "Ignores non-Installer.zip assets" "FAIL" "" $nonParseRes.Item1
}


Write-Host "`n=== AREA 2: VERSION COMPARISON (IsNewerVersion) ===" -ForegroundColor Cyan

$isNewerMethod = $UpdateCheckerType.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public, Static")

function Run-VersionTest {
    param(
        [string]$Name,
        [string]$Current,
        [string]$Newest,
        [bool]$Expected
    )
    $actual = [bool]$isNewerMethod.Invoke($null, @($Current, $Newest))
    $status = if ($actual -eq $Expected) { "PASS" } else { "FAIL" }
    Record-Result "Version" $Name $status ($Expected.ToString()) ($actual.ToString()) "Current='$Current', Newest='$Newest'"
}

# V1 Standard semver upgrades
Run-VersionTest "Minor upgrade: 2.15.0 -> 2.16.0" "2.15.0" "2.16.0" $true
Run-VersionTest "Patch upgrade: 2.16.0 -> 2.16.1" "2.16.0" "2.16.1" $true
Run-VersionTest "Major upgrade: 2.16.0 -> 3.0.0" "2.16.0" "3.0.0" $true
Run-VersionTest "Same version: 2.16.0 -> 2.16.0" "2.16.0" "2.16.0" $false
Run-VersionTest "Downgrade: 2.16.0 -> 2.15.0" "2.16.0" "2.15.0" $false

# V2 'v' prefix variations
Run-VersionTest "v-prefix on both: v2.15.0 -> v2.16.0" "v2.15.0" "v2.16.0" $true
Run-VersionTest "Uppercase V on current: V2.15.0 -> v2.16.0" "V2.15.0" "v2.16.0" $true
Run-VersionTest "v on newest only: 2.15.0 -> v2.16.0" "2.15.0" "v2.16.0" $true
Run-VersionTest "v on current only: v2.15.0 -> 2.16.0" "v2.15.0" "2.16.0" $true

# V3 4-part versions
Run-VersionTest "4-part revision upgrade: 2.16.0.0 -> 2.16.0.1" "2.16.0.0" "2.16.0.1" $true
Run-VersionTest "3-part vs 4-part same: 2.16.0 vs 2.16.0.0" "2.16.0" "2.16.0.0" $false
Run-VersionTest "3-part vs 4-part upgrade: 2.16.0 vs 2.16.0.1" "2.16.0" "2.16.0.1" $true

# V4 2-part versions
Run-VersionTest "2-part to 3-part: 2.15 vs 2.16.0" "2.15" "2.16.0" $true
Run-VersionTest "2-part same: 2.16 vs 2.16.0" "2.16" "2.16.0" $false

# V5 Prerelease tags
Run-VersionTest "Prerelease to higher patch: v2.16.0-beta.1 -> v2.16.1" "v2.16.0-beta.1" "v2.16.1" $true
Run-VersionTest "Prerelease to stable of same version: v2.16.0-beta.1 -> v2.16.0" "v2.16.0-beta.1" "v2.16.0" $true
Run-VersionTest "Prerelease to next prerelease: v2.16.0-beta.1 -> v2.16.0-beta.2" "v2.16.0-beta.1" "v2.16.0-beta.2" $true
Run-VersionTest "Stable to prerelease patch: v2.16.0 -> v2.16.1-rc1" "v2.16.0" "v2.16.1-rc1" $true

# V6 Build metadata (+build)
Run-VersionTest "Build metadata: v2.15.0 -> v2.16.0+build123" "v2.15.0" "v2.16.0+build123" $true

# V7 Malformed & boundary inputs
Run-VersionTest "Empty current version" "" "v2.16.0" $true
Run-VersionTest "Empty newest version" "v2.16.0" "" $false
Run-VersionTest "Invalid current string" "invalid" "v2.16.0" $false
Run-VersionTest "Invalid newest string" "v2.16.0" "invalid" $false
Run-VersionTest "Whitespace current" "  v2.15.0  " "v2.16.0" $true
Run-VersionTest "Large major version jump" "v2.16.0" "v999.0.0" $true


Write-Host "`n=== AREA 3: SHA-256 CRYPTOGRAPHIC INTEGRITY ===" -ForegroundColor Cyan

# Test in-process SHA256 against standard cryptographic test vectors
$tempDir = Join-Path ([System.IO.Path]::GetTempPath()) "FF_Challenger_Tests"
if (Test-Path $tempDir) { Remove-Item $tempDir -Recurse -Force }
New-Item -ItemType Directory -Path $tempDir | Out-Null

try {
    # Test 3.1 Empty file standard NIST SHA-256
    $emptyFile = Join-Path $tempDir "empty.bin"
    [System.IO.File]::WriteAllBytes($emptyFile, [byte[]]@())

    $expectedEmptyHash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    $verifyMethod = $UpdateInstallerType.GetMethod("VerifyFileHashAsync", [System.Reflection.BindingFlags]"NonPublic, Static")
    $task = $verifyMethod.Invoke($null, [object[]]@([string]$emptyFile, [string]$expectedEmptyHash))
    $task.Wait()
    $resEmpty = $task.Result

    if ($resEmpty -eq $true) {
        Record-Result "Crypto" "NIST Empty file SHA-256" "PASS" "true" "true" "Hash matches e3b0c442..."
    } else {
        Record-Result "Crypto" "NIST Empty file SHA-256" "FAIL" "true" "false"
    }

    # Test 3.2 Known string vector: "The quick brown fox jumps over the lazy dog"
    # Expected SHA256: d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592
    $foxFile = Join-Path $tempDir "fox.txt"
    [System.IO.File]::WriteAllBytes($foxFile, [System.Text.Encoding]::ASCII.GetBytes("The quick brown fox jumps over the lazy dog"))
    $expectedFoxHash = "d7a8fbb307d7809469ca9abcb0082e4f8d5651e46d3cdb762d02d0bf37c9e592"

    $taskFox = $verifyMethod.Invoke($null, [object[]]@([string]$foxFile, [string]$expectedFoxHash))
    $taskFox.Wait()
    $resFox = $taskFox.Result
    if ($resFox -eq $true) {
        Record-Result "Crypto" "NIST Fox string SHA-256" "PASS" "true" "true" "Hash matches d7a8fbb..."
    } else {
        Record-Result "Crypto" "NIST Fox string SHA-256" "FAIL" "true" "false"
    }

    # Test 3.3 Large 5MB random binary file: Cross-check against Get-FileHash
    $largeFile = Join-Path $tempDir "large_5mb.bin"
    $rng = [System.Security.Cryptography.RandomNumberGenerator]::Create()
    $largeBytes = [byte[]]::new(5 * 1024 * 1024)
    $rng.GetBytes($largeBytes)
    [System.IO.File]::WriteAllBytes($largeFile, $largeBytes)

    $sysHash = (Get-FileHash -Path $largeFile -Algorithm SHA256).Hash.ToLowerInvariant()
    $taskLarge = $verifyMethod.Invoke($null, [object[]]@([string]$largeFile, [string]$sysHash))
    $taskLarge.Wait()
    $resLarge = $taskLarge.Result

    if ($resLarge -eq $true) {
        Record-Result "Crypto" "5MB binary vs Get-FileHash" "PASS" "true" "true" "System hash matched: $sysHash"
    } else {
        Record-Result "Crypto" "5MB binary vs Get-FileHash" "FAIL" "true" "false"
    }

    # Test 3.4 Case-insensitivity in hash comparison
    $taskUpper = $verifyMethod.Invoke($null, [object[]]@([string]$largeFile, [string]($sysHash.ToUpperInvariant())))
    $taskUpper.Wait()
    if ($taskUpper.Result -eq $true) {
        Record-Result "Crypto" "Uppercase expected hash comparison" "PASS" "true" "true"
    } else {
        Record-Result "Crypto" "Uppercase expected hash comparison" "FAIL" "true" "false"
    }

    # Test 3.5 Tampered file detection (1-bit flip)
    $tamperedFile = Join-Path $tempDir "tampered.bin"
    $tamperedBytes = [byte[]]::new($largeBytes.Length)
    [Array]::Copy($largeBytes, $tamperedBytes, $largeBytes.Length)
    $tamperedBytes[42] = [byte]($tamperedBytes[42] -bxor 1)
    [System.IO.File]::WriteAllBytes($tamperedFile, $tamperedBytes)

    $taskTampered = $verifyMethod.Invoke($null, [object[]]@([string]$tamperedFile, [string]$sysHash))
    $taskTampered.Wait()
    if ($taskTampered.Result -eq $false) {
        Record-Result "Crypto" "Detect 1-bit file tampering" "PASS" "false" "false" "Tampering correctly detected"
    } else {
        Record-Result "Crypto" "Detect 1-bit file tampering" "FAIL" "false" "true" "SECURITY RISK: Tampered file passed verification!"
    }

    # Test 3.6 Non-existent file handling
    $taskMissing = $verifyMethod.Invoke($null, [object[]]@([string](Join-Path $tempDir "nonexistent.bin"), [string]$expectedFoxHash))
    $taskMissing.Wait()
    if ($taskMissing.Result -eq $false) {
        Record-Result "Crypto" "Non-existent file returns false" "PASS" "false" "false"
    } else {
        Record-Result "Crypto" "Non-existent file returns false" "FAIL" "false" "true"
    }

} finally {
    if (Test-Path $tempDir) {
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}


Write-Host "`n=== AREA 4: DECOUPLED SCRIPT GENERATION & SYNTAX ===" -ForegroundColor Cyan

$buildScriptMethod = $UpdateInstallerType.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic, Static")
$script = $buildScriptMethod.Invoke($null, @(9999, "C:\Sample Dir\SystemFiles"))

# Parse with PowerShell parser
$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($script, [ref]$tokens, [ref]$parseErrors) | Out-Null

if ($parseErrors.Count -eq 0) {
    Record-Result "Script" "PowerShell AST Parse Syntax" "PASS" "0 errors" "0 errors"
} else {
    Record-Result "Script" "PowerShell AST Parse Syntax" "FAIL" "0 errors" "$($parseErrors.Count) errors" ($parseErrors | Out-String)
}

# Verify key tokens in script
$hasWait = $script -match "Wait-Process\s+-Id\s+9999"
$hasLocation = ($script.Contains("`$systemFiles = 'C:\Sample Dir\SystemFiles'")) -and ($script -match 'Set-Location\s+-LiteralPath\s+\$systemFiles')
$hasForce = $script -match "Add-AppDevPackage\.ps1'\s+-Force"
$hasTranscript = $script -match "Start-Transcript"
$hasRelaunch = $script -match "Get-AppxPackage '\*FluentFlyout\*'"

if ($hasWait -and $hasLocation -and $hasForce -and $hasTranscript -and $hasRelaunch) {
    Record-Result "Script" "Hardened script commands present" "PASS" "All present" "All present"
} else {
    Record-Result "Script" "Hardened script commands present" "FAIL" "All present" "Wait=$hasWait, Loc=$hasLocation, Force=$hasForce, Trans=$hasTranscript, Rel=$hasRelaunch"
}

Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
$passCount = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failCount = ($results | Where-Object { $_.Status -eq "FAIL" }).Count
Write-Host "Total Tests: $($results.Count)"
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

# Output JSON results for programmatic analysis
$results | ConvertTo-Json -Depth 3 | Set-Content "E:\Programacion\FluentFlyout\.agents\teamwork\challenger_m1_1\test_results.json"
