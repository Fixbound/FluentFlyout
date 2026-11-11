# Adversarial Stress-Test Suite for Reviewer 2 (Milestone 1 Iteration 2)
param()

$ErrorActionPreference = "Stop"

$assemblyPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"
if (-not (Test-Path -LiteralPath $assemblyPath)) {
    Write-Error "Assembly not found at $assemblyPath"
    exit 1
}

[System.Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null
$UpdateCheckerType = [Type]::GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService, FluentFlyout")
$UpdateInstallerType = [Type]::GetType("FluentFlyoutWPF.Classes.Services.UpdateInstallerService, FluentFlyout")

$parseMethod = $UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")
$isNewerMethod = $UpdateCheckerType.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public, Static")

$passCount = 0
$failCount = 0

function Assert-Test {
    param(
        [string]$TestCategory,
        [string]$TestName,
        [bool]$Condition,
        [string]$Details = ""
    )
    if ($Condition) {
        $script:passCount++
        Write-Host "  [PASS] [$TestCategory] $TestName $(if ($Details) { "($Details)" })" -ForegroundColor Green
    } else {
        $script:failCount++
        Write-Host "  [FAIL] [$TestCategory] $TestName $(if ($Details) { "($Details)" })" -ForegroundColor Red
    }
}

Write-Host "=== ADVERSARIAL SUITE 1: SEMVER 2.0.0 NUMERIC VS LEXICAL PRECEDENCE ===" -ForegroundColor Cyan

# Test 1.1: SemVer 2.0 numeric precedence (beta.11 > beta.2)
# If implementation incorrectly used lexical sort, "beta.11" < "beta.2" (false downgrade)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-beta.2", "v1.0.0-beta.11"))
Assert-Test "SemVer" "Numeric identifier upgrade: beta.2 -> beta.11" ($res -eq $true) "Expected True, Got $res"

# Test 1.2: SemVer 2.0 numeric precedence downgrade (beta.11 -> beta.2 is false)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-beta.11", "v1.0.0-beta.2"))
Assert-Test "SemVer" "Numeric identifier downgrade: beta.11 -> beta.2" ($res -eq $false) "Expected False, Got $res"

# Test 1.3: SemVer 2.0 numeric vs non-numeric (1 < beta)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-alpha.1", "v1.0.0-alpha.beta"))
Assert-Test "SemVer" "Numeric < non-numeric: alpha.1 -> alpha.beta" ($res -eq $true) "Expected True, Got $res"

# Test 1.4: SemVer 2.0 non-numeric > numeric (alpha.beta -> alpha.1 is false)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-alpha.beta", "v1.0.0-alpha.1"))
Assert-Test "SemVer" "Non-numeric > numeric: alpha.beta -> alpha.1" ($res -eq $false) "Expected False, Got $res"

# Test 1.5: SemVer 2.0 identifier count tie-breaker (alpha < alpha.1)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-alpha", "v1.0.0-alpha.1"))
Assert-Test "SemVer" "Larger prerelease set: alpha -> alpha.1" ($res -eq $true) "Expected True, Got $res"

# Test 1.6: SemVer 2.0 build metadata ignored for same version (v1.0.0+build1 vs v1.0.0+build2)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0+build1", "v1.0.0+build2"))
Assert-Test "SemVer" "Build metadata ignored on identical versions" ($res -eq $false) "Expected False, Got $res"

# Test 1.7: Prerelease with build metadata upgrade (v1.0.0-alpha.1+build1 -> v1.0.0-alpha.2+build2)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-alpha.1+build1", "v1.0.0-alpha.2+build2"))
Assert-Test "SemVer" "Prerelease with build metadata upgrade" ($res -eq $true) "Expected True, Got $res"

# Test 1.8: Case-insensitive prerelease comparison (v1.0.0-BETA.1 -> v1.0.0-beta.2)
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-BETA.1", "v1.0.0-beta.2"))
Assert-Test "SemVer" "Case-insensitive prerelease comparison" ($res -eq $true) "Expected True, Got $res"

# Test 1.9: Multi-digit numeric components
$res = [bool]$isNewerMethod.Invoke($null, @("2.9.999", "2.10.0"))
Assert-Test "SemVer" "Multi-digit base version upgrade: 2.9.999 -> 2.10.0" ($res -eq $true) "Expected True, Got $res"

# Test 1.10: 64-bit integer handling in prerelease identifier
$res = [bool]$isNewerMethod.Invoke($null, @("v1.0.0-rc.9000000000", "v1.0.0-rc.9000000001"))
Assert-Test "SemVer" "Int64 prerelease numeric identifier comparison" ($res -eq $true) "Expected True, Got $res"


Write-Host "`n=== ADVERSARIAL SUITE 2: MALFORMED & BOUNDARY VERSION INPUTS ===" -ForegroundColor Cyan

# Test 2.1: Leading zeros in version segments (2.01.0 vs 2.1.0)
$res = [bool]$isNewerMethod.Invoke($null, @("2.01.0", "2.1.0"))
Assert-Test "Boundary" "Leading zero equivalence: 2.01.0 == 2.1.0" ($res -eq $false) "Expected False, Got $res"

# Test 2.2: Negative version numbers (2.-1.0)
$res = [bool]$isNewerMethod.Invoke($null, @("2.-1.0", "2.1.0"))
Assert-Test "Boundary" "Negative version segment fails gracefully" ($res -eq $false) "Expected False, Got $res"

# Test 2.3: 5-segment version (2.16.0.1.2)
$res = [bool]$isNewerMethod.Invoke($null, @("2.16.0.1.2", "2.16.0.2.0"))
Assert-Test "Boundary" "5-part version rejected (> 4 parts)" ($res -eq $false) "Expected False, Got $res"

# Test 2.4: Extremely large overflow integers (e.g. 100 digits)
$res = [bool]$isNewerMethod.Invoke($null, @("1.99999999999999999999999999999999999999999999999999.0", "2.0.0"))
Assert-Test "Boundary" "Integer overflow segment fails gracefully" ($res -eq $false) "Expected False, Got $res"

# Test 2.5: Control characters / newlines in version strings
$res = [bool]$isNewerMethod.Invoke($null, @("v2.16.0`r`n", "v2.16.1`n"))
Assert-Test "Boundary" "Version with newline whitespace" ($res -eq $true) "Expected True, Got $res"

# Test 2.6: Version with space before prerelease
$res = [bool]$isNewerMethod.Invoke($null, @("v2.16.0 -beta.1", "v2.16.0"))
Assert-Test "Boundary" "Space before dash in prerelease" ($res -eq $true) "Expected True, Got $res"

# Test 2.7: Version containing only symbols
$res = [bool]$isNewerMethod.Invoke($null, @("---", "+++"))
Assert-Test "Boundary" "Only symbols returns false" ($res -eq $false) "Expected False, Got $res"


Write-Host "`n=== ADVERSARIAL SUITE 3: REGEX EXTRACTION & MALICIOUS/NOISY BODIES ===" -ForegroundColor Cyan

function Run-AdversarialRegex {
    param(
        [string]$Name,
        [string]$Body,
        [string]$ExpectedHash
    )
    $jsonObj = @{
        body = $Body
        assets = @(
            @{
                name = "FluentFlyout_2.16.0_x64_Installer.zip"
                browser_download_url = "https://example.com/installer.zip"
            }
        )
    } | ConvertTo-Json
    $doc = [System.Text.Json.JsonDocument]::Parse($jsonObj)
    $res = $parseMethod.Invoke($null, @($doc))
    $actualHash = $res.Item2
    $pass = ($actualHash -eq $ExpectedHash.ToLowerInvariant())
    Assert-Test "RegexAdv" $Name $pass "Expected '$ExpectedHash', Got '$actualHash'"
}

$goodHashX64 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$dummyHashArm = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"

# Test 3.1: Markdown table format with x64
$tableBody = @"
| Architecture | Checksum |
| :--- | :--- |
| arm64 | $dummyHashArm |
| x64 | $goodHashX64 |
"@
Run-AdversarialRegex "Markdown table with ARM64 and x64" $tableBody $goodHashX64

# Test 3.2: ReDoS stress test - 50,000 character line with repeated non-matching patterns
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$longLine = ("a" * 50000) + "`nGitHub Release x64 checksum: $goodHashX64"
Run-AdversarialRegex "ReDoS 50KB single-line stress test" $longLine $goodHashX64
$sw.Stop()
Assert-Test "ReDoS" "50KB regex evaluation under 500ms" ($sw.ElapsedMilliseconds -lt 500) "Elapsed: $($sw.ElapsedMilliseconds)ms"

# Test 3.3: Multiple hashes with x64 explicitly labeled in different case and spacing
$complexBody = @"
## Automated Build
Workflow runner: GitHub Actions (windows-2022)
* SHA256 (FluentFlyout_2.16.0_ARM64_Installer.zip) = $dummyHashArm
* SHA256 (FluentFlyout_2.16.0_X64_Installer.zip) = $goodHashX64
"@
Run-AdversarialRegex "Parenthesized architecture SHA256 format" $complexBody $goodHashX64

# Test 3.4: Digest keyword
$digestBody = @"
FluentFlyout x64 installer digest: $goodHashX64
"@
Run-AdversarialRegex "x64 digest keyword" $digestBody $goodHashX64

# Test 3.5: Unicode / Emojis surrounding hash
$emojiBody = "🚀 GitHub Release x64:`n🔒 SHA-256 Checksum: ``$goodHashX64``"
Run-AdversarialRegex "Emoji and backtick wrapped checksum" $emojiBody $goodHashX64

# Test 3.6: Filenames with underscores in release notes (arm64 before x64)
$fileUnderscoreBody = @"
FluentFlyout_2.16.0_arm64_Installer.zip checksum: $dummyHashArm
FluentFlyout_2.16.0_x64_Installer.zip checksum: $goodHashX64
"@
Run-AdversarialRegex "Filename with underscores in release notes (arm64 before x64)" $fileUnderscoreBody $goodHashX64


Write-Host "`n=== ADVERSARIAL SUITE 4: DYNAMIC REPOSITORY OVERRIDE ===" -ForegroundColor Cyan

# Test 4.1: Default repo endpoint
$defaultEndpoint = [string]$UpdateCheckerType.GetProperty("GitHubApiLatestRelease", [System.Reflection.BindingFlags]"Public, Static").GetValue($null)
Assert-Test "Config" "Default endpoint points to unchihugo/FluentFlyout" ($defaultEndpoint -eq "https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest") "Got '$defaultEndpoint'"

# Test 4.2: Override via FLUENTFLYOUT_UPDATE_REPO
try {
    [Environment]::SetEnvironmentVariable("FLUENTFLYOUT_UPDATE_REPO", "customowner/customfork")
    $customEndpoint = [string]$UpdateCheckerType.GetProperty("GitHubApiLatestRelease", [System.Reflection.BindingFlags]"Public, Static").GetValue($null)
    Assert-Test "Config" "Environment override custom repo" ($customEndpoint -eq "https://api.github.com/repos/customowner/customfork/releases/latest") "Got '$customEndpoint'"

    # Test 4.3: Malformed override without slash
    [Environment]::SetEnvironmentVariable("FLUENTFLYOUT_UPDATE_REPO", "malformed_no_slash")
    $fallbackEndpoint = [string]$UpdateCheckerType.GetProperty("GitHubApiLatestRelease", [System.Reflection.BindingFlags]"Public, Static").GetValue($null)
    Assert-Test "Config" "Malformed override without slash falls back to default" ($fallbackEndpoint -eq "https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest") "Got '$fallbackEndpoint'"
} finally {
    [Environment]::SetEnvironmentVariable("FLUENTFLYOUT_UPDATE_REPO", $null)
}


Write-Host "`n=== SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total Adversarial Tests: $($passCount + $failCount)"
Write-Host "Passed: $passCount" -ForegroundColor Green
Write-Host "Failed: $failCount" -ForegroundColor Red

if ($failCount -gt 0) {
    exit 1
}
exit 0
