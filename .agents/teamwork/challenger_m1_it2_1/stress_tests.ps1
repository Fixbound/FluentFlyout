# Extended Empirical Stress Tests for Challenger M1 Iteration 2
# Tests edge cases beyond the standard 52-test harness

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

if ($null -eq $UpdateCheckerType -or $null -eq $UpdateInstallerType) {
    Write-Error "Could not find required types in assembly"
    exit 1
}

$parseMethod = $UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")
$isNewerMethod = $UpdateCheckerType.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public, Static")
$buildScriptMethod = $UpdateInstallerType.GetMethod("BuildApplyScriptContent", [System.Reflection.BindingFlags]"NonPublic, Static")

function Test-Parse {
    param(
        [string]$Name,
        [string]$Body,
        [string]$ExpectedSha,
        [string]$ExpectedAssetUrl = "",
        [array]$Assets = @(
            @{
                name = "FluentFlyout_2.16.0_x64_Installer.zip"
                browser_download_url = "https://github.com/unchihugo/FluentFlyout/releases/download/v2.16.0/FluentFlyout_2.16.0_x64_Installer.zip"
            }
        )
    )

    $jsonObj = @{
        body = $Body
        assets = $Assets
    }
    $jsonStr = $jsonObj | ConvertTo-Json -Depth 5
    $jsonDoc = [System.Text.Json.JsonDocument]::Parse($jsonStr)

    $res = $parseMethod.Invoke($null, @($jsonDoc))
    $actualUrl = $res.Item1
    $actualSha = $res.Item2

    $shaPass = ($actualSha -eq $ExpectedSha.ToLowerInvariant())
    $urlPass = if ($ExpectedAssetUrl) { $actualUrl -eq $ExpectedAssetUrl } else { $true }

    if ($shaPass -and $urlPass) {
        Record-Result "Regex-Stress" $Name "PASS" $ExpectedSha $actualSha "URL: $actualUrl"
    } else {
        Record-Result "Regex-Stress" $Name "FAIL" $ExpectedSha $actualSha "URL: Actual='$actualUrl', Expected='$ExpectedAssetUrl'"
    }
}

function Test-Version {
    param(
        [string]$Name,
        [string]$Current,
        [string]$Newest,
        [bool]$Expected
    )

    $actual = $isNewerMethod.Invoke($null, @($Current, $Newest))
    if ($actual -eq $Expected) {
        Record-Result "Version-Stress" $Name "PASS" $Expected $actual "Current='$Current', Newest='$Newest'"
    } else {
        Record-Result "Version-Stress" $Name "FAIL" $Expected $actual "Current='$Current', Newest='$Newest'"
    }
}

Write-Host "`n=== CATEGORY A: EXTENDED REGEX & MULTI-ARCH STRESS TESTS ===" -ForegroundColor Cyan

$hashArm64 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$hashX64   = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
$hashX86   = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
$hash128   = "11111111111111111111111111111111111111111111111111111111111111112222222222222222222222222222222222222222222222222222222222222222"

# A.1 Markdown table with ARM64 row before x64 row
$tableBody = @"
## Checksums
| Architecture | SHA256 Checksum |
| :--- | :--- |
| ARM64 | $hashArm64 |
| x64 | $hashX64 |
"@
Test-Parse "Markdown table ARM64 before x64" $tableBody $hashX64

# A.2 Bulleted list with x86, arm64, and x64
$bulletBody = @"
Release assets:
* x86 checksum: $hashX86
* arm64 checksum: $hashArm64
* x64 checksum: $hashX64
"@
Test-Parse "Bulleted list multi-arch" $bulletBody $hashX64

# A.3 Colon with parenthesis: SHA-256 (x64): <hash>
Test-Parse "Parenthesized arch SHA-256 (x64):" "SHA-256 (x64): $hashX64" $hashX64

# A.4 Markdown bold x64 and hash
Test-Parse "Markdown bold x64 header" "**x64 Checksum**: **$hashX64**" $hashX64

# A.5 Mixed CRLF, LF, CR in notes
$mixedLineEndings = "Line 1`r`nLine 2`nARM64: $hashArm64`rLine 3`r`nx64: $hashX64`nLine 4"
Test-Parse "Mixed CRLF, LF, CR line endings" $mixedLineEndings $hashX64

# A.6 SHA-512 in notes (128 hex chars) must NOT match as 64-hex prefix
$sha512Body = @"
Release Notes:
SHA-512: $hash128
Single architecture sha256 checksum: $hashX64
"@
Test-Parse "SHA-512 128-hex ignored via word boundaries" $sha512Body $hashX64

# A.7 Multi-tier priority: Sha256WorkflowRegex over Sha256X64Regex
$priorityBody1 = @"
x64 checksum: $hashArm64
GitHub Release x64 checksum: $hashX64
"@
Test-Parse "Tier 1 Workflow over Tier 2 x64" $priorityBody1 $hashX64

# A.8 Multi-tier priority: Sha256X64Regex over Sha256FallbackRegex
$priorityBody2 = @"
checksum: $hashArm64
x64 checksum: $hashX64
"@
Test-Parse "Tier 2 x64 over Tier 3 Fallback" $priorityBody2 $hashX64

# A.9 Generic fallback (Tier 4) when no keywords exist
$rawHashBody = @"
Version 2.16.0 has been released.
$hashX64
Thank you for using FluentFlyout!
"@
Test-Parse "Tier 4 generic 64-hex fallback" $rawHashBody $hashX64

# A.10 Mixed-case hash handling (64 chars) and malformed length (62 chars)
$mixedCaseHash64 = "bB" * 32
Test-Parse "Mixed-case 64-hex normalized to lowercase" "GitHub Release x64 checksum: $mixedCaseHash64" $hashX64

$malformed62 = "bB" * 31
Test-Parse "Malformed 62-hex mixed-case rejected" "GitHub Release x64 checksum: $malformed62" ""

# A.11 Hash surrounded by quotes
Test-Parse "Hash in double quotes" 'x64 hash: "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"' $hashX64

# A.12 Hash surrounded by square brackets
Test-Parse "Hash in brackets" "x64: [$hashX64]" $hashX64


Write-Host "`n=== CATEGORY B: ASSET SELECTION NUANCES ===" -ForegroundColor Cyan

# B.1 Multiple assets with companion files
$assetsMixed = @(
    @{ name = "FluentFlyout_2.16.0_arm64_Installer.zip"; browser_download_url = "https://example.com/arm64.zip" },
    @{ name = "FluentFlyout_2.16.0_x64_Installer.zip.sha256"; browser_download_url = "https://example.com/x64.zip.sha256" },
    @{ name = "FluentFlyout_2.16.0_x64_Installer.zip"; browser_download_url = "https://example.com/x64.zip" },
    @{ name = "Source code.zip"; browser_download_url = "https://example.com/src.zip" }
)
Test-Parse "Multi-asset companion filter" "x64 checksum: $hashX64" $hashX64 "https://example.com/x64.zip" $assetsMixed

# B.2 Uppercase asset name
$assetsUpper = @(
    @{ name = "FLUENTFLYOUT_2.16.0_X64_INSTALLER.ZIP"; browser_download_url = "https://example.com/upper_x64.zip" }
)
Test-Parse "Uppercase asset name matching" "x64: $hashX64" $hashX64 "https://example.com/upper_x64.zip" $assetsUpper

# B.3 No valid installer assets
$assetsNone = @(
    @{ name = "source.zip"; browser_download_url = "https://example.com/source.zip" }
)
Test-Parse "No matching installer assets" "x64: $hashX64" $hashX64 "" $assetsNone


Write-Host "`n=== CATEGORY C: SEMVER 2.0.0 SPECIFICATION & BOUNDARY STRESS TESTS ===" -ForegroundColor Cyan

# C.1 Full SemVer 2.0.0 §11.4 Pre-release Chain Progression
# 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
Test-Version "SemVer chain 1: alpha -> alpha.1" "1.0.0-alpha" "1.0.0-alpha.1" $true
Test-Version "SemVer chain 2: alpha.1 -> alpha.beta" "1.0.0-alpha.1" "1.0.0-alpha.beta" $true
Test-Version "SemVer chain 3: alpha.beta -> beta" "1.0.0-alpha.beta" "1.0.0-beta" $true
Test-Version "SemVer chain 4: beta -> beta.2" "1.0.0-beta" "1.0.0-beta.2" $true
Test-Version "SemVer chain 5: beta.2 -> beta.11" "1.0.0-beta.2" "1.0.0-beta.11" $true
Test-Version "SemVer chain 6: beta.11 -> rc.1" "1.0.0-beta.11" "1.0.0-rc.1" $true
Test-Version "SemVer chain 7: rc.1 -> 1.0.0 stable" "1.0.0-rc.1" "1.0.0" $true

# Reverse checks (downgrades)
Test-Version "SemVer rev 1: alpha.1 -> alpha" "1.0.0-alpha.1" "1.0.0-alpha" $false
Test-Version "SemVer rev 2: alpha.beta -> alpha.1" "1.0.0-alpha.beta" "1.0.0-alpha.1" $false
Test-Version "SemVer rev 3: beta.11 -> beta.2" "1.0.0-beta.11" "1.0.0-beta.2" $false
Test-Version "SemVer rev 4: 1.0.0 stable -> rc.1" "1.0.0" "1.0.0-rc.1" $false

# C.2 Case-insensitivity in prerelease identifiers
Test-Version "Prerelease case insensitive compare 1" "2.16.0-RC.1" "2.16.0-rc.2" $true
Test-Version "Prerelease case insensitive equal" "2.16.0-BETA.1" "2.16.0-beta.1" $false

# C.3 SemVer §10 Build Metadata Ignored in Precedence
Test-Version "Build metadata ignored on stable" "1.0.0+20130313144700" "1.0.0" $false
Test-Version "Build metadata ignored on remote" "1.0.0" "1.0.0+20130313144700" $false
Test-Version "Build metadata different timestamps" "1.0.0+20130313" "1.0.0+20130314" $false
Test-Version "Build metadata on identical prerelease" "1.0.0-alpha+001" "1.0.0-alpha+002" $false
Test-Version "Build metadata on differing prerelease" "1.0.0-alpha+001" "1.0.0-alpha.1+001" $true

# C.4 Cross-base transitions with prerelease
Test-Version "Cross-base: stable to higher prerelease base" "1.0.0" "2.0.0-alpha" $true
Test-Version "Cross-base: prerelease to lower stable" "2.0.0-alpha" "1.0.0" $false
Test-Version "Cross-base: prerelease to higher prerelease base" "1.0.0-beta" "1.0.1-alpha" $true
Test-Version "Cross-base: higher prerelease to lower prerelease" "1.0.1-alpha" "1.0.0-beta" $false

# C.5 Notation mixing (1-part, 2-part, 3-part, 4-part)
Test-Version "Notation 1-part vs 1-part upgrade" "2" "3" $true
Test-Version "Notation 1-part vs 1-part same" "2" "2" $false
Test-Version "Notation 1-part vs 2-part same" "2" "2.0" $false
Test-Version "Notation 1-part vs 3-part same" "2" "2.0.0" $false
Test-Version "Notation 1-part vs 4-part same" "2" "2.0.0.0" $false
Test-Version "Notation 4-part revision step" "2.16.0.5" "2.16.0.6" $true
Test-Version "Notation 4-part revision downgrade" "2.16.0.6" "2.16.0.5" $false
Test-Version "Notation 4-part vs 3-part patch higher" "2.16.0.99" "2.16.1" $true
Test-Version "Notation 3-part patch vs 4-part lower" "2.16.1" "2.16.0.99" $false

# C.6 Zero and boundary cases
Test-Version "Zero version 0.0.0.0 to 0.0.0.1" "0.0.0.0" "0.0.0.1" $true
Test-Version "Zero version 0.0.0.1 to 0.0.0.0" "0.0.0.1" "0.0.0.0" $false
Test-Version "Negative component in current" "-1.0.0" "2.16.0" $false
Test-Version "Negative component in newest" "2.16.0" "-1.0.0" $false
Test-Version "5-part version current rejected" "1.2.3.4.5" "2.0.0" $false
Test-Version "5-part version newest rejected" "2.0.0" "1.2.3.4.5" $false
Test-Version "Empty dots in string '1..0'" "1..0" "2.0.0" $false
Test-Version "Alphanumeric base '1.2.3a'" "1.2.3a" "2.0.0" $false
Test-Version "Leading zeros '2.01.0' vs '2.2.0'" "2.01.0" "2.2.0" $true
Test-Version "Leading zeros '2.01.0' vs '2.1.0'" "2.01.0" "2.1.0" $false


Write-Host "`n=== CATEGORY D: DECOUPLED INSTALLER SCRIPT ROBUSTNESS ===" -ForegroundColor Cyan

# D.1 Script generation with single quote in path
$pathWithSingleQuote = "C:\Program Files\Fluent'Flyout\SystemFiles"
$scriptContent = $buildScriptMethod.Invoke($null, @(12345, $pathWithSingleQuote))

$escapedTarget = "C:\Program Files\Fluent''Flyout\SystemFiles"
$hasEscaped = $scriptContent.Contains($escapedTarget)
if ($hasEscaped) {
    Record-Result "Script-Stress" "Single quote path escaping" "PASS" "Contains $escapedTarget" "Found"
} else {
    Record-Result "Script-Stress" "Single quote path escaping" "FAIL" "Contains $escapedTarget" "Not found"
}

# D.2 AST syntax verification for escaped path script
$astTokens = $null
$astErrors = $null
[System.Management.Automation.Language.Parser]::ParseInput($scriptContent, [ref]$astTokens, [ref]$astErrors) | Out-Null
if ($astErrors.Count -eq 0) {
    Record-Result "Script-Stress" "Script with quotes parses valid AST" "PASS" "0 errors" "0 errors"
} else {
    Record-Result "Script-Stress" "Script with quotes parses valid AST" "FAIL" "0 errors" "$($astErrors.Count) errors: $($astErrors[0].Message)"
}

Write-Host "`n=== EXTENDED STRESS TEST SUMMARY ===" -ForegroundColor Cyan
$total = $results.Count
$passed = ($results | Where-Object { $_.Status -eq "PASS" }).Count
$failed = ($results | Where-Object { $_.Status -eq "FAIL" }).Count

Write-Host "Total Stress Tests: $total"
Write-Host "Passed: $passed" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -eq 0) { "Green" } else { "Red" })

if ($failed -gt 0) {
    exit 1
}
exit 0
