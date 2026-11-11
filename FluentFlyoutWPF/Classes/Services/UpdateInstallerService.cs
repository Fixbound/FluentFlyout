// Copyright (c) 2024-2026 The FluentFlyout Authors
// SPDX-License-Identifier: GPL-3.0-or-later

using FluentFlyout.Classes.Settings;
using FluentFlyoutWPF.ViewModels;
using NLog;
using System.Diagnostics;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Security.Cryptography;
using System.Windows;

namespace FluentFlyoutWPF.Classes.Services;

/// <summary>
/// Applies a pending GitHub release update in-app: download the installer asset, verify its SHA-256 digest,
/// install it through the dev package installer, and relaunch the app. Failures preserve the scratch run
/// directory so the flow can be retried.
/// </summary>
public static class UpdateInstallerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();

    private const string AppTempDir = "FluentFlyout";
    private const string UpdatesDir = "updates";
    private const long DownloadTimeoutMs = 5 * 60_000;
    private const int KeepUpdateRuns = 3;

    private static readonly HttpClient DownloadClient = CreateDownloadClient();

    private static HttpClient CreateDownloadClient()
    {
        var client = new HttpClient
        {
            Timeout = TimeSpan.FromMilliseconds(DownloadTimeoutMs)
        };
        client.DefaultRequestHeaders.TryAddWithoutValidation("User-Agent", "FluentFlyout-Updater");
        return client;
    }

    /// <summary>
    /// Silently applies the pending update: download, digest verification, install, relaunch.
    /// Returns false when the download or the verification failed; the caller shows the failure toast.
    /// </summary>
    public static async Task<bool> AutoApplyPendingUpdateAsync()
    {
        var runDir = await DownloadAndVerifyAsync();

        if (string.IsNullOrEmpty(runDir))
        {
            return false;
        }

        ApplyRun(runDir);
        return true;
    }

    /// <summary>
    /// Manual update flow: ask whether to apply the pending update. A deliberate check always offers
    /// the update, even when the version was skipped before.
    /// Ensures UI interactions occur on the Dispatcher thread.
    /// </summary>
    public static async Task ShowUpdateChoiceAndApplyAsync()
    {
        if (Application.Current != null && !Application.Current.Dispatcher.CheckAccess())
        {
            await Application.Current.Dispatcher.InvokeAsync(async () => await ShowUpdateChoiceAndApplyAsync());
            return;
        }

        var version = UpdateState.Current.NewestVersion;

        // If no installer asset is attached to this release (e.g. upstream release without binaries)
        if (string.IsNullOrWhiteSpace(UpdateState.Current.AssetUrl))
        {
            var noAssetContent = $"Se encontró la versión {version} en GitHub, pero esta versión no incluye un instalador adjunto para descarga automática.\n\n¿Deseas abrir la página de la versión en GitHub?";
            var noAssetTitle = "Actualización disponible";

            var openWeb = MessageBox.Show(
                noAssetContent,
                noAssetTitle,
                MessageBoxButton.YesNo,
                MessageBoxImage.Information);

            if (openWeb == MessageBoxResult.Yes)
            {
                string url = !string.IsNullOrEmpty(UpdateState.Current.UpdateUrl) ? UpdateState.Current.UpdateUrl : "https://github.com/unchihugo/FluentFlyout/releases";
                UpdateCheckerService.OpenUpdateUrl(url);
            }
            return;
        }

        var updateDialogContent = Application.Current?.FindResource("UpdateDialogContent")?.ToString() ?? "An update ({0}) is available. Would you like to install it now?";
        var updateDialogTitle = Application.Current?.FindResource("UpdateDialogTitle")?.ToString() ?? "Update";

        var result = MessageBox.Show(
            string.Format(updateDialogContent, version),
            updateDialogTitle,
            MessageBoxButton.YesNo,
            MessageBoxImage.Question);

        if (result != MessageBoxResult.Yes)
        {
            var skipDialogContent = Application.Current?.FindResource("SkipVersionDialogContent")?.ToString() ?? "Would you like to skip version {0}?";
            var skipDialogTitle = Application.Current?.FindResource("SkipVersionDialogTitle")?.ToString() ?? "Skip Update";

            var skipDialog = MessageBox.Show(
                string.Format(skipDialogContent, version),
                skipDialogTitle,
                MessageBoxButton.YesNo,
                MessageBoxImage.Question);

            if (skipDialog == MessageBoxResult.Yes)
            {
                SettingsManager.Current.SkippedUpdateVersion = version;
            }

            return;
        }

        var runDir = await DownloadAndVerifyAsync();

        if (string.IsNullOrEmpty(runDir))
        {
            var failedContent = Application.Current?.FindResource("UpdateFailedMessage")?.ToString() ?? "Failed to download and verify update {0}.";
            var failedTitle = Application.Current?.FindResource("UpdateFailedTitle")?.ToString() ?? "Update Failed";

            MessageBox.Show(
                string.Format(failedContent, version),
                failedTitle,
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            return;
        }

        ApplyRun(runDir);
    }

    /// <summary>
    /// Downloads the installer asset to a scratch run directory and verifies its SHA-256 digest against
    /// the digest published by the release. Returns the run directory, or an empty string on failure.
    /// </summary>
    private static async Task<string> DownloadAndVerifyAsync()
    {
        CleanOldUpdateRuns();

        var assetUrl = UpdateState.Current.AssetUrl;
        var expectedSha256 = UpdateState.Current.ExpectedSha256;
        var version = UpdateState.Current.NewestVersion;

        if (string.IsNullOrWhiteSpace(assetUrl) || string.IsNullOrWhiteSpace(version))
        {
            Logger.Warn("Download and verify aborted: missing asset URL or version in UpdateState.");
            return string.Empty;
        }

        // scratch layout: TEMP\FluentFlyout\updates\<version>\<epoch>
        var epoch = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var runDir = Path.Join(Path.GetTempPath(), AppTempDir, UpdatesDir, version, epoch.ToString());

        try
        {
            Directory.CreateDirectory(runDir);
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to create scratch directory {runDir}");
            return string.Empty;
        }

        bool isExe = assetUrl.EndsWith(".exe", StringComparison.OrdinalIgnoreCase);
        var targetFile = Path.Join(runDir, isExe ? "FluentFlyout_Setup.exe" : "update.zip");

        // Stream download directly via managed HttpClient
        bool downloaded = await DownloadFileAsync(assetUrl, targetFile);
        if (!downloaded)
        {
            return string.Empty;
        }

        // Verify SHA-256 hash using native managed cryptography
        if (!string.IsNullOrWhiteSpace(expectedSha256))
        {
            bool verified = await VerifyFileHashAsync(targetFile, expectedSha256);
            if (!verified)
            {
                return string.Empty;
            }
        }
        else
        {
#if GITHUB_RELEASE
            Logger.Error($"Update rejected: SHA-256 digest is strictly required under GITHUB_RELEASE but was missing for version {version}.");
            return string.Empty;
#else
            Logger.Warn($"No expected SHA-256 provided for update {version}; proceeding without digest verification.");
#endif
        }

        return runDir;
    }

    /// <summary>
    /// Streams an update asset directly to disk asynchronously.
    /// </summary>
    private static async Task<bool> DownloadFileAsync(string url, string destinationPath)
    {
        try
        {
            Logger.Info($"Downloading update asset from {url} to {destinationPath}...");
            using var response = await DownloadClient.GetAsync(url, HttpCompletionOption.ResponseHeadersRead);
            response.EnsureSuccessStatusCode();

            await using var stream = await response.Content.ReadAsStreamAsync();
            await using var fileStream = new FileStream(destinationPath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, useAsync: true);
            await stream.CopyToAsync(fileStream);

            Logger.Info($"Downloaded update asset successfully ({fileStream.Length} bytes)");
            return true;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to download update from {url} to {destinationPath}");
            if (File.Exists(destinationPath))
            {
                try { File.Delete(destinationPath); } catch { }
            }
            return false;
        }
    }

    /// <summary>
    /// Computes and verifies SHA-256 hash of a file using native .NET cryptography.
    /// </summary>
    private static async Task<bool> VerifyFileHashAsync(string filePath, string expectedSha256)
    {
        try
        {
            if (!File.Exists(filePath))
            {
                Logger.Error($"File to verify does not exist: {filePath}");
                return false;
            }

            Logger.Info($"Verifying SHA-256 checksum for {filePath} against expected: {expectedSha256}...");
            await using var stream = File.OpenRead(filePath);
            byte[] hashBytes = await SHA256.HashDataAsync(stream);
            string actualSha256 = Convert.ToHexString(hashBytes);

            if (string.Equals(actualSha256, expectedSha256, StringComparison.OrdinalIgnoreCase))
            {
                Logger.Info($"SHA-256 verification passed: {actualSha256}");
                return true;
            }

            Logger.Error($"SHA-256 digest mismatch for {filePath}. Expected: {expectedSha256}, Actual: {actualSha256}");
            return false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to compute SHA-256 hash for {filePath}");
            return false;
        }
    }

    /// <summary>
    /// Starts the install pipeline for a verified run:
    /// Unpacks the archive in C# before initiating shutdown, verifies that Add-AppDevPackage.ps1 exists,
    /// writes apply.ps1, launches elevated detached PowerShell, and terminates the app cleanly.
    /// </summary>
    private static void ApplyRun(string runDir)
    {
        var extractDir = Path.Join(runDir, "files");
        var zipPath = Path.Join(runDir, "update.zip");
        var exePath = Path.Join(runDir, "FluentFlyout_Setup.exe");
        var applyScript = Path.Join(runDir, "apply.ps1");

        try
        {
            string systemFilesDir = runDir;

            if (File.Exists(exePath))
            {
                systemFilesDir = runDir;
            }
            else if (File.Exists(zipPath))
            {
                Logger.Info($"Extracting update archive {zipPath} to {extractDir}...");
                if (Directory.Exists(extractDir))
                {
                    Directory.Delete(extractDir, recursive: true);
                }

                ZipFile.ExtractToDirectory(zipPath, extractDir, overwriteFiles: true);
                Logger.Info($"Archive extracted successfully to {extractDir}");

                var exeFiles = Directory.GetFiles(extractDir, "*.exe", SearchOption.AllDirectories)
                    .Where(f => Path.GetFileName(f).Contains("Setup", StringComparison.OrdinalIgnoreCase) ||
                                Path.GetFileName(f).Contains("Installer", StringComparison.OrdinalIgnoreCase))
                    .ToArray();

                if (exeFiles.Length > 0)
                {
                    systemFilesDir = Path.GetDirectoryName(exeFiles[0]) ?? extractDir;
                }
                else
                {
                    // Locate Add-AppDevPackage.ps1 within extracted files
                    string installerScript = Path.Join(extractDir, "SystemFiles", "Add-AppDevPackage.ps1");
                    if (!File.Exists(installerScript))
                    {
                        var matchingFiles = Directory.GetFiles(extractDir, "Add-AppDevPackage.ps1", SearchOption.AllDirectories);
                        if (matchingFiles.Length > 0)
                        {
                            installerScript = matchingFiles[0];
                        }
                    }

                    if (File.Exists(installerScript))
                    {
                        systemFilesDir = Path.GetDirectoryName(installerScript) ?? extractDir;
                    }
                }
            }
            else
            {
                Logger.Error($"No installer package found at {runDir}");
                return;
            }

            int currentPid = Environment.ProcessId;

            var scriptBody = BuildApplyScriptContent(currentPid, systemFilesDir);
            File.WriteAllText(applyScript, scriptBody);

            Logger.Info($"Generated installer script at {applyScript}. Launching elevated PowerShell...");

            bool isExe = File.Exists(exePath);

            var startInfo = new ProcessStartInfo
            {
                FileName = "powershell.exe",
                Arguments = $"-NoProfile -ExecutionPolicy Bypass -File \"{applyScript}\"",
                UseShellExecute = true,
                Verb = isExe ? string.Empty : "runas",
                WorkingDirectory = runDir
            };

            var proc = Process.Start(startInfo);
            if (proc != null)
            {
                Logger.Info($"Detached installer launched successfully (PID: {proc.Id}). Shutting down application.");
                Application.Current.Shutdown();
            }
            else
            {
                Logger.Error($"Process.Start returned null for {applyScript}");
            }
        }
        catch (System.ComponentModel.Win32Exception winEx)
        {
            Logger.Warn(winEx, "Update installation was canceled by user or elevation was denied.");
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to prepare or start update installer for {runDir}");
        }
    }

    /// <summary>
    /// Generates the decoupled PowerShell script that waits for process exit,
    /// navigates to SystemFiles, executes the installer or Add-AppDevPackage.ps1, logs output, and relaunches the app.
    /// </summary>
    internal static string BuildApplyScriptContent(int pid, string systemFilesDir)
    {
        var escapedSystemFilesDir = systemFilesDir.Replace("'", "''");

        return
            "$ErrorActionPreference = 'Stop'\r\n" +
            "$logPath = Join-Path $PSScriptRoot 'update_install.log'\r\n" +
            "Start-Transcript -Path $logPath -Append -Force\r\n\r\n" +
            "try {\r\n" +
            $"    Write-Output 'Waiting for FluentFlyout process (PID: {pid}) to terminate...'\r\n" +
            "    try {\r\n" +
            $"        Wait-Process -Id {pid} -Timeout 30 -ErrorAction SilentlyContinue\r\n" +
            "    } catch {\r\n" +
            "        Write-Output 'Process already exited or not found.'\r\n" +
            "    }\r\n" +
            "    Get-Process FluentFlyout -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue\r\n" +
            "    Start-Sleep -Seconds 1\r\n\r\n" +
            $"    $systemFiles = '{escapedSystemFilesDir}'\r\n" +
            "    Write-Output \"Changing directory to SystemFiles: $systemFiles\"\r\n" +
            "    Set-Location -LiteralPath $systemFiles\r\n\r\n" +
            "    $exeSetup = Get-ChildItem -Path $PSScriptRoot -Filter '*Setup*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1\r\n" +
            "    if (-not $exeSetup) {\r\n" +
            "        $exeSetup = Get-ChildItem -Path $systemFiles -Filter '*Setup*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1\r\n" +
            "    }\r\n" +
            "    if (-not $exeSetup) {\r\n" +
            "        $exeSetup = Get-ChildItem -Path $systemFiles -Filter '*Installer*.exe' -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1\r\n" +
            "    }\r\n" +
            "    if ($exeSetup) {\r\n" +
            "        Write-Output \"Executing installer: $($exeSetup.FullName) /VERYSILENT /SUPPRESSMSGBOXES /NORESTART\"\r\n" +
            "        $p = Start-Process -FilePath $exeSetup.FullName -ArgumentList '/VERYSILENT /SUPPRESSMSGBOXES /NORESTART' -PassThru -Wait\r\n" +
            "        Write-Output \"Installer finished with exit code $($p.ExitCode)\"\r\n" +
            "    } elseif (Test-Path '.\\Add-AppDevPackage.ps1') {\r\n" +
            "        Write-Output 'Executing Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry...'\r\n" +
            "        & '.\\Add-AppDevPackage.ps1' -Force -SkipLoggingTelemetry\r\n" +
            "        Write-Output 'Add-AppDevPackage.ps1 completed.'\r\n" +
            "    } else {\r\n" +
            "        Write-Warning 'No supported installer found.'\r\n" +
            "    }\r\n\r\n" +
            "    Write-Output 'Relaunching FluentFlyout application...'\r\n" +
            "    $localAppExe = Join-Path $env:LOCALAPPDATA 'Programs\\FluentFlyout\\FluentFlyout.exe'\r\n" +
            "    if (Test-Path $localAppExe) {\r\n" +
            "        $localAppDir = Split-Path $localAppExe\r\n" +
            "        Start-Process -FilePath $localAppExe -WorkingDirectory $localAppDir\r\n" +
            "        Write-Output \"Started $localAppExe\"\r\n" +
            "    } else {\r\n" +
            "        $pkg = Get-AppxPackage '*FluentFlyout*' | Select-Object -First 1\r\n" +
            "        if ($pkg) {\r\n" +
            "            $exe1 = Join-Path $pkg.InstallLocation 'FluentFlyout\\FluentFlyout.exe'\r\n" +
            "            $exe2 = Join-Path $pkg.InstallLocation 'FluentFlyout.exe'\r\n" +
            "            if (Test-Path $exe1) {\r\n" +
            "                Start-Process -FilePath $exe1\r\n" +
            "                Write-Output \"Started $exe1\"\r\n" +
            "            } elseif (Test-Path $exe2) {\r\n" +
            "                Start-Process -FilePath $exe2\r\n" +
            "                Write-Output \"Started $exe2\"\r\n" +
            "            } else {\r\n" +
            "                explorer.exe \"shell:AppsFolder\\$($pkg.PackageFamilyName)!App\"\r\n" +
            "                Write-Output 'Started via AppsFolder'\r\n" +
            "            }\r\n" +
            "        } else {\r\n" +
            "            Write-Warning 'Could not find installed FluentFlyout package to relaunch.'\r\n" +
            "        }\r\n" +
            "    }\r\n" +
            "} catch {\r\n" +
            "    Write-Error \"Update installation failed: $_\"\r\n" +
            "} finally {\r\n" +
            "    Stop-Transcript -ErrorAction SilentlyContinue\r\n" +
            "}\r\n";
    }

    /// <summary>
    /// Removes old scratch update runs, keeping only the most recent ones.
    /// </summary>
    private static void CleanOldUpdateRuns()
    {
        try
        {
            var updatesRoot = Path.Join(Path.GetTempPath(), AppTempDir, UpdatesDir);
            if (!Directory.Exists(updatesRoot))
            {
                return;
            }

            var runs = new List<DirectoryInfo>();
            foreach (var versionDir in Directory.GetDirectories(updatesRoot))
            {
                foreach (var runDir in Directory.GetDirectories(versionDir))
                {
                    runs.Add(new DirectoryInfo(runDir));
                }
            }

            if (runs.Count <= KeepUpdateRuns)
            {
                return;
            }

            // Sort newest first by parsed epoch or creation time
            runs.Sort((a, b) =>
            {
                if (long.TryParse(b.Name, out var epochB) && long.TryParse(a.Name, out var epochA))
                {
                    return epochB.CompareTo(epochA);
                }
                return b.CreationTimeUtc.CompareTo(a.CreationTimeUtc);
            });

            for (var i = KeepUpdateRuns; i < runs.Count; ++i)
            {
                try
                {
                    runs[i].Delete(recursive: true);
                }
                catch (Exception ex)
                {
                    Logger.Warn(ex, $"Could not delete old update run: {runs[i].FullName}");
                }
            }

            // drop version folders left without any runs
            foreach (var versionDir in Directory.GetDirectories(updatesRoot))
            {
                if (!Directory.EnumerateFileSystemEntries(versionDir).Any())
                {
                    try
                    {
                        Directory.Delete(versionDir, recursive: true);
                    }
                    catch { }
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to clean old update runs");
        }
    }
}