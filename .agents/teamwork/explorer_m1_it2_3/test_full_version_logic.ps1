# Prototype of full SemVer-aware IsNewerVersion

function CleanVersionString([string]$version) {
    if ([string]::IsNullOrWhiteSpace($version)) { return "0.0.0.0" }
    $v = $version.Trim().TrimStart('v', 'V')
    $splitIndex = $v.IndexOfAny(@('-', '+'))
    if ($splitIndex -ge 0) {
        $v = $v.Substring(0, $splitIndex)
    }
    return $v
}

function ExtractPrerelease([string]$version) {
    if ([string]::IsNullOrWhiteSpace($version)) { return [string]::Empty }
    $v = $version.Trim().TrimStart('v', 'V')
    $dashIndex = $v.IndexOf('-')
    if ($dashIndex -lt 0) { return [string]::Empty }
    $pre = $v.Substring($dashIndex + 1)
    $plusIndex = $pre.IndexOf('+')
    if ($plusIndex -ge 0) {
        $pre = $pre.Substring(0, $plusIndex)
    }
    return $pre.Trim()
}

function ComparePrerelease([string]$preA, [string]$preB) {
    if ($preA -eq $preB) { return 0 }
    $partsA = $preA.Split('.')
    $partsB = $preB.Split('.')
    $minLen = [Math]::Min($partsA.Length, $partsB.Length)

    for ($i = 0; $i -lt $minLen; $i++) {
        $a = $partsA[$i]
        $b = $partsB[$i]
        if ($a -eq $b) { continue }

        $numA = 0
        $numB = 0
        $isNumA = [int]::TryParse($a, [ref]$numA)
        $isNumB = [int]::TryParse($b, [ref]$numB)

        if ($isNumA -and $isNumB) {
            return $numA.CompareTo($numB)
        }
        if ($isNumA -and -not $isNumB) {
            return -1 # Numeric has lower precedence than non-numeric in SemVer
        }
        if (-not $isNumA -and $isNumB) {
            return 1 # Non-numeric has higher precedence than numeric in SemVer
        }

        $cmp = [string]::Compare($a, $b, [StringComparison]::OrdinalIgnoreCase)
        if ($cmp -ne 0) { return $cmp }
    }

    return $partsA.Length.CompareTo($partsB.Length)
}

function NormalizeVersion([string]$cleaned, [ref]$version) {
    $version.Value = [Version]::new(0, 0, 0, 0)
    if ([string]::IsNullOrWhiteSpace($cleaned)) { return $false }
    $parts = $cleaned.Split('.')
    if ($parts.Length -eq 0 -or $parts.Length -gt 4) { return $false }
    $major = 0; $minor = 0; $build = 0; $rev = 0
    if ($parts.Length -gt 0 -and -not [int]::TryParse($parts[0], [ref]$major)) { return $false }
    if ($parts.Length -gt 1 -and -not [int]::TryParse($parts[1], [ref]$minor)) { return $false }
    if ($parts.Length -gt 2 -and -not [int]::TryParse($parts[2], [ref]$build)) { return $false }
    if ($parts.Length -gt 3 -and -not [int]::TryParse($parts[3], [ref]$rev)) { return $false }
    $version.Value = [Version]::new($major, $minor, $build, $rev)
    return $true
}

function IsNewerVersion([string]$currentVersion, [string]$newestVersion) {
    try {
        if ([string]::IsNullOrWhiteSpace($newestVersion)) { return $false }
        # If current is empty or whitespace, any valid newest version is an update
        $cleanCurrent = CleanVersionString $currentVersion
        $cleanNewest = CleanVersionString $newestVersion

        $cur = [Version]::new(0,0,0,0)
        $new = [Version]::new(0,0,0,0)

        if (-not (NormalizeVersion $cleanCurrent ([ref]$cur))) { return $false }
        if (-not (NormalizeVersion $cleanNewest ([ref]$new))) { return $false }

        if ($new -gt $cur) { return $true }
        if ($new -lt $cur) { return $false }

        # Base versions are identical (e.g. 2.16.0 == 2.16.0)
        $preCurrent = ExtractPrerelease $currentVersion
        $preNewest = ExtractPrerelease $newestVersion

        $currentHasPre = -not [string]::IsNullOrEmpty($preCurrent)
        $newestHasPre = -not [string]::IsNullOrEmpty($preNewest)

        # 1. Prerelease to stable release upgrade: v2.16.0-beta.1 -> v2.16.0
        if ($currentHasPre -and -not $newestHasPre) { return $true }

        # 2. Stable release to prerelease is NOT an upgrade: v2.16.0 -> v2.16.0-beta.1
        if (-not $currentHasPre -and $newestHasPre) { return $false }

        # 3. Both are prereleases: v2.16.0-beta.1 -> v2.16.0-beta.2
        if ($currentHasPre -and $newestHasPre) {
            return (ComparePrerelease $preCurrent $preNewest) -lt 0
        }

        # 4. Both are stable and identical: 2.16.0 vs 2.16.0.0
        return $false
    } catch {
        return $false
    }
}

# Run all 25 tests from Challenger 1 harness
$tests = @(
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
    @{ Name = "Large major version jump"; Cur = "v2.16.0"; New = "v999.0.0"; Exp = $true }
)

$passed = 0
$failed = 0
foreach ($t in $tests) {
    $act = IsNewerVersion $t.Cur $t.New
    if ($act -eq $t.Exp) {
        Write-Host "[PASS] $($t.Name)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "[FAIL] $($t.Name): Expected $($t.Exp), Actual $act" -ForegroundColor Red
        $failed++
    }
}

Write-Host "`nSummary: $passed Passed, $failed Failed out of $($tests.Count)"
