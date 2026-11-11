# Forensic Auditor Independent Behavioral & Reflection Test Suite
param()

$ErrorActionPreference = 'Stop'
$dllPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"

Write-Host "Loading assembly: $dllPath" -ForegroundColor Cyan
if (-not (Test-Path $dllPath)) {
    Write-Error "Assembly not found at $dllPath"
    exit 1
}

$assembly = [System.Reflection.Assembly]::LoadFrom($dllPath)
$updateCheckerType = $assembly.GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService")
if ($null -eq $updateCheckerType) {
    Write-Error "Type FluentFlyoutWPF.Classes.Services.UpdateCheckerService not found"
    exit 1
}

$isNewerVersionMethod = $updateCheckerType.GetMethod("IsNewerVersion", [System.Reflection.BindingFlags]'Public,Static')
$parseInstallerAssetMethod = $updateCheckerType.GetMethod("ParseInstallerAsset", [System.Reflection.BindingFlags]'Public,Static')

$totalTests = 0
$passedTests = 0
$failedTests = 0

function Assert-Test([string]$desc, $expected, $actual) {
    $script:totalTests++
    $pass = ($expected -eq $actual)
    if ($pass) {
        $script:passedTests++
        Write-Host "  [PASS] ${desc}: '$actual'" -ForegroundColor Green
    } else {
        $script:failedTests++
        Write-Host "  [FAIL] ${desc}: Expected '$expected', got '$actual'" -ForegroundColor Red
    }
}

Write-Host "`n=== GROUP 1: SemVer 2.0.0 & Normalization Reflection Tests ===" -ForegroundColor Yellow

$versionCases = @(
    # Standard upgrades
    @{ Current = "2.15.0"; Remote = "2.16.0"; Expected = $true; Name = "Minor bump" },
    @{ Current = "2.16.0"; Remote = "2.16.1"; Expected = $true; Name = "Patch bump" },
    @{ Current = "2.16.0"; Remote = "3.0.0";  Expected = $true; Name = "Major bump" },
    @{ Current = "2.16.0"; Remote = "2.16.0"; Expected = $false; Name = "Exact match" },
    @{ Current = "2.16.0"; Remote = "2.15.0"; Expected = $false; Name = "Downgrade" },
    
    # Normalization (2-part, 3-part, 4-part)
    @{ Current = "2.16"; Remote = "2.16.0"; Expected = $false; Name = "2-part vs 3-part equal" },
    @{ Current = "2.16.0"; Remote = "2.16.0.0"; Expected = $false; Name = "3-part vs 4-part equal" },
    @{ Current = "2.16"; Remote = "2.16.1"; Expected = $true; Name = "2-part vs 3-part bump" },
    @{ Current = "2.16.0"; Remote = "2.16.0.1"; Expected = $true; Name = "3-part vs 4-part bump" },
    
    # Prefix and formatting
    @{ Current = "v2.15.0"; Remote = "v2.16.0"; Expected = $true; Name = "v-prefix both" },
    @{ Current = "V2.15.0"; Remote = "v2.16.0"; Expected = $true; Name = "Uppercase V on current" },
    @{ Current = "  2.15.0  "; Remote = " 2.16.0 "; Expected = $true; Name = "Whitespace trimmed" },
    
    # SemVer Prerelease Transitions
    @{ Current = "2.16.0-beta.1"; Remote = "2.16.0"; Expected = $true; Name = "Prerelease to stable of same base" },
    @{ Current = "2.16.0-beta.1"; Remote = "2.16.0-beta.2"; Expected = $true; Name = "Prerelease bump numeric" },
    @{ Current = "2.16.0-beta.2"; Remote = "2.16.0-beta.1"; Expected = $false; Name = "Prerelease downgrade numeric" },
    @{ Current = "2.16.0-alpha.1"; Remote = "2.16.0-beta.1"; Expected = $true; Name = "Prerelease bump lexical" },
    @{ Current = "2.16.0-beta.1"; Remote = "2.16.0-alpha.1"; Expected = $false; Name = "Prerelease downgrade lexical" },
    @{ Current = "2.16.0"; Remote = "2.16.0-beta.1"; Expected = $false; Name = "Stable to prerelease of same base" },
    @{ Current = "2.16.0"; Remote = "2.17.0-beta.1"; Expected = $true; Name = "Stable to prerelease of higher base" },
    @{ Current = "2.16.0-rc.1"; Remote = "2.16.1"; Expected = $true; Name = "Prerelease to higher patch" },
    
    # Build Metadata (+build)
    @{ Current = "2.15.0"; Remote = "2.16.0+build123"; Expected = $true; Name = "Build metadata stripped on remote" },
    @{ Current = "2.15.0+exp.sha.1"; Remote = "2.16.0"; Expected = $true; Name = "Build metadata stripped on current" },
    @{ Current = "2.16.0+build1"; Remote = "2.16.0+build2"; Expected = $false; Name = "Same base with different build meta" },
    @{ Current = "2.16.0-beta.1+exp1"; Remote = "2.16.0-beta.2+exp2"; Expected = $true; Name = "Prerelease with build metadata" },
    
    # Invalid and boundary cases
    @{ Current = ""; Remote = "2.16.0"; Expected = $true; Name = "Empty current string (defaults 0.0.0.0)" },
    @{ Current = "2.16.0"; Remote = ""; Expected = $false; Name = "Empty remote string" },
    @{ Current = "invalid"; Remote = "2.16.0"; Expected = $false; Name = "Invalid current token fails NormalizeVersion" },
    @{ Current = "2.16.0"; Remote = "invalid"; Expected = $false; Name = "Invalid remote token fails NormalizeVersion" },
    @{ Current = "2.16.0"; Remote = "2.16.0.0.1"; Expected = $false; Name = "5-part version rejected" },
    @{ Current = "2.16.0"; Remote = "-1.0.0"; Expected = $false; Name = "Negative version component rejected" }
)

foreach ($tc in $versionCases) {
    $res = $isNewerVersionMethod.Invoke($null, @($tc.Current, $tc.Remote))
    Assert-Test $tc.Name $tc.Expected $res
}

Write-Host "`n=== GROUP 2: SHA-256 Multi-Tier Hierarchy & Asset Parsing Tests ===" -ForegroundColor Yellow

$hashA = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
$hashB = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
$hashC = "cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc"
$hashD = "dddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddddd"

$assetTests = @(
    @{
        Name = "Tier 1: GitHub Release x64 line matched"
        Body = "Release notes summary`nGitHub Release x64 checksum: $hashA`nOther arch info"
        ExpectedHash = $hashA
    },
    @{
        Name = "Tier 1: Multi-arch ARM64 listed before x64 in workflow notes"
        Body = "GitHub Release arm64 checksum: $hashB`nGitHub Release x64 checksum: $hashA"
        ExpectedHash = $hashA
    },
    @{
        Name = "Tier 2: x64 keyword on line before colon"
        Body = "Notes:`nx64 sha-256: $hashB`nARM64 sha-256: $hashC"
        ExpectedHash = $hashB
    },
    @{
        Name = "Tier 2: Markdown bold x64 header"
        Body = "**x64 Checksum**: " + '`' + $hashC + '`'
        ExpectedHash = $hashC
    },
    @{
        Name = "Tier 3: Fallback single arch checksum header"
        Body = "Single build release`nChecksum: $hashD"
        ExpectedHash = $hashD
    },
    @{
        Name = "Tier 4: Generic 64-hex fallback with word boundaries"
        Body = "Here is the release binary with digest $hashA."
        ExpectedHash = $hashA
    },
    @{
        Name = "Overlong 65-hex string not matched by word boundary regex"
        Body = "Hash is " + $hashA + "f"
        ExpectedHash = ""
    },
    @{
        Name = "Truncated 63-hex string not matched"
        Body = "Hash is " + $hashA.Substring(0, 63)
        ExpectedHash = ""
    }
)

foreach ($at in $assetTests) {
    $json = [System.Text.Json.JsonDocument]::Parse(@"
{
    "assets": [
        {
            "name": "FluentFlyout_2.16.0_x64_Installer.zip",
            "browser_download_url": "https://example.com/installer.zip"
        }
    ],
    "body": $($at.Body | ConvertTo-Json)
}
"@)
    $resTuple = $parseInstallerAssetMethod.Invoke($null, @($json))
    $actualHash = $resTuple.Item2
    Assert-Test $at.Name $at.ExpectedHash $actualHash
}

Write-Host "`n=== Test Run Summary ===" -ForegroundColor Cyan
Write-Host "Total: $totalTests | Passed: $passedTests | Failed: $failedTests"
if ($failedTests -gt 0) {
    exit 1
} else {
    exit 0
}
