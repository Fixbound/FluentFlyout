# Challenge Report: Milestone 1 — Installer Zip Staging, Extraction, Script Generation & Failure Scenarios

**Instance**: Challenger M1 (Instance 2)  
**Role**: Empirical Adversarial Verifier (Download, Extraction & Installer Lifecycle)  
**Target Codebase**: `E:\Programacion\FluentFlyout`  
**Verdict**: **APPROVE**  

---

## Challenge Summary

**Overall risk assessment**: **LOW**

Worker M1's refactoring of `UpdateInstallerService.cs` and `UpdateCheckerService.cs` was subjected to an adversarial empirical evaluation comprising 21 stress vectors across four primary failure domains:
1. Archive extraction and corrupt/malicious zip handling (corrupt, empty, truncated, incomplete, nested, dirty, and ZipSlip archives).
2. Generated `apply.ps1` PowerShell script syntax, AST parsing across edge-case directory paths (quotes, brackets, spaces, dollar signs), and transcript error recording.
3. Process detachment, execution arguments quoting, and UAC elevation denial handling.
4. Scratch directory cleanup, retention limits, and tolerance against locked file handles.

All 21 test vectors executed with 100% pass rate. The implementation adheres strictly to non-blocking principles: errors in download, hash verification, zip extraction, or elevation cleanly abort before `Application.Current.Shutdown()`, leaving the running app operational and recording actionable diagnostics.

---

## Challenges

### [Low] Challenge 1: Child Script Exit Code Sensitivity in `apply.ps1`

- **Assumption challenged**: In `apply.ps1`, `& '.\Add-AppDevPackage.ps1' -Force -SkipLoggingTelemetry` relies on `$ErrorActionPreference = 'Stop'` and standard PowerShell error propagation to trap installation errors.
- **Attack scenario**: If a future variation of `Add-AppDevPackage.ps1` or a sub-tool terminates using an un-trapped `exit <non-zero>` without emitting a terminating error or calling `Write-Error`, in-process script invocation via `&` does not throw an exception into the caller's `try/catch` block.
- **Blast radius**: The script could potentially log "Add-AppDevPackage.ps1 completed" and attempt to relaunch the old application when the package was not updated.
- **Empirical observation**: Microsoft's official `Add-AppDevPackage.ps1` implements `Fail-Script` which calls `Write-Error` upon any fatal package deployment or certificate registration failure. Because `apply.ps1` specifies `$ErrorActionPreference = 'Stop'`, our empirical test (T2.5) proved that `Write-Error` terminates execution immediately and is cleanly captured by the `catch` block and transcript log.
- **Mitigation / Recommendation**: In future milestones (e.g. M4 testing), optionally augment `apply.ps1` to explicitly check `if (-not $? -or ($LASTEXITCODE -and $LASTEXITCODE -ne 0)) { throw "Add-AppDevPackage failed with exit code $LASTEXITCODE" }` for belt-and-suspenders hardening against third-party batch scripts.

### [Low] Challenge 2: Temporary Directory Accumulation on Repeated Verification Retries

- **Assumption challenged**: Retaining failed update run directories for diagnostic inspection might lead to unbounded temp disk consumption if update checks are triggered frequently.
- **Attack scenario**: A user on an intermittent network connection triggers auto-update check repeatedly, each time creating a scratch epoch folder under `%TEMP%\FluentFlyout\updates\<version>\<epoch>`.
- **Blast radius**: Excessive disk usage in `%TEMP%`.
- **Empirical observation**: `UpdateInstallerService.CleanOldUpdateRuns()` runs proactively at the start of each update lifecycle, sorting all runs across all version subdirectories by parsed epoch timestamp and deleting any runs beyond `KeepUpdateRuns = 3`. Our empirical test (T4.1 and T4.2) verified that only the newest 3 runs are preserved, older runs are deleted, and empty version parent folders are pruned.

---

## Stress Test Results

Executed via automated test harness `run_empirical_tests.ps1` (21 test vectors):

| Test ID | Scenario / Vector | Expected Behavior | Actual Behavior | Result |
|---------|-------------------|-------------------|-----------------|--------|
| **T1.1** | Valid ZIP with `SystemFiles\Add-AppDevPackage.ps1` | Archive extracted, script detected at exact expected path | Extracted to `files\SystemFiles\Add-AppDevPackage.ps1` | **PASS** |
| **T1.2** | Empty 0-byte archive file | `ZipFile.ExtractToDirectory` throws `InvalidDataException`, caught cleanly | Throws `InvalidDataException: Central Directory corrupt.`, no crash | **PASS** |
| **T1.3** | Valid empty zip archive (0 entries) | Extraction succeeds, pre-shutdown check detects missing installer script | Detected missing `Add-AppDevPackage.ps1`, aborted before shutdown | **PASS** |
| **T1.4** | Corrupt ZIP (random garbage bytes) | `ZipFile.ExtractToDirectory` throws `InvalidDataException` | Throws `InvalidDataException: End of Central Directory record...` | **PASS** |
| **T1.5** | Truncated ZIP header/data | Throws `InvalidDataException`, logged cleanly | Throws `InvalidDataException: End of Central Directory record...` | **PASS** |
| **T1.6** | Incomplete ZIP (contains files, but missing `Add-AppDevPackage.ps1`) | Locater check fails, returns early without writing script or terminating app | Locater returned `Add-AppDevPackage.ps1 not found`, app kept alive | **PASS** |
| **T1.7** | Nested ZIP hierarchy discovery (`FluentFlyout_2.16.0_x64\SystemFiles\Add-AppDevPackage.ps1`) | Recursive search fallback locates script and identifies parent folder | Found nested script, resolved `systemFilesDir` correctly | **PASS** |
| **T1.8** | Pre-existing dirty extraction directory collision | Prior dirty contents purged recursively before fresh extraction | Obsolete files deleted, fresh extraction completed cleanly | **PASS** |
| **T1.9** | ZipSlip path traversal attack (`../evil.txt`) | Runtime blocks extraction outside destination folder | .NET throws `System.IO.IOException: Extracting Zip entry would have resulted in a file outside...` | **PASS** |
| **T2.1** | PowerShell AST Validation - Standard path | 0 AST syntax errors | `errors.Count == 0`, parsed cleanly | **PASS** |
| **T2.2** | PowerShell AST Validation - Path with single quotes (`O'Connor`) | Escaped with `Replace("'", "''")`, 0 AST syntax errors | `errors.Count == 0`, parsed cleanly | **PASS** |
| **T2.3** | PowerShell AST Validation - Brackets, dollar signs, spaces | Handled literally via `-LiteralPath`, 0 AST syntax errors | `errors.Count == 0`, parsed cleanly | **PASS** |
| **T2.4** | Simulated `apply.ps1` execution with mock installer | Transcript generated, script executed, marker file written, exit code 0 | Transcript logged to `update_install.log`, marker verified | **PASS** |
| **T2.5** | `apply.ps1` execution when installer throws error | Trapped by `catch` block, logged in transcript, no unhandled exit | Error logged in transcript: `Update installation failed: Simulated failure...` | **PASS** |
| **T3.1** | `ProcessStartInfo` argument quoting | Script path quoted: `-NoProfile -ExecutionPolicy Bypass -File "<path>"` | Matched regex, handles space-bearing directories | **PASS** |
| **T3.2** | Process detachment parameters | `UseShellExecute = true`, `Verb = "runas"` | Independent elevated child process lifecycle confirmed | **PASS** |
| **T3.3** | UAC elevation cancellation | `Win32Exception(1223)` caught specifically in `ApplyRun` | Caught specifically, app shutdown averted | **PASS** |
| **T4.1** | Scratch update run retention | Keep newest 3 runs, delete older runs | Retained epochs 30, 40, 50; deleted epochs 10, 20 | **PASS** |
| **T4.2** | Pruning of orphaned version folders | Empty version folders pruned, folders with runs preserved | Empty version dir deleted, active version dir preserved | **PASS** |
| **T4.3** | Partial download error cleanup | Partial `update.zip` deleted on download stream failure | File purged from scratch directory | **PASS** |
| **T4.4** | Retention resilience against locked directory | Non-crashing warning logged when run directory cannot be deleted | Caught and logged warning without crashing updater service | **PASS** |

---

## Unchallenged Areas

- **Actual MSIX Sideload Installation on Machine**: End-to-end installation of an official MSIX package signed with production/test certificates will be validated in Milestone 4 once M2 (Packaging alignment) and M3 (CI pipeline) are complete.

---

## Final Assessment & Recommendation

Worker M1's changes for Milestone 1 fulfill all criteria of Requirements R1 and R2 with exemplary resilience. The implementation safely isolates GitHub fork releases, prevents premature application termination, validates digests natively, enforces secure zip extraction, and produces an elevated, decoupled updater script with detailed transcript logging.

**Verdict**: **APPROVE**
