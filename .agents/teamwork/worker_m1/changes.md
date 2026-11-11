# Milestone 1 Code Modifications: Auto-Updater Service & GitHub Fork Integration

**Date**: 2026-11-10  
**Author**: Worker M1 (`Auto-Updater Engineer`)  
**Scope**: Requirements R1 and R2 (`UpdateCheckerService.cs` & `UpdateInstallerService.cs`)  

---

## 1. Summary of Changes

### A. `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`
1. **Configured GitHub Fork Target**:
   - Defined `DefaultGitHubOwner = "unchihugo"` and `DefaultGitHubRepo = "FluentFlyout"`.
   - Added property `GitHubApiLatestRelease` resolving to `https://api.github.com/repos/{DefaultGitHubOwner}/{DefaultGitHubRepo}/releases/latest`, with support for developer override via `FLUENTFLYOUT_UPDATE_REPO` environment variable.
2. **Dedicated HTTP Client & 15-Second Timeout**:
   - Replaced dependency on `FluentFlyoutApiClient` (which had a hardcoded 2-second timeout) with a dedicated `GitHubHttpClient` configured with `TimeSpan.FromSeconds(15)`.
   - Included explicit `Accept: application/vnd.github.v3+json` and dynamic `User-Agent: FluentFlyout/{version}` headers.
3. **Strict Fallback Isolation Under `#if GITHUB_RELEASE`**:
   - Under `#if GITHUB_RELEASE`, the fallback call to `fluentflyout.com/api/newest-version` is strictly disabled. If GitHub API is unreachable or times out, the service logs the error and gracefully returns `result.Success = false` without prompting users to downgrade or switch to upstream builds.
4. **Hardened SHA-256 Digest Regex Extraction**:
   - Replaced fragile `@"GitHub Release x64\D*?([0-9a-fA-F]{64})"` with hardened regex:
     `@"(?i)(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})"`
   - Added a generic 64-hex fallback regex to ensure release notes formatted in any standard convention are reliably captured.
5. **Asset Name Filtering**:
   - `ParseInstallerAsset` now explicitly prioritizes and matches `*x64*Installer.zip`.
6. **Resilient Version Parsing**:
   - Added `CleanVersionString` to strip SemVer prerelease suffixes (e.g., `-preview`, `-rc1`) before `Version.TryParse` comparison.

---

### B. `FluentFlyoutWPF/Classes/Services/UpdateInstallerService.cs`
1. **Managed Streaming Download**:
   - Removed external process dependency on `curl.exe`.
   - Implemented `DownloadFileAsync` using asynchronous `HttpClient` streaming (`HttpCompletionOption.ResponseHeadersRead` and `CopyToAsync` to `FileStream`).
   - Cleans up partial files if download fails.
2. **Native Cryptographic SHA-256 Verification**:
   - Removed external process dependency on `powershell.exe -Command Get-FileHash`.
   - Implemented `VerifyFileHashAsync` using native `System.Security.Cryptography.SHA256.HashDataAsync(stream)` and `Convert.ToHexString(hashBytes)`.
3. **Pre-Shutdown Archive Extraction**:
   - Unpacking is now executed in C# before application shutdown using `ZipFile.ExtractToDirectory(zipPath, extractDir, overwriteFiles: true)`.
   - Validates that `Add-AppDevPackage.ps1` exists before initiating shutdown, preventing the application from closing if the archive is corrupt.
4. **Hardened Decoupled Launcher Script (`apply.ps1`)**:
   - Replaced basic script with an elevated, robust PowerShell pipeline:
     * Transcript logging directed to `update_install.log`.
     * Explicit process wait (`Wait-Process -Id <pid> -Timeout 30 -ErrorAction SilentlyContinue`) to prevent MSIX lock error `0x80073D02`.
     * Working directory navigation to `SystemFiles` (`Set-Location -LiteralPath $systemFiles`).
     * Silent forced execution: `& '.\Add-AppDevPackage.ps1' -Force -SkipLoggingTelemetry`.
     * Application relaunch via AppX package detection:
       `$pkg = Get-AppxPackage '*FluentFlyout*' | Select-Object -First 1`
       Launching `$pkg.InstallLocation\FluentFlyout\FluentFlyout.exe`.
5. **Elevated Process Launch & Thread Safety**:
   - `ApplyRun` launches `powershell.exe` with:
     * `-NoProfile -ExecutionPolicy Bypass -File apply.ps1`
     * `UseShellExecute = true`
     * `Verb = "runas"` (UAC elevation)
   - Graceful exception handling for `Win32Exception` if user declines UAC.
   - `Application.Current.Shutdown()` is invoked only after `Process.Start` succeeds.
   - `ShowUpdateChoiceAndApplyAsync` dispatches to the WPF UI thread (`Dispatcher.InvokeAsync`) to ensure safe execution when invoked from background toast notification callbacks.
6. **Cleanup and Memory Maintenance**:
   - Fixed directory sorting in `CleanOldUpdateRuns` to sort by parsed epoch or creation timestamp.
   - Removed obsolete `RunAndWait` and `Quote` helper methods.

---

## 2. Compilation and Verification Status

- Command: `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
- Result: **0 Warning(s), 0 Error(s)**.
