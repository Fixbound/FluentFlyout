$source = Get-Content -Raw -Path "E:\Programacion\FluentFlyout\.agents\teamwork\explorer_m1_it2_3\VersionVerifier.cs"

Add-Type -TypeDefinition $source -Language CSharp

$verifier = [ExplorerM1It2Test.VersionVerifier]

$allTests = @(
    # Area 2 Challenger 1 tests:
    @{ Name = "Minor upgrade: 2.15.0 -> 2.16.0"; Cur = "2.15.0"; New = "2.16.0"; Exp = $true },
    @{ Name = "Patch upgrade: 2.16.0 -> 2.16.1"; Cur = "2.16.0"; New = "2.16.1"; Exp = $true },
    @{ Name = "Major upgrade: 2.16.0 -> 3.0.0"; Cur = "2.16.0"; New = "3.0.0"; Exp = $true },
    @{ Name = "Same version: 2.16.0 -> 2.16.0"; Cur = "2.16.0"; New = "2.16.0"; Exp = $false },
    @{ Name = "Downgrade: 2.16.0 -> 2.15.0"; Cur = "2.16.0"; New = "2.15.0"; Exp = $false },
    @{ Name = "v-prefix on both: v2.15.0 -> v2.16.0"; Cur = "v2.15.0"; New = "v2.16.0"; Exp = $true },
    @{ Name = "Uppercase V on current: V2.15.0 -> v2.16.0"; Cur = "V2.15.0"; New = "v2.16.0"; Exp = $true },
    @{ Name = "v on newest only: 2.15.0 -> v2.16.0"; Cur = "2.15.0"; New = "v2.16.0"; Exp = $true },
    @{ Name = "v on current only: v2.15.0 -> 2.16.0"; Cur = "v2.15.0"; New = "2.16.0"; Exp = $true },
    @{ Name = "4-part revision upgrade: 2.16.0.0 -> 2.16.0.1"; Cur = "2.16.0.0"; New = "2.16.0.1"; Exp = $true },
    @{ Name = "3-part vs 4-part same: 2.16.0 vs 2.16.0.0"; Cur = "2.16.0"; New = "2.16.0.0"; Exp = $false },
    @{ Name = "3-part vs 4-part upgrade: 2.16.0 vs 2.16.0.1"; Cur = "2.16.0"; New = "2.16.0.1"; Exp = $true },
    @{ Name = "2-part to 3-part: 2.15 vs 2.16.0"; Cur = "2.15"; New = "2.16.0"; Exp = $true },
    @{ Name = "2-part same: 2.16 vs 2.16.0"; Cur = "2.16"; New = "2.16.0"; Exp = $false },
    @{ Name = "Prerelease to higher patch: v2.16.0-beta.1 -> v2.16.1"; Cur = "v2.16.0-beta.1"; New = "v2.16.1"; Exp = $true },
    @{ Name = "Prerelease to stable: v2.16.0-beta.1 -> v2.16.0"; Cur = "v2.16.0-beta.1"; New = "v2.16.0"; Exp = $true },
    @{ Name = "Prerelease to next prerelease: v2.16.0-beta.1 -> v2.16.0-beta.2"; Cur = "v2.16.0-beta.1"; New = "v2.16.0-beta.2"; Exp = $true },
    @{ Name = "Stable to prerelease patch: v2.16.0 -> v2.16.1-rc1"; Cur = "v2.16.0"; New = "v2.16.1-rc1"; Exp = $true },
    @{ Name = "Build metadata: v2.15.0 -> v2.16.0+build123"; Cur = "v2.15.0"; New = "v2.16.0+build123"; Exp = $true },
    @{ Name = "Empty current version"; Cur = ""; New = "v2.16.0"; Exp = $true },
    @{ Name = "Empty newest version"; Cur = "v2.16.0"; New = ""; Exp = $false },
    @{ Name = "Invalid current string"; Cur = "invalid"; New = "v2.16.0"; Exp = $false },
    @{ Name = "Invalid newest string"; Cur = "v2.16.0"; New = "invalid"; Exp = $false },
    @{ Name = "Whitespace current"; Cur = "  v2.15.0  "; New = "v2.16.0"; Exp = $true },
    @{ Name = "Large major version jump"; Cur = "v2.16.0"; New = "v999.0.0"; Exp = $true },

    # Additional boundary & semantic tests:
    @{ Name = "Prerelease downgrade: beta.2 -> beta.1"; Cur = "v2.16.0-beta.2"; New = "v2.16.0-beta.1"; Exp = $false },
    @{ Name = "Prerelease downgrade: beta.1 -> alpha.1"; Cur = "v2.16.0-beta.1"; New = "v2.16.0-alpha.1"; Exp = $false },
    @{ Name = "Prerelease upgrade: alpha.1 -> beta.1"; Cur = "v2.16.0-alpha.1"; New = "v2.16.0-beta.1"; Exp = $true },
    @{ Name = "Numeric prerelease bump: beta.9 -> beta.10"; Cur = "v2.16.0-beta.9"; New = "v2.16.0-beta.10"; Exp = $true },
    @{ Name = "Numeric prerelease downgrade: beta.10 -> beta.9"; Cur = "v2.16.0-beta.10"; New = "v2.16.0-beta.9"; Exp = $false },
    @{ Name = "RC over Beta: beta.2 -> rc.1"; Cur = "v2.16.0-beta.2"; New = "v2.16.0-rc.1"; Exp = $true },
    @{ Name = "Beta under RC: rc.1 -> beta.2"; Cur = "v2.16.0-rc.1"; New = "v2.16.0-beta.2"; Exp = $false },
    @{ Name = "Stable to prerelease of same base: 2.16.0 -> 2.16.0-beta.1"; Cur = "2.16.0"; New = "2.16.0-beta.1"; Exp = $false },
    @{ Name = "Stable to prerelease with higher base: 2.16.0 -> 2.17.0-alpha.1"; Cur = "2.16.0"; New = "2.17.0-alpha.1"; Exp = $true },
    @{ Name = "Prerelease to stable with higher base: 2.16.0-beta.1 -> 2.17.0"; Cur = "2.16.0-beta.1"; New = "2.17.0"; Exp = $true },
    @{ Name = "Reverse 4-part same: 2.16.0.0 vs 2.16.0"; Cur = "2.16.0.0"; New = "2.16.0"; Exp = $false },
    @{ Name = "4-part downgrade: 2.16.0.1 vs 2.16.0"; Cur = "2.16.0.1"; New = "2.16.0"; Exp = $false },
    @{ Name = "4-part upgrade from 3-part: 2.16.0 vs 2.16.0.1"; Cur = "2.16.0"; New = "2.16.0.1"; Exp = $true },
    @{ Name = "1-part to 4-part same: 1.0 vs 1.0.0.0"; Cur = "1.0"; New = "1.0.0.0"; Exp = $false },
    @{ Name = "4-part to 1-part same: 1.0.0.0 vs 1.0"; Cur = "1.0.0.0"; New = "1.0"; Exp = $false },
    @{ Name = "4-part explicit: 1.2.3.4 -> 1.2.3.5"; Cur = "v1.2.3.4"; New = "v1.2.3.5"; Exp = $true },
    @{ Name = "4-part explicit downgrade: 1.2.3.5 -> 1.2.3.4"; Cur = "v1.2.3.5"; New = "v1.2.3.4"; Exp = $false },
    @{ Name = "Prerelease with build metadata upgrade: 2.16.0-beta.1+001 -> 2.16.0-beta.2+002"; Cur = "2.16.0-beta.1+001"; New = "2.16.0-beta.2+002"; Exp = $true },
    @{ Name = "Identical prerelease with different build metadata: 2.16.0-beta.1+001 -> 2.16.0-beta.1+002"; Cur = "2.16.0-beta.1+001"; New = "2.16.0-beta.1+002"; Exp = $false },
    @{ Name = "Large numeric prerelease: 2.16.0-preview.202611101234 -> 2.16.0-preview.202611105678"; Cur = "2.16.0-preview.202611101234"; New = "2.16.0-preview.202611105678"; Exp = $true }
)

$passed = 0
$failed = 0

foreach ($t in $allTests) {
    $act = [bool]$verifier::IsNewerVersion($t.Cur, $t.New)
    if ($act -eq $t.Exp) {
        Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] $($t.Name): Expected $($t.Exp), Actual $act (Cur='$($t.Cur)', New='$($t.New)')" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`nTotal Tests: $($allTests.Count) | Passed: $passed | Failed: $failed"
