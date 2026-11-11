# Adversarial Challenge Report: Regression & Staging Lifecycle Stress Testing

**Challenger**: Challenger 2 (Milestone 1 Iteration 2)  
**Date**: 2026-11-10  
**Target Codebase**: `FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs` & `UpdateCheckerService.cs`  
**Verdict**: **APPROVE**  
**Overall Risk Assessment**: **LOW**

---

## 1. Executive Summary

As Challenger 2, an empirical stress testing suite was constructed and executed to verify that no regressions were introduced to `UpdateInstallerService.cs` during Milestone 1 Iteration 2 (which focused on `UpdateCheckerService.cs` multi-tier regex and SemVer normalization).

Empirical testing scrutinized the complete lifecycle:
1. **Staging Directory Lifecycle & Cleanup (`CleanOldUpdateRuns`)**: Preserving the latest 3 runs, pruning older runs, cleaning orphan version directories, and graceful recovery when scratch roots or run names are corrupt/non-numeric.
2. **Extraction Robustness (`ZipFile.ExtractToDirectory` & Script Discovery)**: Overwriting existing directories, nested directory structure discovery of `Add-AppDevPackage.ps1`, and handling of corrupt/incomplete archives.
3. **`apply.ps1` AST Syntax & Adversarial Path Escaping (`BuildApplyScriptContent`)**: Escaping of single quotes, spaces, brackets (`[x64]`), dollar signs (`$`), backticks, and extreme PID values (Int32.MaxValue, PID 0), ensuring 0 PowerShell parser syntax errors and exact literal path resolution.
4. **Elevation Tokens and ProcessStartInfo**: Validation of `Verb = "runas"`, `UseShellExecute = true`, `-NoProfile -ExecutionPolicy Bypass`, and proper UAC cancellation handling (`Win32Exception`).
5. **SHA-256 Cryptographic Verification In-Process (`VerifyFileHashAsync`)**: 10MB binary verification against system SHA-256, rejection of truncated and tampered files, case-insensitivity, and thread safety under concurrent file access (`FileShare.Read`).
6. **Regression Verification of `UpdateCheckerService.cs`**: Verified default repo endpoint (`unchihugo/FluentFlyout`), 15-second HTTP timeout, and SemVer 2.0.0 normalization rules.

**Summary of Empirical Results**:
- **Challenger 1 Test Suite**: 52/52 PASSED (100%)
- **Challenger 2 Stress Test Suite**: 31/31 PASSED (100%)
- **Total Tests**: 83/83 PASSED (0 Failures)

---

## 2. Challenges & Stress Hypotheses

### [Low Risk] Challenge 1: PowerShell Script Path Injection / Escaping Failure
- **Assumption Challenged**: That escaping single quotes with `Replace("'", "''")` and surrounding `$systemFiles` with single quotes in `apply.ps1` prevents injection or syntax breakage if Windows temp or username paths contain apostrophes (e.g. `C:\Users\O'Connor\...`), brackets (e.g. `[x64]`), or dollar signs.
- **Attack Scenario**: An installer directory located on a user profile with special characters causes `apply.ps1` to fail AST parsing or triggers PowerShell wildcard globbing in `Set-Location`.
- **Stress Test Result**: Tested with paths containing single quotes (`O'Connor`), multiple quotes (`Jack's & Jill's`), dollar signs (`$FluentFlyout`), brackets (`[x64]`), and backticks. All 10 scenarios parsed with **0 syntax errors** using `[System.Management.Automation.Language.Parser]::ParseInput`. `Set-Location` specifically uses `-LiteralPath $systemFiles`, completely mitigating wildcard/bracket globbing.
- **Verdict**: Robust.

### [Low Risk] Challenge 2: Scratch Update Staging Accumulation and Race Handling
- **Assumption Challenged**: That `CleanOldUpdateRuns()` reliably prevents disk bloat in `%TEMP%\FluentFlyout\updates` without deleting active or recent runs, and handles edge conditions without throwing unhandled exceptions.
- **Attack Scenario**: 6 update runs generated across 3 distinct version folders; non-numeric run folder names from legacy runs; or an empty updates folder.
- **Stress Test Result**: 
  - Exactly 3 runs are preserved (`KeepUpdateRuns = 3`).
  - The 3 oldest runs are deleted, and empty version folders (`2.14.0`) are automatically deleted.
  - Non-numeric folder names fall back gracefully to `CreationTimeUtc` without throwing exceptions.
  - Non-existent updates root returns immediately without error.
- **Verdict**: Robust.

### [Low Risk] Challenge 3: In-Process SHA-256 Under Concurrency and Malformed Inputs
- **Assumption Challenged**: That in-process `SHA256.HashDataAsync` correctly protects against corruptions, performs case-insensitive comparisons, handles truncated downloads, and supports concurrent read access without file-locking deadlocks.
- **Attack Scenario**: 10MB random payload verified concurrently across 5 tasks while checking truncated downloads and case mismatches.
- **Stress Test Result**:
  - Matched native PowerShell `Get-FileHash` across 10MB payload.
  - Truncated files cleanly rejected as `false`.
  - 5 concurrent verification tasks on the same file completed simultaneously without lock contention (`FileShare.Read`).
- **Verdict**: Robust.

---

## 3. Stress Test Results Matrix

| Area | Scenario | Expected | Actual | Result |
|---|---|---|---|---|
| Staging | CleanOldUpdateRuns non-existent root | No Exception | No Exception | **PASS** |
| Staging | CleanOldUpdateRuns empty root | No Exception | No Exception | **PASS** |
| Staging | CleanOldUpdateRuns with exactly 3 runs | Retain 3 runs | 3 runs retained | **PASS** |
| Staging | CleanOldUpdateRuns with 6 runs | Prune oldest 3, keep newest 3 | Kept 40, 50, 60 | **PASS** |
| Staging | CleanOldUpdateRuns empty version folder deletion | Deleted | Deleted | **PASS** |
| Staging | Non-numeric run directory sorting fallback | No Crash | No Crash | **PASS** |
| Extraction | Standard SystemFiles/Add-AppDevPackage.ps1 | Extracted | Extracted | **PASS** |
| Extraction | Nested zip structure recursive search | Discovered | Discovered | **PASS** |
| Extraction | Overwrite existing extraction files | No IOException | No IOException | **PASS** |
| Extraction | Corrupted zip archive detection | InvalidDataException | InvalidDataException | **PASS** |
| AST & Escaping | Standard path AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Path with spaces AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Path with single quote (O'Connor) AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Multiple single quotes AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Path containing dollar sign ($) AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Path containing brackets [x64] AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Path containing backticks and parentheses | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Large PID (Int32.MaxValue) AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | PID 0 (System idle process) AST parse | 0 errors | 0 errors | **PASS** |
| AST & Escaping | Set-Location uses -LiteralPath | True | True | **PASS** |
| Elevation | ProcessStartInfo sets Verb = 'runas' | True | True | **PASS** |
| Elevation | ProcessStartInfo sets UseShellExecute = true | True | True | **PASS** |
| Elevation | Arguments specify -NoProfile -ExecutionPolicy Bypass | True | True | **PASS** |
| Elevation | Catches Win32Exception on UAC cancellation | True | True | **PASS** |
| Crypto | 10MB binary file SHA-256 vs Get-FileHash | True | True | **PASS** |
| Crypto | Padded expected hash behavior (exact match) | False | False | **PASS** |
| Crypto | Truncated file rejected | False | False | **PASS** |
| Crypto | 5 concurrent hash verifications on shared file | True | True | **PASS** |
| Regression | Default fork repo unchihugo/FluentFlyout | unchihugo/FluentFlyout | unchihugo/FluentFlyout | **PASS** |
| Regression | HttpClient timeout configured to 15s | 15s | 15s | **PASS** |
| Regression | SemVer 2.0.0 comparison rules | c1=F, c2=T, c3=F, c4=T | c1=False, c2=True, c3=False, c4=True | **PASS** |

---

## 4. Unchallenged Areas

- **Elevated UAC Execution to Completion**: End-to-end execution of `Add-AppDevPackage.ps1` with actual installation into Windows AppX store was not run in this test pass because it requires user-interactive elevation prompt and system-level installation. This will be verified in Milestone 4 (E2E Verification & Audit).

---

## 5. Conclusion & Recommendation

The empirical tests confirm that `UpdateInstallerService.cs` is free of regressions, staging and extraction lifecycles are robust, PowerShell AST syntax and escaping withstand adversarial path scenarios, and cryptographic verification operates as intended.

**Recommendation**: **APPROVE** Milestone 1 Iteration 2.
