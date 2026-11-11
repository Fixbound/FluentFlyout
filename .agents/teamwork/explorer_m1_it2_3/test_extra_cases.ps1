# Extended adversarial test suite for version normalization and prerelease semantics

. "E:\Programacion\FluentFlyout\.agents\teamwork\explorer_m1_it2_3\test_full_version_logic.ps1"

$extraTests = @(
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
    @{ Name = "Identical prerelease with different build metadata: 2.16.0-beta.1+001 -> 2.16.0-beta.1+002"; Cur = "2.16.0-beta.1+001"; New = "2.16.0-beta.1+002"; Exp = $false }
)

$passed = 0
$failed = 0
foreach ($t in $extraTests) {
    $act = IsNewerVersion $t.Cur $t.New
    if ($act -eq $t.Exp) {
        Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] $($t.Name): Expected $($t.Exp), Actual $act" -ForegroundColor Red
        $failed++
    }
}
Write-Host "`nExtra Tests Summary: $passed Passed, $failed Failed out of $($extraTests.Count)"
