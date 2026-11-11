# Independent Adversarial Test Suite for Reviewer M1 Iteration 2
$ErrorActionPreference = "Stop"

$assemblyPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"
if (-not (Test-Path -LiteralPath $assemblyPath)) {
    Write-Error "Assembly not found: $assemblyPath"
    exit 1
}

[System.Reflection.Assembly]::LoadFrom($assemblyPath) | Out-Null
$UpdateCheckerType = [Type]::GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService, FluentFlyout")
$parseMethod = $UpdateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]"Public, Static")
$isNewerMethod = $UpdateCheckerType.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]"Public, Static")

$pass = 0
$fail = 0

function Assert-Equal {
    param([string]$TestName, $Actual, $Expected)
    if ($Actual -eq $Expected) {
        $script:pass++
        Write-Host "[PASS] $TestName" -ForegroundColor Green
    } else {
        $script:fail++
        Write-Host "[FAIL] $TestName -> Actual: '$Actual', Expected: '$Expected'" -ForegroundColor Red
    }
}

function Test-RegexExtract {
    param([string]$TestName, [string]$Body, [string]$ExpectedSha)
    $jsonObj = @{
        body = $Body
        assets = @(
            @{
                name = "FluentFlyout_2.16.0_x64_Installer.zip"
                browser_download_url = "https://example.com/installer.zip"
            }
        )
    }
    $doc = [System.Text.Json.JsonDocument]::Parse(($jsonObj | ConvertTo-Json -Depth 5))
    $res = $parseMethod.Invoke($null, @($doc))
    Assert-Equal $TestName $res.Item2 ($ExpectedSha.ToLowerInvariant())
}

function Test-Version {
    param([string]$TestName, [string]$Current, [string]$Newest, [bool]$Expected)
    $res = [bool]$isNewerMethod.Invoke($null, @($Current, $Newest))
    Assert-Equal $TestName $res $Expected
}

Write-Host "--- TEST GROUP 1: ADVERSARIAL REGEX STRESS TESTS ---" -ForegroundColor Cyan
$h1 = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$h2 = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
$h3 = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"

# 1.1 Markdown Table with pipe separators
$tableBody = @"
| Architecture | Package | SHA-256 Checksum |
|---|---|---|
| ARM64 | FluentFlyout_arm64_Installer.zip | $h1 |
| x64 | FluentFlyout_x64_Installer.zip | $h2 |
"@
Test-RegexExtract "Markdown Table x64 row priority" $tableBody $h2

# 1.2 Windows \r\n line breaks
$crlfBody = "ARM64 checksum: $h1`r`nGitHub Release x64 checksum: $h2`r`n"
Test-RegexExtract "CRLF Line Breaks Multi-arch" $crlfBody $h2

# 1.3 Unix \n line breaks
$lfBody = "ARM64 checksum: $h1`nGitHub Release x64 checksum: $h2`n"
Test-RegexExtract "LF Line Breaks Multi-arch" $lfBody $h2

# 1.4 Parentheses and brackets around hash
Test-RegexExtract "Hash inside parentheses" "GitHub Release x64 ($h2)" $h2
Test-RegexExtract "Hash inside brackets" "GitHub Release x64 [$h2]" $h2
$backtickStr = 'GitHub Release x64 checksum: `' + $h2 + '`'
Test-RegexExtract "Hash inside backticks" $backtickStr $h2

# 1.5 Mixed case hex characters
$mixedHex = "aAbBcCdDeEfF01234567890123456789abcdef0123456789abcdef0123456789"
Test-RegexExtract "Mixed case hex normalization" "GitHub Release x64 checksum: $mixedHex" ($mixedHex.ToLowerInvariant())

# 1.6 Malformed hash length checks
$longHex = $h2 + "f"
$prefixedHex = "f" + $h2
$shortHex = $h2.Substring(0, 63)
Test-RegexExtract "Embedded in longer word (65 chars no boundary)" "GitHub Release x64 checksum: $longHex" ""
Test-RegexExtract "Embedded in longer word (prefixed)" "GitHub Release x64 checksum: $prefixedHex" ""
Test-RegexExtract "Too short (63 chars)" "GitHub Release x64 checksum: $shortHex" ""

# 1.7 Multiple x64 references: Workflow line vs generic line
$multiX64Body = @"
## Changelog
* Fixed x64 crash when reading cache
GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip
GitHub Release x64 checksum: $h2
"@
Test-RegexExtract "Changelog mentioning x64 before workflow checksum" $multiX64Body $h2

Write-Host "`n--- TEST GROUP 2: SEMVER 2.0.0 SPECIFICATION CONFORMANCE ---" -ForegroundColor Cyan
# SemVer 2.0.0 §11.4: 1.0.0-alpha < 1.0.0-alpha.1 < 1.0.0-alpha.beta < 1.0.0-beta < 1.0.0-beta.2 < 1.0.0-beta.11 < 1.0.0-rc.1 < 1.0.0
Test-Version "SemVer: alpha -> alpha.1" "1.0.0-alpha" "1.0.0-alpha.1" $true
Test-Version "SemVer: alpha.1 -> alpha" "1.0.0-alpha.1" "1.0.0-alpha" $false
Test-Version "SemVer: alpha.1 -> alpha.beta" "1.0.0-alpha.1" "1.0.0-alpha.beta" $true
Test-Version "SemVer: alpha.beta -> beta" "1.0.0-alpha.beta" "1.0.0-beta" $true
Test-Version "SemVer: beta -> beta.2" "1.0.0-beta" "1.0.0-beta.2" $true
Test-Version "SemVer: beta.2 -> beta.11 (Numeric comparison: 11 > 2)" "1.0.0-beta.2" "1.0.0-beta.11" $true
Test-Version "SemVer: beta.11 -> beta.2 (Numeric comparison)" "1.0.0-beta.11" "1.0.0-beta.2" $false
Test-Version "SemVer: beta.11 -> rc.1" "1.0.0-beta.11" "1.0.0-rc.1" $true
Test-Version "SemVer: rc.1 -> 1.0.0 (prerelease to stable)" "1.0.0-rc.1" "1.0.0" $true
Test-Version "SemVer: 1.0.0 -> rc.1 (stable to prerelease)" "1.0.0" "1.0.0-rc.1" $false

# Build metadata (§10: Build metadata SHOULD be ignored when determining version precedence)
Test-Version "Build metadata ignored on same version" "1.0.0+build1" "1.0.0+build2" $false
Test-Version "Build metadata with upgrade" "1.0.0+build1" "1.0.1+build2" $true
Test-Version "Prerelease with build metadata upgrade" "1.0.0-beta.1+exp.sha.5114f85" "1.0.0-beta.2+exp.sha.1234567" $true

# 1-part, 2-part, 3-part, 4-part equality & normalization
Test-Version "1-part same as 4-part: 2 vs 2.0.0.0" "2" "2.0.0.0" $false
Test-Version "1-part upgrade: 2 vs 3" "2" "3" $true
Test-Version "2-part same as 3-part: 2.16 vs 2.16.0" "2.16" "2.16.0" $false
Test-Version "4-part same: 2.16.0.0 vs 2.16.0" "2.16.0.0" "2.16.0" $false
Test-Version "4-part revision upgrade: 2.16.0.1 -> 2.16.0.2" "2.16.0.1" "2.16.0.2" $true

# Edge inputs
Test-Version "Invalid numbers: 2.16.0.abc" "2.16.0.abc" "2.16.1" $false
Test-Version "Too many parts: 1.2.3.4.5" "1.2.3.4.5" "2.0.0" $false
Test-Version "Whitespace around tokens" "  v2.16.0  " "  v2.16.1  " $true

Write-Host "`n--- SUMMARY ---" -ForegroundColor Cyan
Write-Host "Total: $($pass + $fail) | Passed: $pass | Failed: $fail"
if ($fail -gt 0) { exit 1 } else { exit 0 }
