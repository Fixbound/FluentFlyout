# Technical Analysis: Version Normalization & Prerelease Upgrade Semantics

**Author**: Explorer 3 (Milestone 1 Iteration 2)  
**Date**: 2026-11-10  
**Target File**: `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`  
**Focus**: Version Normalization (2-part, 3-part, 4-part) & Prerelease Upgrade Semantics in `IsNewerVersion`  
**Reference Findings**: Challenger 1 Failure Report (`challenge_report.md` and `handoff.md`)

---

## 1. Executive Summary

Empirical testing by Challenger 1 against the compiled `FluentFlyout.dll` revealed **four distinct failure modes** in the version comparison logic of `UpdateCheckerService.cs`:
1. **Component Discrepancy in `System.Version`**: `System.Version` assigns `-1` to undefined build or revision components. Consequently, `2.16.0.0 > 2.16.0` falsely evaluates to `true` (because `Revision` is `0 > -1`), as does `2.16.0 > 2.16` (because `Build` is `0 > -1`). This triggers false update prompts when the installed version is identical to the release version.
2. **Prerelease-to-Stable Upgrade Blindness**: Users testing beta builds (e.g. `v2.16.0-beta.1`) are blinded to final release updates (e.g. `v2.16.0`) because stripping the `-` suffix leaves identical base versions (`2.16.0` vs `2.16.0`), evaluating `newest > current` as `false`.
3. **Prerelease-to-Newer-Prerelease Blindness**: Users on an earlier prerelease build (e.g. `v2.16.0-beta.1`) cannot update to subsequent prereleases of the same base (e.g. `v2.16.0-beta.2`).
4. **SemVer 2.0.0 Build Metadata Parsing**: As detailed by Explorer 2, versions with `+` metadata (e.g. `v2.16.0+build123`) fail `Version.TryParse` completely.

### Critical Finding: Defects in Challenger 1's Proposed Fix
Critique of Challenger 1's proposed sketch (Section 6 of `challenge_report.md`):
- **Defect A (Prerelease Comparison Incompleteness)**: Challenger 1 proposed `if (currentIsPrerelease && !newestIsPrerelease) return true;`. While this fixes `beta.1 -> stable`, it evaluates `beta.1 -> beta.2` to `false`, leaving Challenger's own test harness test case (`Run-VersionTest "Prerelease to next prerelease: v2.16.0-beta.1 -> v2.16.0-beta.2"`) **failing**.
- **Defect B (Malformed String Fallback to 0.0.0.0)**: Challenger 1's proposed `NormalizeVersion` used a ternary fallback (`parts.Length > 0 && int.TryParse(parts[0], out var m) ? m : 0`). When given a non-numeric string like `"invalid"`, `int.TryParse` fails, but the ternary assigns `0`, causing `NormalizeVersion("invalid")` to return `true` with `0.0.0.0`. This causes `IsNewerVersion("invalid", "v2.16.0")` to return `true`, violating Challenger's own test case (`Run-VersionTest "Invalid current string" "invalid" "v2.16.0" $false`).

We have designed, implemented, and empirically verified a complete, robust fix that resolves all of these issues, achieving **45/45 passing tests (100% success rate)** across all standard, edge-case, and adversarial inputs.

---

## 2. Root Cause Analysis

### 2.1 System.Version Undefined Component Mechanics
In .NET, `System.Version` supports 2, 3, or 4 components. Undefined components are internally stored as `-1`:
```csharp
var v3 = new Version("2.16.0");    // Major=2, Minor=16, Build=0,  Revision=-1
var v4 = new Version("2.16.0.0");  // Major=2, Minor=16, Build=0,  Revision=0
```
When `System.Version.CompareTo` compares `v4` and `v3`:
1. `v4.Major == v3.Major` (2 == 2)
2. `v4.Minor == v3.Minor` (16 == 16)
3. `v4.Build == v3.Build` (0 == 0)
4. `v4.Revision.CompareTo(v3.Revision)` -> `0.CompareTo(-1)` -> `+1`!

Thus, `v4 > v3` returns `true`.
In FluentFlyout:
- `Package.appxmanifest` declares `Version="2.16.0.0"` (MSIX requires a 4-part version `Major.Minor.Build.Revision`).
- `MainWindow.xaml.cs` (line 210) extracts `Package.Current.Id.Version` and formats it as `$"v{version.Major}.{version.Minor}.{version.Build}"` (3 parts: `v2.16.0`).
- If an update endpoint or tag supplies a 4-part version with trailing zero (`2.16.0.0`), `System.Version` treats it as strictly greater than `2.16.0`, prompting the user to re-download the identical version.

### 2.2 Prerelease Suffix Stripping & Upgrade Semantics
Lines 270–301 of `UpdateCheckerService.cs` previously implemented:
```csharp
public static bool IsNewerVersion(string currentVersion, string newestVersion)
{
    string cleanCurrent = CleanVersionString(currentVersion);
    string cleanNewest = CleanVersionString(newestVersion);

    if (Version.TryParse(cleanCurrent, out var current) && Version.TryParse(cleanNewest, out var newest))
    {
        return newest > current;
    }
    return false;
}

private static string CleanVersionString(string version)
{
    if (string.IsNullOrWhiteSpace(version)) return "0.0.0.0";
    var v = version.Trim().TrimStart('v', 'V');
    var dashIndex = v.IndexOf('-');
    if (dashIndex >= 0)
    {
        v = v[..dashIndex];
    }
    return v;
}
```
When `currentVersion` is `v2.16.0-beta.1` and `newestVersion` is `v2.16.0`:
- `CleanVersionString` strips `-beta.1` -> `"2.16.0"`.
- `CleanVersionString("v2.16.0")` -> `"2.16.0"`.
- `current` = `2.16.0`, `newest` = `2.16.0`.
- `newest > current` evaluates to `false`.

According to **SemVer 2.0.0 Specification (Rule 11)**:
> *"A normal version number MUST take precedence over a pre-release version of the same normal version. Example: 1.0.0-alpha < 1.0.0."*

Therefore, `v2.16.0` is strictly newer than `v2.16.0-beta.1`. Stripping the prerelease tag without a fallback check completely blinds beta users to the release build.

Furthermore, when comparing two prereleases of the same base (e.g. `v2.16.0-beta.1` vs `v2.16.0-beta.2`), SemVer 2.0.0 mandates:
> *"Precedence for two pre-release versions with the same major, minor, and patch version MUST be determined by comparing each dot separated identifier from left to right... Identifiers consisting of only digits are compared numerically. Identifiers with letters or hyphens are compared lexically in ASCII sort order."*

---

## 3. Recommended Architecture & Fix Specification

To achieve full compliance with SemVer 2.0.0 and Windows MSIX 4-part versioning, the comparison logic must be decomposed into four coordinated helper methods:

```
                          ┌──────────────────────────┐
                          │   IsNewerVersion(cur,    │
                          │          new)            │
                          └─────────────┬────────────┘
                                        │
           ┌────────────────────────────┼───────────────────────────┐
           ▼                            ▼                           ▼
┌─────────────────────┐      ┌────────────────────┐      ┌────────────────────┐
│ CleanVersionString  │      │  NormalizeVersion  │      │ ExtractPrerelease  │
│  - Trim 'v'/'V'     │      │  - Split '.' (1-4) │      │  - Parse after '-' │
│  - Split '-' or '+' │      │  - Strict int check│      │  - Strip '+' meta  │
│  - Returns base str │      │  - Default omitted │      │  - Returns tag/null│
└─────────────────────┘      │    parts to 0      │      └─────────┬──────────┘
                             └──────────┬─────────┘                │
                                        │                          │
                                        ▼                          ▼
                             ┌────────────────────┐      ┌────────────────────┐
                             │ Compare 4-Part     │      │ ComparePrerelease  │
                             │ System.Version     │      │  - Dot-separated   │
                             │ (newest vs current)│      │  - Numeric (long)  │
                             │  - newest > cur: T │      │  - Lexical ASCII   │
                             │  - newest < cur: F │      │  - Identifier count│
                             │  - newest == cur:  ├─────►│  - Evaluates       │
                             └────────────────────┘      │    precedence      │
                                                         └────────────────────┘
```

### 3.1 Component Normalization (`NormalizeVersion`)
- Splits on `.` (supports 1, 2, 3, or 4 parts).
- Rejects strings with 0 or >4 parts.
- Uses an array `int[] nums = new int[4]` initialized to 0.
- Validates that every present part parses as a non-negative integer via `int.TryParse(parts[i], out nums[i]) && nums[i] >= 0`. If any part is invalid, returns `false`.
- Produces a fully populated 4-part `System.Version(nums[0], nums[1], nums[2], nums[3])`.
- **Result**: `2`, `2.16`, `2.16.0`, and `2.16.0.0` all normalize identically to `new Version(2, 16, 0, 0)`. Revision is `0`, never `-1`.

### 3.2 Prerelease Extraction (`ExtractPrerelease`)
- Trims whitespace and leading `v`/`V`.
- Locates the first `-` delimiter. If absent, returns `null` (or empty string).
- Strips any build metadata starting from `+`.
- Returns the clean prerelease string (e.g. `"beta.1"`).

### 3.3 SemVer Prerelease Comparison (`ComparePrerelease`)
- If strings are equal (case-insensitive), returns `0`.
- Splits both prerelease strings by `.` into identifiers.
- Compares identifiers left-to-right up to `min(lenA, lenB)`:
  - If both are numeric (using `long.TryParse` to prevent overflow on timestamps), compares numerically.
  - If one is numeric and the other non-numeric: numeric has **lower** precedence than non-numeric (SemVer §11.4).
  - If both are non-numeric: compares using `string.Compare(..., StringComparison.OrdinalIgnoreCase)`.
- If all compared identifiers are equal, the version with more identifiers has **higher** precedence (e.g. `beta < beta.1`).

### 3.4 Upgrade Logic in `IsNewerVersion`
1. Guard: If `newestVersion` is null or whitespace, return `false`.
2. Clean base version strings via `CleanVersionString` (strips `-` and `+`).
3. Normalize both base versions via `NormalizeVersion`. If either fails, return `false`.
4. If `newestBase > currentBase`, return `true` (e.g. `v2.16.0` -> `v2.16.1` or `v2.16.0` -> `v2.17.0-alpha.1`).
5. If `newestBase < currentBase`, return `false` (downgrade).
6. When `newestBase == currentBase`:
   - Extract prerelease identifiers `preCurrent` and `preNewest`.
   - **Case A**: `preCurrent != null && preNewest == null`: Current is prerelease, newest is stable release of same base -> **`true`** (prerelease to stable upgrade).
   - **Case B**: `preCurrent == null && preNewest != null`: Current is stable release, newest is prerelease of same base -> **`false`** (stable users do not downgrade to prerelease).
   - **Case C**: `preCurrent != null && preNewest != null`: Both are prereleases of same base -> **`ComparePrerelease(preCurrent, preNewest) < 0`** (newer prerelease).
   - **Case D**: Both are stable and base versions match (e.g. `2.16.0` vs `2.16.0.0`) -> **`false`** (same version).

---

## 4. Proposed Source Code Replacement

The following code should replace lines 270–301 in `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`:

```csharp
    /// <summary>
    /// Compares two version strings taking into account SemVer 2.0.0 rules,
    /// 2-part/3-part/4-part normalization (defaulting omitted parts to 0),
    /// and prerelease upgrade transitions.
    /// </summary>
    /// <param name="currentVersion">The currently installed application version</param>
    /// <param name="newestVersion">The remote release version to evaluate</param>
    /// <returns>True if newestVersion represents a newer upgrade; otherwise false.</returns>
    public static bool IsNewerVersion(string currentVersion, string newestVersion)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(newestVersion)) return false;

            string cleanCurrent = CleanVersionString(currentVersion);
            string cleanNewest = CleanVersionString(newestVersion);

            if (NormalizeVersion(cleanCurrent, out var current) && NormalizeVersion(cleanNewest, out var newest))
            {
                if (newest > current) return true;
                if (newest < current) return false;

                // Base versions are identical (e.g. 2.16.0 vs 2.16.0.0 or 2.16.0-beta.1 vs 2.16.0)
                string? preCurrent = ExtractPrerelease(currentVersion);
                string? preNewest = ExtractPrerelease(newestVersion);

                bool currentHasPre = !string.IsNullOrEmpty(preCurrent);
                bool newestHasPre = !string.IsNullOrEmpty(preNewest);

                // Case 1: Current is prerelease and newest is stable release of same base -> upgrade available
                if (currentHasPre && !newestHasPre) return true;

                // Case 2: Current is stable and newest is prerelease of same base -> not an upgrade
                if (!currentHasPre && newestHasPre) return false;

                // Case 3: Both are prereleases of same base -> compare prerelease identifiers
                if (currentHasPre && newestHasPre)
                {
                    return ComparePrerelease(preCurrent!, preNewest!) < 0;
                }

                // Case 4: Both are stable releases and identical (e.g. 2.16.0 vs 2.16.0.0) -> not an upgrade
                return false;
            }
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to compare versions: {currentVersion} vs {newestVersion}");
            return false;
        }
    }

    private static string CleanVersionString(string version)
    {
        if (string.IsNullOrWhiteSpace(version)) return "0.0.0.0";
        var v = version.Trim().TrimStart('v', 'V').Trim();
        var splitIndex = v.IndexOfAny(['-', '+']);
        if (splitIndex >= 0)
        {
            v = v[..splitIndex];
        }
        return v.Trim();
    }

    private static string? ExtractPrerelease(string version)
    {
        if (string.IsNullOrWhiteSpace(version)) return null;
        var v = version.Trim().TrimStart('v', 'V').Trim();
        var dashIndex = v.IndexOf('-');
        if (dashIndex < 0) return null;

        var pre = v[(dashIndex + 1)..];
        var plusIndex = pre.IndexOf('+');
        if (plusIndex >= 0)
        {
            pre = pre[..plusIndex];
        }
        return string.IsNullOrWhiteSpace(pre) ? null : pre.Trim();
    }

    private static int ComparePrerelease(string preA, string preB)
    {
        if (string.Equals(preA, preB, StringComparison.OrdinalIgnoreCase))
            return 0;

        var partsA = preA.Split('.');
        var partsB = preB.Split('.');
        int minLen = Math.Min(partsA.Length, partsB.Length);

        for (int i = 0; i < minLen; i++)
        {
            string a = partsA[i];
            string b = partsB[i];

            if (string.Equals(a, b, StringComparison.OrdinalIgnoreCase))
                continue;

            bool isNumA = long.TryParse(a, out long numA);
            bool isNumB = long.TryParse(b, out long numB);

            if (isNumA && isNumB)
            {
                int cmpNum = numA.CompareTo(numB);
                if (cmpNum != 0) return cmpNum;
                continue;
            }

            if (isNumA && !isNumB)
            {
                // SemVer 2.0 §11.4: Numeric identifiers have lower precedence than non-numeric identifiers
                return -1;
            }

            if (!isNumA && isNumB)
            {
                return 1;
            }

            int cmpStr = string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
            if (cmpStr != 0) return cmpStr;
        }

        return partsA.Length.CompareTo(partsB.Length);
    }

    private static bool NormalizeVersion(string cleaned, out Version version)
    {
        version = new Version(0, 0, 0, 0);
        if (string.IsNullOrWhiteSpace(cleaned)) return false;

        var parts = cleaned.Split('.');
        if (parts.Length == 0 || parts.Length > 4) return false;

        int[] nums = new int[4];
        for (int i = 0; i < parts.Length; i++)
        {
            if (!int.TryParse(parts[i], out nums[i]) || nums[i] < 0)
            {
                return false;
            }
        }

        version = new Version(nums[0], nums[1], nums[2], nums[3]);
        return true;
    }
```

---

## 5. Verification Matrix (45 Test Scenarios)

The proposed implementation was compiled using the modern C# compiler (`pwsh` / .NET 10) in `run_csharp_tests.ps1` and tested against all 25 Challenger 1 test cases plus 20 extended boundary and semantic test cases:

| Category | Test Case Name | Current | Newest | Expected | Actual | Result |
|---|---|---|---|---|---|:---:|
| Challenger 1 | Minor upgrade | `2.15.0` | `2.16.0` | True | True | **PASS** |
| Challenger 1 | Patch upgrade | `2.16.0` | `2.16.1` | True | True | **PASS** |
| Challenger 1 | Major upgrade | `2.16.0` | `3.0.0` | True | True | **PASS** |
| Challenger 1 | Same version | `2.16.0` | `2.16.0` | False | False | **PASS** |
| Challenger 1 | Downgrade | `2.16.0` | `2.15.0` | False | False | **PASS** |
| Challenger 1 | v-prefix on both | `v2.15.0` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | Uppercase V on current | `V2.15.0` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | v on newest only | `2.15.0` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | v on current only | `v2.15.0` | `2.16.0` | True | True | **PASS** |
| Challenger 1 | 4-part revision upgrade | `2.16.0.0` | `2.16.0.1` | True | True | **PASS** |
| Challenger 1 | **3-part vs 4-part same** | `2.16.0` | `2.16.0.0` | False | False | **PASS** |
| Challenger 1 | 3-part vs 4-part upgrade | `2.16.0` | `2.16.0.1` | True | True | **PASS** |
| Challenger 1 | 2-part to 3-part | `2.15` | `2.16.0` | True | True | **PASS** |
| Challenger 1 | **2-part same** | `2.16` | `2.16.0` | False | False | **PASS** |
| Challenger 1 | Prerelease to higher patch | `v2.16.0-beta.1` | `v2.16.1` | True | True | **PASS** |
| Challenger 1 | **Prerelease to stable** | `v2.16.0-beta.1` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | **Prerelease to next prerelease** | `v2.16.0-beta.1` | `v2.16.0-beta.2` | True | True | **PASS** |
| Challenger 1 | Stable to prerelease patch | `v2.16.0` | `v2.16.1-rc1` | True | True | **PASS** |
| Challenger 1 | **Build metadata (+)** | `v2.15.0` | `v2.16.0+build123` | True | True | **PASS** |
| Challenger 1 | Empty current version | `""` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | Empty newest version | `v2.16.0` | `""` | False | False | **PASS** |
| Challenger 1 | **Invalid current string** | `"invalid"` | `v2.16.0` | False | False | **PASS** |
| Challenger 1 | Invalid newest string | `v2.16.0` | `"invalid"` | False | False | **PASS** |
| Challenger 1 | Whitespace current | `"  v2.15.0  "` | `v2.16.0` | True | True | **PASS** |
| Challenger 1 | Large major version jump | `v2.16.0` | `v999.0.0` | True | True | **PASS** |
| Extended | Prerelease downgrade | `v2.16.0-beta.2` | `v2.16.0-beta.1` | False | False | **PASS** |
| Extended | Prerelease downgrade (alpha) | `v2.16.0-beta.1` | `v2.16.0-alpha.1` | False | False | **PASS** |
| Extended | Prerelease upgrade (alpha to beta) | `v2.16.0-alpha.1` | `v2.16.0-beta.1` | True | True | **PASS** |
| Extended | Numeric bump: beta.9 to beta.10 | `v2.16.0-beta.9` | `v2.16.0-beta.10` | True | True | **PASS** |
| Extended | Numeric downgrade: beta.10 to beta.9 | `v2.16.0-beta.10` | `v2.16.0-beta.9` | False | False | **PASS** |
| Extended | RC over Beta | `v2.16.0-beta.2` | `v2.16.0-rc.1` | True | True | **PASS** |
| Extended | Beta under RC | `v2.16.0-rc.1` | `v2.16.0-beta.2` | False | False | **PASS** |
| Extended | Stable to prerelease same base | `2.16.0` | `2.16.0-beta.1` | False | False | **PASS** |
| Extended | Stable to prerelease higher base | `2.16.0` | `2.17.0-alpha.1` | True | True | **PASS** |
| Extended | Prerelease to stable higher base | `2.16.0-beta.1` | `2.17.0` | True | True | **PASS** |
| Extended | Reverse 4-part same | `2.16.0.0` | `2.16.0` | False | False | **PASS** |
| Extended | 4-part downgrade | `2.16.0.1` | `2.16.0` | False | False | **PASS** |
| Extended | 4-part upgrade from 3-part | `2.16.0` | `2.16.0.1` | True | True | **PASS** |
| Extended | 1-part to 4-part same | `1.0` | `1.0.0.0` | False | False | **PASS** |
| Extended | 4-part to 1-part same | `1.0.0.0` | `1.0` | False | False | **PASS** |
| Extended | 4-part explicit bump | `v1.2.3.4` | `v1.2.3.5` | True | True | **PASS** |
| Extended | 4-part explicit downgrade | `v1.2.3.5` | `v1.2.3.4` | False | False | **PASS** |
| Extended | Prerelease + metadata upgrade | `2.16.0-beta.1+001` | `2.16.0-beta.2+002` | True | True | **PASS** |
| Extended | Metadata differ only (same prec.) | `2.16.0-beta.1+001` | `2.16.0-beta.1+002` | False | False | **PASS** |
| Extended | 64-bit timestamp prerelease | `2.16.0-p.202611101234` | `2.16.0-p.202611105678` | True | True | **PASS** |

**Total Tests**: 45  
**Passed**: 45 (100%)  
**Failed**: 0  
