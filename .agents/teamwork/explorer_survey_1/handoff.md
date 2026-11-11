# Handoff Report: Auto-Updater Service & GitHub Fork API Endpoint (R1 & R2)

**Agent ID**: `explorer_survey_1`  
**Working Directory**: `E:\Programacion\FluentFlyout\.agents\teamwork\explorer_survey_1\`  
**Target Codebase**: `E:\Programacion\FluentFlyout`  
**Handoff Type**: Hard (Investigation & Survey Complete)  

---

## 1. Observation

### 1.1 Git Remotes and Repository Fork
- **Command**: `git -C "E:\Programacion\FluentFlyout" remote -v`
  - Output:
    ```
    origin  https://github.com/unchihugo/FluentFlyout.git (fetch)
    origin  https://github.com/unchihugo/FluentFlyout.git (push)
    ```
- **File**: `E:\Programacion\FluentFlyout\FluentFlyoutMSIX\Package.appxmanifest`
  - Lines 12–14:
    ```xml
    <Identity
      Name="unchihugo.FluentFlyout"
      Publisher="CN=49793F74-1457-4B66-A672-4ED3A640FC76"
      Version="2.16.0.0" />
    ```
- **File**: `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\LicenseManager.cs`
  - Lines 87–92:
    ```csharp
    #if GITHUB_RELEASE
                _isStoreVersion = false;
                _isPremiumUnlocked = true;
                _isInitialized = true;
                return;
    #endif
    ```

### 1.2 Update Checker Service & Endpoint Configuration
- **File**: `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\Services\UpdateCheckerService.cs`
  - Line 34:
    ```csharp
    private const string GitHubApiLatestRelease = "https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest";
    ```
  - Lines 69–84:
    ```csharp
    catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
    {
        Logger.Info(ex, "GitHub update check failed, falling back to the site API.");
    }

    var siteResponse = await FluentFlyoutApiClient.GetStringAsync(ApiEndpoint);
    var siteJson = JsonDocument.Parse(siteResponse);
    ```
  - Lines 133–137:
    ```csharp
    if (release.RootElement.TryGetProperty("body", out var bodyElement))
    {
        var match = Regex.Match(bodyElement.GetString() ?? string.Empty, @"GitHub Release x64\D*?([0-9a-fA-F]{64})");
        sha256 = (match.Success && match.Groups.Count > 1) ? match.Groups[1].Value : string.Empty;
    }
    ```
  - Lines 160–167:
    ```csharp
    private static bool IsNewerVersion(string currentVersion, string newestVersion)
    {
        try
        {
            var current = Version.Parse(currentVersion.TrimStart('v'));
            var newest = Version.Parse(newestVersion.TrimStart('v'));
            return newest > current;
    ```
- **File**: `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\Clients\FluentFlyoutApiClient.cs`
  - Line 13: `private static readonly TimeSpan _timeout = TimeSpan.FromSeconds(2);`
  - Line 14: `private static readonly Uri _uri = new("https://fluentflyout.com/api/");`
  - Line 41: `public static async Task<string> GetUrlAsync(string absoluteUrl)` sets `Timeout = _timeout;` (2 seconds).

### 1.3 Update Installer Service & Execution
- **File**: `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\Services\UpdateInstallerService.cs`
  - Lines 118–123 (curl download):
    ```csharp
    var curlArgs = "--location --output " + Quote(zipPath) + " " + Quote(assetUrl);
    if (RunAndWait("curl.exe", curlArgs, DownloadTimeoutMs) != 0)
    {
        Logger.Error($"Failed to download {assetUrl} into {zipPath}");
        return string.Empty;
    }
    ```
  - Lines 127–133 (powershell verification):
    ```csharp
    var verifyCommand =
        "if ((Get-FileHash -Path " + Quote(zipPath) + " -Algorithm SHA256).Hash -ieq " + Quote(expectedSha256) + ") { exit 0 } else { exit 1 }";

    if (RunAndWait("powershell.exe", "-NoProfile -Command \"" + verifyCommand + "\"", VerifyTimeoutMs) != 0)
    ```
  - Lines 143–167 (ApplyRun script and execution):
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

### 1.4 CI Workflow and Installer Scripts
- **File**: `E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml`
  - Lines 80–86:
    ```powershell
    $zipName = "FluentFlyout_${{ env.APP_VERSION }}_${{ env.PLATFORM }}_Installer.zip"
    $zipPath = "$env:GITHUB_WORKSPACE\$zipName"
    Remove-Item $zipPath -ErrorAction Ignore
    Compress-Archive -Path "InstallerOutput\*" -DestinationPath $zipPath
    $sha = (Get-FileHash -Path $zipPath -Algorithm SHA256).Hash.ToLower()
    $tag = "v${{ env.APP_VERSION }}"
    $notes = "GitHub Release x64 installer: $zipName`nGitHub Release x64 checksum: $sha"
    ```
- **File**: `E:\Programacion\FluentFlyout\.github\build-files\FluentFlyout_Installer.bat`
  - Line 13: `cd /d "%~dp0SystemFiles"`
  - Line 16: `PowerShell -NoProfile -ExecutionPolicy Bypass -Command "& './Add-AppDevPackage.ps1' -SkipLoggingTelemetry"`
  - Line 30: `PowerShell -Command "& { $pkg = Get-AppxPackage '%AppNamePattern%' | Select-Object -First 1; if ($pkg) { $exe = Join-Path $pkg.InstallLocation 'FluentFlyout\FluentFlyout.exe'; Start-Process $exe } else { Write-Host 'Could not find installed App.' } }"`

### 1.5 Unit Test Status & Build Status
- **Solution File**: `E:\Programacion\FluentFlyout\FluentFlyout.sln` has 3 projects:
  - `FluentFlyoutWPF\FluentFlyout.csproj`
  - `FluentFlyoutMSIX\FluentFlyoutMSIX.wapproj`
  - `FluentFlyout.SourceGenerators\FluentFlyout.SourceGenerators.csproj`
  - Existing Unit Test Projects: **0**.
- **Command**: `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64`
  - Output: `Build succeeded. 0 Warning(s) 0 Error(s).`

---

## 2. Logic Chain

1. **Endpoint Resolution (R1)**:
   - *Observation 1.1* confirms that the GitHub repository fork is `unchihugo/FluentFlyout`.
   - *Observation 1.2* shows `UpdateCheckerService.cs` has hardcoded `https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest`.
   - *Observation 1.2* also shows that if GitHub check fails, it falls back to `FluentFlyoutApiClient.GetStringAsync("newest-version")`, hitting `fluentflyout.com/api/newest-version` (the upstream project).
   - If a user runs the fork and the GitHub API call fails or times out (which is probable due to the 2-second timeout in *Observation 1.2*), the application will fall back to upstream release metadata, which points to the non-fork application where premium features are locked.
   - *Conclusion*: The fork repository endpoint must be clearly parameterized, the timeout increased, and the fallback to `fluentflyout.com` must be disabled for GitHub builds.

2. **Regex Vulnerability in Checksum Extraction (R2)**:
   - *Observation 1.2* shows `Regex.Match(body, @"GitHub Release x64\D*?([0-9a-fA-F]{64})")`.
   - The token `\D` matches non-digits. If the release notes include digits prior to the hash (e.g. `(sha256)` or version `2.16`), `\D*?` cannot traverse the digits.
   - Tested in PowerShell: `[regex]::Match('GitHub Release x64 checksum (sha256): <hash>', 'GitHub Release x64\D*?([0-9a-fA-F]{64})').Groups[1].Value` returns empty string.
   - When SHA-256 is empty, `UpdateCheckerService` returns empty `ExpectedSha256`, which disables the in-app update flow in `MainWindow.xaml.cs:275` and `HomePage.xaml.cs:77`.
   - *Conclusion*: The regex must be replaced with a robust pattern matching `GitHub Release x64 checksum:\s*([0-9a-fA-F]{64})` and generic `sha256: <hash>`.

3. **External Process Dependencies & Flaws in Download/Verify (R2)**:
   - *Observation 1.3* shows downloading via `curl.exe` without `--fail` and verifying via `powershell.exe -Command Get-FileHash`.
   - Spawning external processes introduces console window flashing, blocking threads via `RunAndWait`, and risk of error suppression (HTTP 404 writing HTML to zip).
   - .NET 10 has native asynchronous `HttpClient` and `System.Security.Cryptography.SHA256` that run in-process in milliseconds with zero dependencies.
   - *Conclusion*: Replace `curl.exe` and `powershell.exe` hash checks with managed .NET async code.

4. **Fatal Flaws in Detached Package Installation (`apply.ps1`) (R2)**:
   - *Observation 1.3* shows `ApplyRun` writes `apply.ps1` with only `Expand-Archive` and `& Add-AppDevPackage.ps1`, then calls `Process.Start("powershell.exe", "-NoProfile -File apply.ps1")` and `Application.Current.Shutdown()`.
   - *Observation 1.4* shows `FluentFlyout_Installer.bat` executes with `-ExecutionPolicy Bypass`, runs inside `SystemFiles` directory, and explicitly relaunches `FluentFlyout.exe` via `Get-AppxPackage` after installation completes.
   - *Defect A*: `Add-AppDevPackage.ps1` does NOT relaunch the app. By calling only `Add-AppDevPackage.ps1`, the app shuts down and never reopens.
   - *Defect B*: Missing `-ExecutionPolicy Bypass` causes `powershell.exe` to fail on standard Windows machines with `Restricted` policy.
   - *Defect C*: Missing directory change means `Add-AppDevPackage.ps1` cannot find the `.msix` or `.cer` files.
   - *Defect D*: Missing `-Force` causes `Add-AppDevPackage.ps1` to hang indefinitely waiting for interactive console keyboard input `[Enter]`.
   - *Defect E*: Missing elevation (`runas`) prevents installing the test certificate to the Local Machine Root store.
   - *Defect F*: Unpacking in PowerShell *after* `Application.Current.Shutdown()` leaves the user stranded if the zip is corrupt.
   - *Defect G*: If `FluentFlyout.exe` is still exiting when `Add-AppDevPackage.ps1` starts, Windows MSIX deployment service fails with error `0x80073D02` (in-use files).
   - *Conclusion*: Extract in C# before shutdown. Generate `apply.ps1` that waits for process termination, changes directory, executes `Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry`, relaunches `FluentFlyout.exe`, and runs elevated.

---

## 3. Caveats

1. **No Existing Test Harnesses**: Because `FluentFlyout.sln` has zero unit test projects, all testing of updater logic currently requires manual end-to-end execution or mock test harnesses.
2. **Local Debug Environment Identity**: Running `FluentFlyoutWPF` via Visual Studio / `dotnet run` runs unpackaged without MSIX identity, causing `Package.Current.Id.Version` to throw and `LastKnownVersion` to default to `"debug"`. In `UpdateCheckerService`, `currentVersion == "debug"` deliberately suppresses update detection (`result.IsUpdateAvailable = false`). Local simulation of updates requires providing a mock version or test parameter.
3. **Pre-releases vs Latest Releases**: GitHub's `/releases/latest` endpoint excludes releases flagged as "Prerelease" or "Draft". If the fork publishes updates as prereleases, `/releases/latest` will return HTTP 404. Releases must be published as full releases or the endpoint should query `/releases` to inspect the newest release tag.

---

## 4. Conclusion

Requirements R1 and R2 can be cleanly and reliably achieved with the following specific modifications:

1. **Requirement R1**:
   - Refactor `UpdateCheckerService` to define `DefaultGitHubOwner = "unchihugo"`, `DefaultGitHubRepo = "FluentFlyout"`, and compose `GitHubReleasesApiUrl`.
   - Increase GitHub API request timeout from 2 seconds to 15 seconds.
   - Disable upstream `fluentflyout.com` fallback when running under `#if GITHUB_RELEASE` or when checking GitHub releases.
2. **Requirement R2**:
   - Upgrade SHA-256 regex to support standard patterns (`GitHub Release x64 checksum:\s*([0-9a-fA-F]{64})` and `(?i)(?:sha-?256|checksum)[^0-9a-f\r\n]*([0-9a-fA-F]{64})`).
   - Replace `curl.exe` with asynchronous managed `HttpClient` file streaming.
   - Replace PowerShell `Get-FileHash` with native `System.Security.Cryptography.SHA256.HashDataAsync`.
   - Unpack archive in C# using `ZipFile.ExtractToDirectory` before initiating shutdown; verify existence of `SystemFiles\Add-AppDevPackage.ps1`.
   - Generate `apply.ps1` with:
     * Transcript logging to `install.log`.
     * `Wait-Process -Id <pid>` to prevent MSIX in-use file lock errors.
     * Working directory navigation to `SystemFiles`.
     * Execution of `Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry`.
     * Relaunching of the application via `Get-AppxPackage '*FluentFlyout*'`.
   - Launch `powershell.exe` with `-ExecutionPolicy Bypass`, `UseShellExecute = true`, and `Verb = "runas"` for UAC elevation.
   - Ensure toast notification callbacks dispatch UI dialogs to the Dispatcher thread.

---

## 5. Verification Method

### Independent Verification Commands:
1. **Compilation Check**:
   ```powershell
   Set-Location "E:\Programacion\FluentFlyout"
   dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64
   ```
   *Expected*: Build succeeds with 0 errors and 0 warnings.

2. **Regex Digest Parsing Verification**:
   ```powershell
   [regex]::Match("GitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip`nGitHub Release x64 checksum: e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", "(?i)(?:GitHub Release x64\s+(?:checksum|sha256)|sha-?256|checksum)[\s:]+([0-9a-fA-F]{64})").Groups[1].Value
   ```
   *Expected*: Returns `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855`.

3. **Inspection of Key Files**:
   - `E:\Programacion\FluentFlyout\.agents\teamwork\explorer_survey_1\analysis.md`
   - `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\Services\UpdateCheckerService.cs`
   - `E:\Programacion\FluentFlyout\FluentFlyoutWPF\Classes\Services\UpdateInstallerService.cs`
   - `E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml`
   - `E:\Programacion\FluentFlyout\.github\build-files\FluentFlyout_Installer.bat`

### Invalidation Conditions:
- If GitHub API releases change the schema and no longer publish release notes containing the SHA-256 hash or an asset ending with `Installer.zip`.
- If the repository fork owner or repository name changes from `unchihugo/FluentFlyout`.
