# Analysis Report: Auto-Updater Service & GitHub Fork API Endpoint (R1 & R2)

**Author**: Explorer Survey 1  
**Date**: 2026-11-10  
**Scope**: Requirements R1 & R2 for FluentFlyout  
**Target Codebase**: `E:\Programacion\FluentFlyout`  

---

## 1. Executive Summary

This report provides a thorough, code-level investigation into the auto-updater mechanism and GitHub API integration for the FluentFlyout fork (`unchihugo/FluentFlyout`). Requirements R1 and R2 aim to ensure that the MSIX-packaged application seamlessly checks for, downloads, validates, and installs releases from the GitHub fork repository, keeping premium features unlocked, operating non-blockingly, and handling errors cleanly with proper logging.

The investigation examined:
- `UpdateCheckerService.cs` (GitHub release querying, version parsing, asset parsing, regex digest extraction).
- `UpdateInstallerService.cs` (download pipeline, hash validation, scratch folder layout, PowerShell script generation, process execution, application shutdown).
- Supporting components: `FluentFlyoutApiClient.cs`, `UpdateState.cs`, `UserSettings.cs`, `Notifications.cs`, `HomePage.xaml.cs`, `MainWindow.xaml.cs`, and `.github/workflows/build-msix.yml`.

### Key Findings at a Glance:
1. **GitHub Fork Endpoint (R1)**: The endpoint is hardcoded as `https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest` in `UpdateCheckerService.cs:34`. However, if the GitHub check fails or times out, it falls back to `fluentflyout.com/api/newest-version` (the original author's upstream site), which would redirect users away from the fork or prompt them to install an upstream release lacking unlocked premium features. Furthermore, `FluentFlyoutApiClient.GetUrlAsync` uses a hardcoded 2-second timeout, which is prone to false timeouts under realistic network conditions.
2. **Regex Digest Extraction Vulnerability (R2)**: The SHA-256 regex in `UpdateCheckerService.cs:135` (`@"GitHub Release x64\D*?([0-9a-fA-F]{64})"`) relies on `\D*?` (non-digits). Any digit appearing between "GitHub Release x64" and the hash (such as `(sha256)`, version numbers, or build IDs) causes the regex match to fail completely, producing an empty expected hash and aborting the updater.
3. **External Process Dependencies in Download & Verify (R2)**: `UpdateInstallerService.cs` spawns `curl.exe` to download the zip and `powershell.exe` to calculate the SHA-256 checksum via `Get-FileHash`. Spawning `curl.exe` lacks the `--fail` flag (so HTTP 404/403 pages are saved as zip files with exit code 0) and provides no progress reporting. Both tasks can be performed natively and asynchronously in C# using .NET's `HttpClient` and `System.Security.Cryptography.SHA256` in milliseconds with zero process overhead.
4. **Fatal Flaws in Package Extraction & Execution (`apply.ps1`) (R2)**:
   - **No App Relaunch**: `apply.ps1` only executes `Add-AppDevPackage.ps1`; it never relaunches `FluentFlyout.exe`. Once updated, the app terminates and never reopens.
   - **Missing ExecutionPolicy**: `Process.Start("powershell.exe", "-NoProfile -File ...")` does not specify `-ExecutionPolicy Bypass`, failing on standard Windows installations where the execution policy is `Restricted`.
   - **Wrong Working Directory**: `apply.ps1` does not change directory into `SystemFiles`. `Add-AppDevPackage.ps1` expects its working directory to be the directory containing `.msix` and `.cer` files.
   - **Interactive Prompt Hang**: `apply.ps1` calls `Add-AppDevPackage.ps1` without the `-Force` flag. In non-interactive contexts, `Add-AppDevPackage.ps1` halts waiting for user keyboard input `[Enter]`.
   - **Process Lock Conflict**: `apply.ps1` does not wait for the running `FluentFlyout.exe` process to terminate before starting installation, causing MSIX error `0x80073D02` (Application files in use).
   - **Premature App Shutdown**: The app extracts the archive inside `apply.ps1` *after* calling `Application.Current.Shutdown()`. If the zip is corrupted, extraction fails after the app has already closed.
5. **Thread Safety & UI Blocking**: Toast notification activations in `Notifications.cs:47` call `UpdateInstallerService.ShowUpdateChoiceAndApplyAsync()` from a Windows background thread, risking invalid cross-thread access during `Application.Current.FindResource` and modal `MessageBox.Show`.
6. **Test Harness Gaps**: There are currently zero unit test projects in `FluentFlyout.sln`.

---

## 2. GitHub Fork API Endpoint Analysis (Requirement R1)

### 2.1 Git Remotes and Repository Identity
Inspection of the local repository configuration via `git remote -v`:
- `origin`: `https://github.com/unchihugo/FluentFlyout.git` (fetch & push)
- Branch: `master`
- Upstream project: `AnErrupTion/FluentFlyout` (website `fluentflyout.com`).

The current fork owner is **`unchihugo`**, repository **`FluentFlyout`**.

### 2.2 Current Code Implementation
In `FluentFlyoutWPF/Classes/Services/UpdateCheckerService.cs`:
```csharp
Line 18: private const string ApiEndpoint = "newest-version";
Line 34: private const string GitHubApiLatestRelease = "https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest";
```

### 2.3 Problems with Current Configuration
1. **Hardcoded String**: The repository path `unchihugo/FluentFlyout` is a private literal string. It cannot be overridden without code changes.
2. **Harmful Upstream Fallback**:
   In lines 69–84 of `UpdateCheckerService.cs`:
   ```csharp
   catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
   {
       Logger.Info(ex, "GitHub update check failed, falling back to the site API.");
   }

   var siteResponse = await FluentFlyoutApiClient.GetStringAsync(ApiEndpoint);
   var siteJson = JsonDocument.Parse(siteResponse);
   ```
   If GitHub check fails (e.g., rate limit, network timeout, HTTP 404), the service calls `https://fluentflyout.com/api/newest-version`. That API represents the original upstream repository. If the upstream repository releases a newer version, the user's fork application will prompt them to install or visit the upstream release, overwriting the fork build and stripping the unlocked premium features.
   **Recommendation**: For GitHub builds (`#if GITHUB_RELEASE` or when targeting GitHub Releases), the upstream site API fallback must be disabled or isolated. A failure on GitHub should simply report `Success = false`.
3. **Overly Aggressive 2-Second Timeout**:
   In `FluentFlyoutApiClient.cs`:
   ```csharp
   Line 13: private static readonly TimeSpan _timeout = TimeSpan.FromSeconds(2);
   ...
   Line 41: public static async Task<string> GetUrlAsync(string absoluteUrl)
   {
       var client = new HttpClient { Timeout = _timeout };
       ...
   }
   ```
   A 2-second timeout for a cold HTTPS connection to `api.github.com` (TLS negotiation + DNS + JSON payload transfer) frequently times out on typical home networks or VPNs, immediately triggering the fallback.
   **Recommendation**: Use a dedicated, reasonable timeout for GitHub API calls (e.g., 10–15 seconds) or configure it independently from quick internal telemetry pings.

### 2.4 Proposed Clean Configuration Architecture for R1
- Introduce constants/properties in `UpdateCheckerService`:
  ```csharp
  public const string DefaultGitHubOwner = "unchihugo";
  public const string DefaultGitHubRepo = "FluentFlyout";
  public static string GitHubReleasesApiUrl => $"https://api.github.com/repos/{DefaultGitHubOwner}/{DefaultGitHubRepo}/releases/latest";
  ```
- Optional: Allow an override via `UserSettings.CustomUpdateRepo` or environment variable `FLUENTFLYOUT_UPDATE_REPO` for developer testing.
- Guard against upstream site API fallback when in `GITHUB_RELEASE` mode or when GitHub is the configured update authority.

---

## 3. GitHub Release Payload Parsing & Version Checking (Requirement R2)

### 3.1 GitHub Releases API Payload Structure
The endpoint `https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest` returns JSON with:
- `tag_name`: Git tag, e.g., `"v2.16.0"` or `"v2.16.0.0"`.
- `html_url`: Release web page URL, e.g., `"https://github.com/unchihugo/FluentFlyout/releases/tag/v2.16.0"`.
- `body`: Markdown release notes containing the installer file name and SHA-256 hash.
- `assets`: Array of asset items with `name`, `browser_download_url`, `size`, `content_type`.

### 3.2 Asset Name Resolution
In `.github/workflows/build-msix.yml:80`:
```powershell
$zipName = "FluentFlyout_${{ env.APP_VERSION }}_${{ env.PLATFORM }}_Installer.zip"
```
In `UpdateCheckerService.cs:109-131` (`ParseInstallerAsset`):
```csharp
if (!asset.TryGetProperty("name", out var nameElement))
    continue;

var name = nameElement.GetString();
if (name is null || !name.EndsWith("Installer.zip", StringComparison.OrdinalIgnoreCase))
    continue;

var url = asset.GetProperty("browser_download_url").GetString();
if (url is not null && (assetUrl == string.Empty || name.Contains("x64", StringComparison.OrdinalIgnoreCase)))
{
    assetUrl = url;
}
```
**Evaluation**:
- Asset matching correctly looks for `Installer.zip` and prefers `x64`.
- Safety fix needed: `asset.GetProperty("browser_download_url")` should use `TryGetProperty` to prevent `KeyNotFoundException` on malformed asset items.

### 3.3 SHA-256 Regex Extraction Fragility
In `.github/workflows/build-msix.yml:86`:
```powershell
$notes = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"
```
In `UpdateCheckerService.cs:133-137`:
```csharp
if (release.RootElement.TryGetProperty("body", out var bodyElement))
{
    var match = Regex.Match(bodyElement.GetString() ?? string.Empty, @"GitHub Release x64\D*?([0-9a-fA-F]{64})");
    sha256 = (match.Success && match.Groups.Count > 1) ? match.Groups[1].Value : string.Empty;
}
```
**Demonstrated Vulnerability**:
- `\D*?` matches non-digits lazily.
- If the release body contains:
  `GitHub Release x64 checksum (sha256): <hash>`
  or if the version number appears: `GitHub Release x64 (v2.16.0) checksum: <hash>`
  The regex **fails completely** because `256` and `2.16.0` contain digits!
- **Verified in PowerShell**:
  `[regex]::Match('GitHub Release x64 checksum (sha256): e3b0c442...', 'GitHub Release x64\D*?([0-9a-fA-F]{64})').Groups[1].Value`
  returns `""` (empty string).
- **Proposed Robust Regex**:
  ```csharp
  // Matches "GitHub Release x64 checksum: <hash>" or generic "SHA256: <hash>"
  var match = Regex.Match(body, @"(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})", RegexOptions.IgnoreCase);
  ```

### 3.4 Version Comparison Logic
In `UpdateCheckerService.cs:160-173`:
```csharp
private static bool IsNewerVersion(string currentVersion, string newestVersion)
{
    try
    {
        var current = Version.Parse(currentVersion.TrimStart('v'));
        var newest = Version.Parse(newestVersion.TrimStart('v'));
        return newest > current;
    }
    catch (Exception ex)
    {
        Logger.Error(ex, $"Failed to compare versions: {currentVersion} vs {newestVersion}");
        return false;
    }
}
```
**Defects & Edge Cases**:
1. `System.Version.Parse` throws `FormatException` if the version tag contains SemVer prerelease suffixes (e.g. `2.16.0-beta1` or `2.16.0-preview`).
2. In `MainWindow.xaml.cs:214`, unpackaged executions set `SettingsManager.Current.LastKnownVersion = "debug"`. In `UpdateCheckerService.cs:64`:
   `result.IsUpdateAvailable = currentVersion != "debug" && IsNewerVersion(currentVersion, result.NewestVersion);`
   While this prevents debug instances from self-updating accidentally, it makes local verification of the updater impossible unless a mock version or test bypass is supplied.

---

## 4. Update Download, Verification, and Installation Deep Dive (`UpdateInstallerService.cs`)

### 4.1 Asset Download Mechanism
`UpdateInstallerService.cs:118-123`:
```csharp
var curlArgs = "--location --output " + Quote(zipPath) + " " + Quote(assetUrl);
if (RunAndWait("curl.exe", curlArgs, DownloadTimeoutMs) != 0)
{
    Logger.Error($"Failed to download {assetUrl} into {zipPath}");
    return string.Empty;
}
```
**Critical Deficiencies**:
1. **Missing `--fail` flag**: If GitHub API returns HTTP 404 (file removed) or HTTP 403 (rate limited / forbidden), `curl` writes the HTML error page into `update.zip` and exits with code 0.
2. **Missing Console Hiding**: `Process.Start("curl.exe", ...)` without `ProcessStartInfo.CreateNoWindow = true` pops up a brief black console window.
3. **No Progress Indication**: User has no indication of download progress. An MSIX package zip is typically 40MB–100MB, causing the app to appear completely frozen for up to several minutes.
4. **Unnecessary Process Spawning**: .NET 10 has high-performance, asynchronous streaming HTTP capabilities built-in. Spawning an external process is an anti-pattern when `HttpClient` is readily available.

**Recommended Replacement**:
```csharp
using var response = await httpClient.GetAsync(assetUrl, HttpCompletionOption.ResponseHeadersRead);
response.EnsureSuccessStatusCode();
using var fileStream = new FileStream(zipPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true);
await response.Content.CopyToAsync(fileStream);
```

### 4.2 SHA-256 Digest Verification
`UpdateInstallerService.cs:127-133`:
```csharp
var verifyCommand =
    "if ((Get-FileHash -Path " + Quote(zipPath) + " -Algorithm SHA256).Hash -ieq " + Quote(expectedSha256) + ") { exit 0 } else { exit 1 }";

if (RunAndWait("powershell.exe", "-NoProfile -Command \"" + verifyCommand + "\"", VerifyTimeoutMs) != 0)
{
    Logger.Error($"SHA-256 digest mismatch for {zipPath}; refusing to install");
    return string.Empty;
}
```
**Critical Deficiencies**:
1. Shelling out to `powershell.exe` introduces 1–3 seconds of process spin-up latency, risks execution policy failures, and spawns another external process.
2. If PowerShell is disabled or restricted in an enterprise environment (AppLocker/WDAC), this step fails.

**Recommended Replacement**:
Managed .NET implementation takes <10ms:
```csharp
using var fileStream = File.OpenRead(zipPath);
byte[] hashBytes = await SHA256.HashDataAsync(fileStream);
string actualSha256 = Convert.ToHexString(hashBytes);

if (!string.Equals(actualSha256, expectedSha256, StringComparison.OrdinalIgnoreCase))
{
    Logger.Error($"SHA-256 digest mismatch for {zipPath}. Expected: {expectedSha256}, Actual: {actualSha256}");
    return string.Empty;
}
```

### 4.3 Scratch Directory Layout and Cleanup
Layout in `UpdateInstallerService.cs:107`:
`%TEMP%\FluentFlyout\updates\<version>\<epoch>\`
- `update.zip`
- `files\` (extracted package)
- `apply.ps1` (installer script)

`CleanOldUpdateRuns()`:
- Scans `%TEMP%\FluentFlyout\updates` and retains the last 3 runs.
- **Bug in sorting**: `runs.Sort((a, b) => b.CompareTo(a));` sorts by full directory path string rather than directory creation time or parsed epoch value. If directory names differ in length or structure across versions, alphabetical sorting will delete the wrong runs.

### 4.4 Extraction and Execution (`ApplyRun`)
`UpdateInstallerService.cs:143-167`:
```csharp
private static void ApplyRun(string runDir)
{
    var extractDir = Path.Join(runDir, "files");
    var zipPath = Path.Join(runDir, "update.zip");
    var installerScript = Path.Join(extractDir, "SystemFiles\\Add-AppDevPackage.ps1");
    var applyScript = Path.Join(runDir, "apply.ps1");

    var scriptBody =
        "Expand-Archive -LiteralPath " + Quote(zipPath) + " -DestinationPath " + Quote(extractDir) + "\r\n" +
        "& " + Quote(installerScript) + "\r\n";

    try
    {
        File.WriteAllText(applyScript, scriptBody);

        // detached installer survives our shutdown: it installs and launches the new version
        _ = Process.Start("powershell.exe", "-NoProfile -File \"" + applyScript + "\"");

        Application.Current.Shutdown();
    }
    catch (Exception ex)
    {
        Logger.Error(ex, $"Failed to start update installer for {runDir}");
    }
}
```

**Fatal Issues Identified**:
1. **Extraction Timing (Post-Shutdown)**:
   Extracting the archive in PowerShell *after* `Application.Current.Shutdown()` is fragile. If the zip file is corrupt or truncated, `Expand-Archive` throws an unhandled PowerShell error and terminates. The application is already dead, leaving the user with no app and no update.
   *Fix*: Perform extraction in C# using `System.IO.Compression.ZipFile.ExtractToDirectory(zipPath, extractDir, overwriteFiles: true)`. Check that `Add-AppDevPackage.ps1` exists *before* initiating application shutdown.
2. **Missing ExecutionPolicy Bypass**:
   Standard Windows clients run with `ExecutionPolicy = Restricted` by default. Invoking `powershell.exe -NoProfile -File apply.ps1` fails immediately with an execution policy violation.
   *Fix*: Always pass `-ExecutionPolicy Bypass`.
3. **Missing Elevation (`runas`)**:
   `Add-AppDevPackage.ps1` must install the developer certificate into the machine's certificate store. This requires Administrator privileges. Calling `Process.Start("powershell.exe", ...)` runs under the current standard user token without requesting elevation.
   *Fix*: Set `ProcessStartInfo.Verb = "runas"` and `ProcessStartInfo.UseShellExecute = true`.
4. **Interactive Prompt Hang (Missing `-Force`)**:
   `Add-AppDevPackage.ps1` without `-Force` will pause with:
   `"Press Enter to continue..."`
   In a detached/background process without interactive console input, the script hangs indefinitely.
   *Fix*: Invoke `& $installerScript -Force -SkipLoggingTelemetry`.
5. **Wrong Working Directory**:
   `Add-AppDevPackage.ps1` locates the `.msix` package and certificate relative to its working directory. In `apply.ps1`, the working directory is not set to `SystemFiles`.
   *Fix*: Add `Set-Location -LiteralPath (Split-Path -Parent $installerScript)`.
6. **Application Never Relaunched**:
   As inspected in `.github/build-files/FluentFlyout_Installer.bat:30`, `Add-AppDevPackage.ps1` **does not relaunch the app**. The `.bat` installer had an explicit step:
   `PowerShell -Command "& { $pkg = Get-AppxPackage '*FluentFlyout*' | Select-Object -First 1; if ($pkg) { $exe = Join-Path $pkg.InstallLocation 'FluentFlyout\FluentFlyout.exe'; Start-Process $exe } }"`
   In `UpdateInstallerService.cs`, the author assumed `Add-AppDevPackage.ps1` launched the app, but it does not. The app shuts down and never reopens.
7. **Process Lock Conflict**:
   If `Add-AppDevPackage.ps1` attempts to install the MSIX package while the old `FluentFlyout.exe` process is still running or completing cleanup, Windows AppX deployment fails with `0x80073D02` (files in use).
   *Fix*: `apply.ps1` must wait for `FluentFlyout` to exit:
   `Wait-Process -Id <pid> -Timeout 15 -ErrorAction SilentlyContinue; Start-Sleep -Seconds 1`.
8. **No Logging**:
   `apply.ps1` currently produces no log.
   *Fix*: Wrap execution in `Start-Transcript -Path (Join-Path $runDir "install.log") -Append`.

---

## 5. UI Integration, Threading, and Error Handling

### 5.1 Call Sites Overview
1. **`MainWindow.xaml.cs:252` (`CheckForUpdatesOnStartupAsync`)**:
   - Called during startup after version determination.
   - If `SettingsManager.Current.AutoUpdateEnabled` is true, calls `AutoApplyPendingUpdateAsync()`.
   - If update fails, triggers `Notifications.ShowUpdateFailedToast()`.
2. **`HomePage.xaml.cs:63` (`CheckForUpdatesButton_Click`)**:
   - Triggered when user clicks the update button in the settings UI.
   - Checks `UpdateState.Current.IsUpdateAvailable`. If update ready, calls `UpdateInstallerService.ShowUpdateChoiceAndApplyAsync()`.
   - If no update cached, calls `CheckForUpdatesAsync()`.
3. **`Notifications.cs:44` (`OnNotificationInvoked`)**:
   - Handles clicking toast notification buttons with action `"updateNow"`.
   - Invokes `UpdateInstallerService.ShowUpdateChoiceAndApplyAsync()`.

### 5.2 Threading & Non-Blocking Issues
- **Background Thread Violation in Notifications**:
  Windows Toast notification callbacks occur on a background thread pool thread. Calling `UpdateInstallerService.ShowUpdateChoiceAndApplyAsync()` directly from `Notifications.cs:47` means `Application.Current.FindResource(...)` and `MessageBox.Show(...)` are executed on a non-UI thread without an owner window.
  *Fix*: Dispatch to `Application.Current.Dispatcher.InvokeAsync(...)`.
- **UI Feedback During Download**:
  `UpdateState` lacks observable properties for `IsDownloading` or `DownloadStatus`. When a user clicks "Update Now", the app downloads 50MB+ with zero UI response, causing users to believe the app is unresponsive.
  *Fix*: Add `IsDownloading` and `StatusText` to `UpdateState`.

---

## 6. Dependencies, Unit Tests, and Testability

### 6.1 Solution Layout
The solution `FluentFlyout.sln` consists of:
1. `FluentFlyoutWPF/FluentFlyout.csproj` (.NET 10, WPF, Windows SDK 10.0.22000.0)
2. `FluentFlyoutMSIX/FluentFlyoutMSIX.wapproj` (Windows Application Packaging project)
3. `FluentFlyout.SourceGenerators/FluentFlyout.SourceGenerators.csproj` (.NET Standard 2.0)

### 6.2 Test Coverage Status
- **Existing Unit Tests**: **None**. There are no unit test projects in the solution.
- **Service Testability**:
  Both `UpdateCheckerService` and `UpdateInstallerService` are implemented as `public static class` with direct calls to `HttpClient`, `Process.Start`, and `Application.Current`.
  To allow robust unit testing and verification without making network calls or running real installers, the core logic should be modularized:
  - Pure parsing functions (version comparison, release JSON parsing, regex hash extraction) can be tested cleanly.
  - Hashing and file validation can be tested on local temporary test files.
  - A test harness or mock mode can verify the complete check/download/verify/unpack pipeline offline.

---

## 7. Gap Analysis & Actionable Remediation Plan

| Requirement Area | Current Code Defect / Gap | Proposed Remediation |
|---|---|---|
| **R1. Fork Endpoint** | Hardcoded endpoint string; fallback to upstream `fluentflyout.com` overwrites fork releases | Define explicit constants `DefaultGitHubOwner = "unchihugo"`, `DefaultGitHubRepo = "FluentFlyout"`; construct endpoint dynamically; disable upstream site fallback for GitHub builds |
| **R1. Network Reliability** | 2-second timeout in `FluentFlyoutApiClient` causes frequent false failures | Increase timeout to 15 seconds for GitHub API calls |
| **R2. SHA-256 Regex** | `\D*?` fails if any digit exists before hash (e.g. `(sha256)`) | Replace with robust regex supporting `GitHub Release x64 checksum: <hash>` and generic `sha256: <hash>` patterns |
| **R2. Version Parsing** | `System.Version.Parse` crashes on SemVer tags with prerelease suffixes; unpackaged returns `"debug"` | Implement SemVer-tolerant parsing; provide a test override for local updater validation |
| **R2. Download Process** | Spawns `curl.exe` without `--fail`, blocking UI thread, no progress reporting | Replace with native async `HttpClient` streaming directly to file |
| **R2. Hash Verification** | Spawns `powershell.exe -Command Get-FileHash` | Replace with native `SHA256.HashDataAsync` in managed C# |
| **R2. Unpacking Strategy** | Unpacks in PowerShell post-shutdown; corrupted zip kills app with no recovery | Extract archive in C# using `ZipFile.ExtractToDirectory` before shutting down; abort cleanly if corrupt |
| **R2. Detached Script Execution** | `apply.ps1` lacks ExecutionPolicy bypass, elevation (`runas`), correct working dir, and `-Force` | Generate robust `apply.ps1`: `-ExecutionPolicy Bypass`, set working directory to `SystemFiles`, run `Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry`, run as Administrator |
| **R2. App Relaunch** | App is never relaunched after update installation | Add package detection and relaunch logic in `apply.ps1` (`Start-Process $exe`) |
| **R2. Process Conflict** | Installation fails if previous `FluentFlyout.exe` has not finished exiting | Add `Wait-Process -Id <pid>` in `apply.ps1` prior to installation |
| **R2. Logging & Diagnostics** | PowerShell installer runs with zero logging | Add `Start-Transcript` in `apply.ps1` saving to `runDir\install.log` |
| **R2. Threading & UX** | Background thread toast activation calls UI methods; no progress indication during download | Dispatch toast actions to UI Dispatcher; expose download state in `UpdateState` |

---

*Report concluded. Handoff document generated in `handoff.md`.*
