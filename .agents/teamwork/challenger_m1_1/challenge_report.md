# Milestone 1 Challenge Report: Auto-Updater Empirical Verification

**Author**: Challenger M1 (Instance 1)  
**Date**: 2026-11-10  
**Target**: Milestone 1 Implementation by Worker M1  
**Target Codebase**: `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`, `UpdateInstallerService.cs`  
**Verdict**: **`REQUEST_CHANGES`**

---

## 1. Challenge Summary

**Overall Risk Assessment**: **MEDIUM**

Worker M1 has successfully executed the architectural shift required for Requirements R1 and R2:
- External dependencies on `curl.exe` and `powershell.exe -Command Get-FileHash` have been completely eliminated in favor of managed asynchronous streaming and native `System.Security.Cryptography.SHA256`.
- Pre-extraction in C# before application shutdown protects users from corrupt archives.
- The generated `apply.ps1` script is elevated (`runas`), decoupled, logs to `update_install.log`, waits for the terminating process, and relaunches the application cleanly.
- The project compiles with **0 warnings and 0 errors** under configuration `"GitHub Release"` (x64).
- Managed SHA-256 calculation matches standard NIST vectors, detects 1-bit tampering, handles 5MB binary payloads identically to Windows `Get-FileHash`, and correctly ignores case.

However, an empirical test harness executing **52 automated adversarial test cases** against the compiled `FluentFlyout.dll` revealed **4 distinct failure modes** in Regex extraction and Version comparison logic. Because Milestone 1's explicit charter includes "Robust SHA-256 Regex Extraction" (Feature 2) and "Version Comparison Hardening" (Feature 1/Acceptance Criteria), these defects must be addressed before proceeding.

---

## 2. Test Execution Summary

| Test Area | Executed | Passed | Failed | Success Rate |
|-----------|:--------:|:------:|:------:|:------------:|
| **Area 1: SHA-256 Regex Extraction & Asset Parsing** | 19 | 17 | 2 | 89.5% |
| **Area 2: Version Comparison (`IsNewerVersion`)** | 25 | 20 | 5 | 80.0% |
| **Area 3: Cryptographic SHA-256 Calculation** | 6 | 6 | 0 | 100.0% |
| **Area 4: Decoupled Script AST Syntax & Hardening** | 2 | 2 | 0 | 100.0% |
| **Total** | **52** | **45** | **7** | **86.5%** |

---

## 3. Specific Challenges & Empirical Evidence

### [High] Challenge 1: Multi-Architecture Checksum Collision in Release Notes
- **Assumption Challenged**: Assumed that `Sha256Regex = new(@"(?i)(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})", RegexOptions.Compiled)` would extract the checksum for the x64 installer.
- **Empirical Attack Scenario**:
  ```markdown
  ## Downloads
  ARM64 checksum: 1111111111111111111111111111111111111111111111111111111111111111
  GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855
  ```
- **Observed Result**:
  `ParseInstallerAsset` extracted: `1111111111111111111111111111111111111111111111111111111111111111` instead of `e3b0c442...`.
- **Logic Chain**:
  The alternation branch `|checksum` matches `ARM64 checksum:` because the pattern does not enforce that `x64` precedes `checksum`. Because ARM64 appears before x64 in the text, the regex captures the ARM64 digest.
- **Blast Radius**:
  The application downloads `FluentFlyout_<version>_x64_Installer.zip`, but verifies its hash against the ARM64 digest. The verification fails with `SHA-256 digest mismatch`, aborting the update and blocking all x64 users from upgrading.
- **Recommended Fix**:
  Tether the primary extraction pattern strictly to x64:
  ```csharp
  private static readonly Regex Sha256X64Regex = new(
      @"(?i)(?:GitHub\s+Release\s+x64[\s\w-]*?(?:checksum|sha-?256)|x64[\s\w-]*?(?:checksum|sha-?256))[\s:]+([0-9a-fA-F]{64})\b",
      RegexOptions.Compiled);

  private static readonly Regex Sha256FallbackRegex = new(
      @"(?i)(?:sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})\b",
      RegexOptions.Compiled);
  ```
  Attempt `Sha256X64Regex` first; only fall back to `Sha256FallbackRegex` or generic hex if no x64-specific line exists.

---

### [Medium] Challenge 2: Truncation of >64-Character Hex Hashes Due to Missing Word Boundary
- **Assumption Challenged**: Assumed matching 64 hex characters without a trailing delimiter would only capture 64-character hashes.
- **Empirical Attack Scenario**:
  Release notes with a 65-character malformed hash or a SHA-512 digest (128 characters):
  `GitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855a`
- **Observed Result**:
  `ParseInstallerAsset` extracted: `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` (truncated the first 64 characters of the 65-char string).
- **Logic Chain**:
  `Sha256Regex` lacks a trailing word boundary `\b` on `([0-9a-fA-F]{64})`. Any string of 65+ hex characters matches the first 64 characters.
- **Blast Radius**:
  A release author publishing a SHA-512 or making a 1-character typo causes the updater to accept the truncated string as a valid SHA-256 expected digest, leading to subsequent hash mismatch failures.
- **Recommended Fix**:
  Ensure all regexes enforce word boundaries on both ends:
  `([0-9a-fA-F]{64})\b`

---

### [Medium] Challenge 3: Incomplete SemVer Cleaning on Build Metadata (`+`)
- **Assumption Challenged**: Assumed `v[..dashIndex]` in `CleanVersionString` was sufficient for SemVer string cleaning.
- **Empirical Attack Scenario**:
  Comparing `v2.15.0` to `v2.16.0+build123` (valid SemVer 2.0.0 build metadata).
- **Observed Result**:
  `IsNewerVersion("v2.15.0", "v2.16.0+build123")` returned `False`.
- **Logic Chain**:
  `CleanVersionString` only searches for `-` (`IndexOf('-')`). When a version has `+build123`, `v` remains `2.16.0+build123`. `Version.TryParse("2.16.0+build123", out _)` returns `false` because `+` is invalid in `System.Version`.
- **Blast Radius**:
  Any release tag or CI artifact tagged with build metadata (common in automated packaging) fails version parsing, causing the update check to silently report `IsUpdateAvailable = false`.
- **Recommended Fix**:
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
      return v;
  }
  ```

---

### [Low] Challenge 4: Prerelease-to-Stable Upgrade Blindness & Undefined Revision Discrepancy
- **Assumption Challenged**: Assumed stripping prerelease suffixes and relying solely on `System.Version.TryParse` produces correct upgrade semantics.
- **Empirical Attack Scenario**:
  1. `IsNewerVersion("v2.16.0-beta.1", "v2.16.0")` returned `False`.
  2. `IsNewerVersion("v2.16.0-beta.1", "v2.16.0-beta.2")` returned `False`.
  3. `IsNewerVersion("2.16.0", "2.16.0.0")` returned `True`.
- **Logic Chain**:
  1. Stripping `-beta.1` leaves both versions as `2.16.0`. Because `2.16.0 > 2.16.0` is false, users on beta builds never get updated to the release build.
  2. In `System.Version`, undefined revision is `-1`. Since `0 > -1`, `2.16.0.0` is evaluated as strictly greater than `2.16.0`.
- **Blast Radius**:
  Users testing beta builds are stranded and must manually download the release. If an external API or tag uses 4-part notation with trailing zero, it triggers false update prompts.
- **Recommended Fix**:
  Normalize version components to 4 parts (`Major.Minor.Build.Revision`) defaulting missing parts to 0, and if base numbers are equal:
  If `currentVersion` has a `-` prerelease suffix and `newestVersion` does not, return `true` (prerelease -> stable upgrade).

---

## 4. Stress Test Results (Empirical Harness)

| Test Category | Test Case Name | Expected | Actual | Result |
|---------------|----------------|:--------:|:------:|:------:|
| Regex | Standard workflow format | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Uppercase hex hash | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Keyword sha256 | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Header SHA-256: | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Header sha256: | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Prefix checksum: | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Space separated sha256 | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Noisy body with 40-char git commit SHA | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Markdown bold **Checksum:** | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Backtick wrapped hash \`hash\` | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Multi-arch notes (ARM64 before x64) | `e3b0c44...` | `1111111...` | **FAIL** |
| Regex | Previous release hash mentioned | `e3b0c44...` | `e3b0c44...` | PASS |
| Regex | Malformed 63-hex string | `""` | `""` | PASS |
| Regex | Malformed 65-hex string | `""` | `e3b0c44...` | **FAIL** |
| Regex | Non-hex string (contains 'g') | `""` | `""` | PASS |
| Regex | No checksum present in notes | `""` | `""` | PASS |
| Regex | Empty body | `""` | `""` | PASS |
| Asset | Prefers x64 Installer.zip over arm64 | `x64.zip` | `x64.zip` | PASS |
| Asset | Ignores non-Installer.zip assets | `""` | `""` | PASS |
| Version | Minor upgrade: 2.15.0 -> 2.16.0 | True | True | PASS |
| Version | Patch upgrade: 2.16.0 -> 2.16.1 | True | True | PASS |
| Version | Major upgrade: 2.16.0 -> 3.0.0 | True | True | PASS |
| Version | Same version: 2.16.0 -> 2.16.0 | False | False | PASS |
| Version | Downgrade: 2.16.0 -> 2.15.0 | False | False | PASS |
| Version | v-prefix on both: v2.15.0 -> v2.16.0 | True | True | PASS |
| Version | Uppercase V on current: V2.15.0 -> v2.16.0 | True | True | PASS |
| Version | v on newest only: 2.15.0 -> v2.16.0 | True | True | PASS |
| Version | v on current only: v2.15.0 -> 2.16.0 | True | True | PASS |
| Version | 4-part revision upgrade: 2.16.0.0 -> 2.16.0.1 | True | True | PASS |
| Version | 3-part vs 4-part same: 2.16.0 vs 2.16.0.0 | False | True | **FAIL** |
| Version | 3-part vs 4-part upgrade: 2.16.0 vs 2.16.0.1 | True | True | PASS |
| Version | 2-part to 3-part: 2.15 vs 2.16.0 | True | True | PASS |
| Version | 2-part same: 2.16 vs 2.16.0 | False | True | **FAIL** |
| Version | Prerelease to higher patch: v2.16.0-beta.1 -> v2.16.1 | True | True | PASS |
| Version | Prerelease to stable: v2.16.0-beta.1 -> v2.16.0 | True | False | **FAIL** |
| Version | Prerelease to next prerelease: v2.16.0-beta.1 -> v2.16.0-beta.2 | True | False | **FAIL** |
| Version | Stable to prerelease patch: v2.16.0 -> v2.16.1-rc1 | True | True | PASS |
| Version | Build metadata: v2.15.0 -> v2.16.0+build123 | True | False | **FAIL** |
| Version | Empty current version | True | True | PASS |
| Version | Empty newest version | False | False | PASS |
| Version | Invalid current string | False | False | PASS |
| Version | Invalid newest string | False | False | PASS |
| Version | Whitespace current | True | True | PASS |
| Version | Large major version jump | True | True | PASS |
| Crypto | NIST Empty file SHA-256 | True | True | PASS |
| Crypto | NIST Fox string SHA-256 | True | True | PASS |
| Crypto | 5MB binary vs Get-FileHash | True | True | PASS |
| Crypto | Uppercase expected hash comparison | True | True | PASS |
| Crypto | Detect 1-bit file tampering | False | False | PASS |
| Crypto | Non-existent file returns false | False | False | PASS |
| Script | PowerShell AST Parse Syntax | 0 errors | 0 errors | PASS |
| Script | Hardened script commands present | All present | All present | PASS |

---

## 5. Unchallenged Areas

- **Actual UAC Execution & Package Installation**: Elevated execution of `apply.ps1` with Windows App Installer was verified via AST syntax parsing and code inspection; executing an actual elevated sideload install on the developer workstation was skipped to preserve local system state.
- **GitHub API Live Rate Limiting**: The live GitHub API endpoint was tested offline with representative mock payloads; live network rate-limiting handling was not exercised against remote GitHub servers.

---

## 6. Actionable Fix Plan for Worker M1

Worker M1 should make the following targeted modifications to `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`:

1. **Update `Sha256Regex`**:
   Split into an x64-specific regex and a fallback regex, both bounded by `\b`:
   ```csharp
   private static readonly Regex Sha256X64Regex = new(
       @"(?i)(?:GitHub\s+Release\s+x64|x64)[\s\w-]*?(?:checksum|sha-?256)[\s:]+([0-9a-fA-F]{64})\b",
       RegexOptions.Compiled);

   private static readonly Regex Sha256FallbackRegex = new(
       @"(?i)(?:sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})\b",
       RegexOptions.Compiled);
   ```
   In `ParseInstallerAsset`, test `Sha256X64Regex` first. If unmatched, test `Sha256FallbackRegex`. If still unmatched, test generic `\b([0-9a-fA-F]{64})\b`.

2. **Update `CleanVersionString`**:
   Add `+` to the delimiter check:
   ```csharp
   var splitIndex = v.IndexOfAny(['-', '+']);
   if (splitIndex >= 0)
   {
       v = v[..splitIndex];
   }
   ```

3. **Refine `IsNewerVersion`**:
   Normalize version strings to 4 components before comparison to avoid the `System.Version` undefined component (-1 vs 0) discrepancy, and allow prerelease-to-stable upgrades when base versions are equal:
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
                   // If base versions are identical, a release build is newer than a prerelease build
                   bool currentIsPrerelease = currentVersion.Contains('-');
                   bool newestIsPrerelease = newestVersion.Contains('-');
                   if (currentIsPrerelease && !newestIsPrerelease) return true;
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
