# Technical Analysis: SemVer Build Metadata Parsing & Delimiters in UpdateCheckerService

**Agent**: Explorer M1 Iteration 2 (Instance 2)  
**Role**: SemVer & Build Metadata Specialist  
**Working Directory**: `E:\Programacion\FluentFlyout\.agents\teamwork\explorer_m1_it2_2\`  
**Target Codebase**: `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`  
**Date**: 2026-11-10  

---

## 1. Executive Summary

During Milestone 1 verification, Challenger 1 identified **Failure 3** in `UpdateCheckerService.cs`:
> `CleanVersionString` only splits on `-`, causing SemVer 2.0.0 build metadata (`+build123`) to fail `Version.TryParse` in `System.Version`.

This investigation conducted a comprehensive code audit of `CleanVersionString` and its callers, evaluated delimiter behavior against the SemVer 2.0.0 specification, explored all edge cases, and constructed an empirical test suite.

### Key Discoveries:
1. **Root Cause Confirmed**: `CleanVersionString` in `UpdateCheckerService.cs:294` uses `var dashIndex = v.IndexOf('-')`, completely ignoring `+`. When a version contains build metadata (`v2.16.0+build123` or `2.16.0+20261110.1`), `+` remains in the string, causing subsequent parsing to fail and silently reporting `IsUpdateAvailable = false`.
2. **Optimal Fix Strategy Verified**: Updating the delimiter search to `v.IndexOfAny(['-', '+'])` accompanied by defensive trimming solves Failure 3 cleanly and with zero heap allocation in .NET 10.
3. **CRITICAL DISCOVERY — Flaws in Challenger 1's Recommended Snippet**:
   Empirical testing of the code proposed by Challenger 1 in Section 6 of `challenge_report.md` revealed **2 critical regressions against Challenger 1's own 25 test cases**:
   - **Flaw 1 (Challenger Test V7)**: Challenger's `NormalizeVersion` defaults unparseable tokens to `0` instead of failing, treating `"invalid"` as `0.0.0.0`. This causes `IsNewerVersion("invalid", "v2.16.0")` to return `True` instead of expected `False`.
   - **Flaw 2 (Challenger Test V5)**: Challenger's `IsNewerVersion` only handles prerelease-to-stable upgrades (`currentIsPrerelease && !newestIsPrerelease`). When both versions are prereleases of the same base version (`v2.16.0-beta.1 -> v2.16.0-beta.2`), it returns `False` instead of expected `True`.
4. **Verified Solution**: A complete, robust implementation was developed and tested against all 25 original Challenger 1 tests plus 12 additional SemVer build metadata edge tests (37 tests total), achieving a **100% pass rate (37/37 PASS)**.

---

## 2. Codebase Investigation: `CleanVersionString`

### 2.1 Current Implementation
`FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs` (lines 290–300):

```csharp
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

### 2.2 Call Chain & Failure Mechanism
- In `UpdateCheckerService.cs:98`, `IsNewerVersion(currentVersion, result.NewestVersion)` is called.
- `IsNewerVersion` invokes `CleanVersionString(currentVersion)` and `CleanVersionString(newestVersion)`.
- If `newestVersion` is `"v2.16.0+build123"`:
  - `version.Trim().TrimStart('v', 'V')` yields `"2.16.0+build123"`.
  - `dashIndex = v.IndexOf('-')` evaluates to `-1` because there is no hyphen.
  - `CleanVersionString` returns `"2.16.0+build123"`.
  - `Version.TryParse("2.16.0+build123", out _)` returns `false` (`System.Version` only accepts digit components delimited strictly by `.`).
  - `IsNewerVersion` returns `false`.
  - The updater concludes no update is available.

---

## 3. SemVer 2.0.0 Specification & Delimiter Analysis

### 3.1 Grammar of Semantic Versioning 2.0.0
According to [SemVer 2.0.0](https://semver.org/):
```
<valid semver> ::= <version core>
                 | <version core> "-" <pre-release>
                 | <version core> "+" <build>
                 | <version core> "-" <pre-release> "+" <build>

<version core> ::= <major> "." <minor> "." <patch>
<pre-release>  ::= <dot-separated pre-release identifiers>
<build>        ::= <dot-separated build identifiers>
```
Identifiers comprise only ASCII alphanumerics and hyphens `[0-9A-Za-z-]`.

### 3.2 Key Rules from the Specification
1. **Item 9 (Pre-release Delimiter)**: Pre-release version is denoted by appending a hyphen `'-'` immediately following the patch version.
2. **Item 10 (Build Metadata Delimiter)**: Build metadata is denoted by appending a plus sign `'+'` immediately following the patch or pre-release version.
3. **Item 10 (Precedence of Build Metadata)**: "Build metadata MUST be ignored when determining version precedence. Therefore, two versions that differ only in the build metadata, have the same precedence."
4. **Hyphens within Build Metadata**: Spec Item 10 allows ASCII hyphens inside build identifiers (e.g. `1.0.0+build-123` or `1.0.0+20261110-sha.abc`).

### 3.3 Delimiter Ordering & Why `IndexOfAny` is Required
Consider possible combinations:
- Standard release: `2.16.0` (no delimiters)
- Prerelease only: `2.16.0-beta.1` (delimiter `-` at index 6)
- Build metadata only: `2.16.0+build123` (delimiter `+` at index 6)
- Both prerelease and build metadata: `2.16.0-beta.1+build123` (delimiter `-` at index 6, `+` at index 14)
- Build metadata containing a hyphen: `2.16.0+build-123` (delimiter `+` at index 6, `-` at index 12)

If code naively checked `IndexOf('-')` before checking `'+'`, for `2.16.0+build-123` it would split at index 12, leaving `"2.16.0+build"`, which would still fail!

By using `v.IndexOfAny(['-', '+'])`:
`IndexOfAny` searches from index 0 left-to-right and returns the index of the **first occurring delimiter**.
- For `2.16.0-beta.1+build123`: `-` is encountered first at index 6. Truncation yields `"2.16.0"`.
- For `2.16.0+build-123`: `+` is encountered first at index 6. Truncation yields `"2.16.0"`.

---

## 4. Evaluation of Fix Strategy for `CleanVersionString`

### 4.1 Recommended Definition of `CleanVersionString`
```csharp
private static string CleanVersionString(string version)
{
    if (string.IsNullOrWhiteSpace(version)) return "0.0.0.0";
    var v = version.Trim().TrimStart('v', 'V');
    var splitIndex = v.IndexOfAny(['-', '+']);
    if (splitIndex >= 0)
    {
        v = v[..splitIndex];
    }
    return v.Trim();
}
```

### 4.2 Behavior Across All Inputs

| Input String | `v` after Prefix Trim | `splitIndex` | Delimiter Found | Output | Parse Result |
|--------------|-----------------------|:------------:|:---------------:|:------:|:------------:|
| `""` | - | - | - | `"0.0.0.0"` | Valid (0.0.0.0) |
| `"   "` | - | - | - | `"0.0.0.0"` | Valid (0.0.0.0) |
| `"v2.16.0"` | `"2.16.0"` | -1 | None | `"2.16.0"` | Valid (2.16.0.0) |
| `"V2.16.0"` | `"2.16.0"` | -1 | None | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0-beta.1"` | `"2.16.0-beta.1"` | 6 | `'-'` | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0+build123"` | `"2.16.0+build123"` | 6 | `'+'` | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0-rc.1+build123"` | `"2.16.0-rc.1+build123"` | 6 | `'-'` | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0+build-123"` | `"2.16.0+build-123"` | 6 | `'+'` | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0 -beta"` | `"2.16.0 -beta"` | 7 | `'-'` | `"2.16.0"` | Valid (2.16.0.0) |
| `"2.16.0.1"` | `"2.16.0.1"` | -1 | None | `"2.16.0.1"` | Valid (2.16.0.1) |
| `"2.16"` | `"2.16"` | -1 | None | `"2.16"` | Valid (2.16.0.0) |
| `"invalid"` | `"invalid"` | -1 | None | `"invalid"` | Invalid (fails parse) |
| `"v"` | `""` | -1 | None | `""` | Invalid (fails parse) |

---

## 5. Critical Discovery: Regressions in Challenger 1's Proposed Fix

In Section 6 of `challenge_report.md`, Challenger 1 recommended:
```csharp
private static bool NormalizeVersion(string cleaned, out Version version)
{
    version = new Version(0, 0, 0, 0);
    var parts = cleaned.Split('.');
    if (parts.Length == 0 || parts.Length > 4) return false;
    int major = parts.Length > 0 && int.TryParse(parts[0], out var m) ? m : 0;
    int minor = parts.Length > 1 && int.TryParse(parts[1], out var n) ? n : 0;
    int build = parts.Length > 2 && int.TryParse(parts[2], out var b) ? b : 0;
    int rev = parts.Length > 3 && int.TryParse(parts[3], out var r) ? r : 0;
    version = new Version(major, minor, build, rev);
    return true;
}
```

### Flaw A: Masking Invalid Version Strings as `0.0.0.0`
- If `cleaned` is `"invalid"`, `parts[0]` is `"invalid"`.
- `int.TryParse("invalid", out var m)` returns `false`.
- Instead of aborting and returning `false`, the ternary operator assigns `major = 0`.
- `NormalizeVersion` returns `true` with `version = 0.0.0.0`!
- Consequence: In `IsNewerVersion("invalid", "v2.16.0")`:
  - `cleanCurrent` = `"invalid"` -> normalized to `0.0.0.0`.
  - `cleanNewest` = `"2.16.0"` -> normalized to `2.16.0.0`.
  - `2.16.0.0 > 0.0.0.0` evaluates to **`True`**!
  - Challenger 1's test harness line 250 explicitly tests:
    `Run-VersionTest "Invalid current string" "invalid" "v2.16.0" $false`
  - **Result: REGRESSION / TEST FAILURE**.

**Fix**:
Every existing token in `parts` MUST parse into a non-negative integer. If any token fails `int.TryParse`, `NormalizeVersion` must immediately return `false`.

```csharp
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

### Flaw B: Prerelease-to-Prerelease Comparison Ignored
Challenger 1's recommended `IsNewerVersion` code:
```csharp
if (newest == current)
{
    bool currentIsPrerelease = currentVersion.Contains('-');
    bool newestIsPrerelease = newestVersion.Contains('-');
    if (currentIsPrerelease && !newestIsPrerelease) return true;
}
```
- When comparing `v2.16.0-beta.1` to `v2.16.0-beta.2`:
  - `currentIsPrerelease` is `true`.
  - `newestIsPrerelease` is `true`.
  - `!newestIsPrerelease` is `false`.
  - The condition evaluates to `false` and the method returns `false`.
  - Challenger 1's test harness line 241 explicitly tests:
    `Run-VersionTest "Prerelease to next prerelease: v2.16.0-beta.1 -> v2.16.0-beta.2" "v2.16.0-beta.1" "v2.16.0-beta.2" $true`
  - **Result: REGRESSION / TEST FAILURE**.

**Fix**:
When base versions match and both versions are prereleases, compare their prerelease identifiers according to SemVer 2.0.0 rules:

```csharp
private static string? ExtractPrerelease(string version)
{
    if (string.IsNullOrWhiteSpace(version)) return null;
    var v = version.Trim().TrimStart('v', 'V');
    var plusIndex = v.IndexOf('+');
    if (plusIndex >= 0)
    {
        v = v[..plusIndex];
    }
    var dashIndex = v.IndexOf('-');
    if (dashIndex >= 0)
    {
        return v[(dashIndex + 1)..];
    }
    return null;
}

private static int ComparePrerelease(string pre1, string pre2)
{
    var parts1 = pre1.Split('.');
    var parts2 = pre2.Split('.');
    int minLength = Math.Min(parts1.Length, parts2.Length);

    for (int i = 0; i < minLength; i++)
    {
        string p1 = parts1[i];
        string p2 = parts2[i];

        bool isNum1 = int.TryParse(p1, out int num1);
        bool isNum2 = int.TryParse(p2, out int num2);

        if (isNum1 && isNum2)
        {
            if (num1 != num2) return num1.CompareTo(num2);
        }
        else if (isNum1 && !isNum2)
        {
            return -1; // numeric identifiers have lower precedence than non-numeric
        }
        else if (!isNum1 && isNum2)
        {
            return 1;
        }
        else
        {
            int cmp = string.Compare(p1, p2, StringComparison.OrdinalIgnoreCase);
            if (cmp != 0) return cmp;
        }
    }

    return parts1.Length.CompareTo(parts2.Length);
}
```

---

## 6. Empirical Verification Results

A standalone reproduction harness was built in `E:\Programacion\FluentFlyout\.agents\teamwork\explorer_m1_it2_2\run_complete_tests.ps1`.

### 6.1 Test Suite Breakdown
1. **Area 2 Version Tests from Challenger 1 Harness (25 tests)**:
   - All standard SemVer upgrades (minor, patch, major, same, downgrade)
   - All `v` and `V` prefix variations
   - All 4-part version variations (`2.16.0` vs `2.16.0.0`, `2.16.0.0` vs `2.16.0.1`)
   - All 2-part version variations (`2.15` vs `2.16.0`, `2.16` vs `2.16.0`)
   - All prerelease tags (`beta.1 -> patch`, `beta.1 -> stable`, `beta.1 -> beta.2`, `stable -> rc1`)
   - SemVer build metadata (`v2.15.0 -> v2.16.0+build123`)
   - Boundary & invalid inputs (empty current, empty newest, invalid current, invalid newest, whitespace, large jump)

2. **Additional SemVer Build Metadata Edge Tests (12 tests)**:
   - Complex build metadata with dots: `v2.15.0 -> v2.16.0+exp.sha.5114f85`
   - Prerelease and build metadata together: `v2.15.0 -> v2.16.0-alpha+001`
   - Timestamp build metadata: `v2.15.0 -> v2.16.0+20130313144700`
   - Beta with build metadata to stable: `v2.16.0-beta+exp.sha.5114f85 -> v2.16.0`
   - Differ ONLY in build metadata (same precedence per SemVer): `v2.16.0+build.1 -> v2.16.0+build.2` (Expected `False`)
   - Upgrade with build metadata on both: `v2.15.0+build.1 -> v2.16.0+build.2` (Expected `True`)
   - Hyphen inside build metadata: `v2.15.0 -> v2.16.0+build-42`
   - Underscore inside build metadata: `v2.15.0 -> v2.16.0+build_42`
   - Newest has build metadata only (same base): `v2.16.0 -> v2.16.0+build` (Expected `False`)
   - Current has build metadata only (same base): `v2.16.0+build -> v2.16.0` (Expected `False`)
   - Prerelease comparison ignoring build metadata: `v2.16.0-alpha.1+build.1 -> v2.16.0-alpha.2+build.2` (Expected `True`)
   - Prerelease downgrade ignoring build metadata: `v2.16.0-alpha.2+build.1 -> v2.16.0-alpha.1+build.2` (Expected `False`)

### 6.2 Test Results
- **Challenger 1 Proposed Snippet**: 23 Passed, 2 Failed.
- **Explorer 2 Robust Implementation**: **37 Passed, 0 Failed (100.0% Pass Rate)**.

---

## 7. Actionable Recommendation for Worker M1

Worker M1 should replace lines 270–301 of `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs` with the following unified implementation:

```csharp
    public static bool IsNewerVersion(string currentVersion, string newestVersion)
    {
        try
        {
            string cleanCurrent = CleanVersionString(currentVersion);
            string cleanNewest = CleanVersionString(newestVersion);

            if (NormalizeVersion(cleanCurrent, out var current) && NormalizeVersion(cleanNewest, out var newest))
            {
                if (newest > current) return true;
                if (newest == current)
                {
                    string? preCurrent = ExtractPrerelease(currentVersion);
                    string? preNewest = ExtractPrerelease(newestVersion);

                    // If current is prerelease and newest is stable -> upgrade available
                    if (preCurrent != null && preNewest == null) return true;

                    // If both are prereleases of the same base, compare identifiers
                    if (preCurrent != null && preNewest != null)
                    {
                        return ComparePrerelease(preCurrent, preNewest) < 0;
                    }
                }
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
        var v = version.Trim().TrimStart('v', 'V');
        var splitIndex = v.IndexOfAny(['-', '+']);
        if (splitIndex >= 0)
        {
            v = v[..splitIndex];
        }
        return v.Trim();
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

    private static string? ExtractPrerelease(string version)
    {
        if (string.IsNullOrWhiteSpace(version)) return null;
        var v = version.Trim().TrimStart('v', 'V');
        var plusIndex = v.IndexOf('+');
        if (plusIndex >= 0)
        {
            v = v[..plusIndex];
        }
        var dashIndex = v.IndexOf('-');
        if (dashIndex >= 0)
        {
            return v[(dashIndex + 1)..];
        }
        return null;
    }

    private static int ComparePrerelease(string pre1, string pre2)
    {
        var parts1 = pre1.Split('.');
        var parts2 = pre2.Split('.');
        int minLength = Math.Min(parts1.Length, parts2.Length);

        for (int i = 0; i < minLength; i++)
        {
            string p1 = parts1[i];
            string p2 = parts2[i];

            bool isNum1 = int.TryParse(p1, out int num1);
            bool isNum2 = int.TryParse(p2, out int num2);

            if (isNum1 && isNum2)
            {
                if (num1 != num2) return num1.CompareTo(num2);
            }
            else if (isNum1 && !isNum2)
            {
                return -1;
            }
            else if (!isNum1 && isNum2)
            {
                return 1;
            }
            else
            {
                int cmp = string.Compare(p1, p2, StringComparison.OrdinalIgnoreCase);
                if (cmp != 0) return cmp;
            }
        }

        return parts1.Length.CompareTo(parts2.Length);
    }
```
