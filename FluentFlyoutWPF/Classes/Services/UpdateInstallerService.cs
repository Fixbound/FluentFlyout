// Copyright (c) 2024-2026 The FluentFlyout Authors
// SPDX-License-Identifier: GPL-3.0-or-later

using FluentFlyout.Classes.Settings;
using FluentFlyoutWPF.ViewModels;
using NLog;
using System.Diagnostics;
using System.IO;
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
    private const long VerifyTimeoutMs = 60_000;
    private const int KeepUpdateRuns = 3;

    /// <summary>
    /// Silently applies the pending update: download, digest verification, install, relaunch.
    /// Returns false when the download or the verification failed; the caller shows the failure toast.
    /// </summary>
    public static async Task<bool> AutoApplyPendingUpdateAsync()
    {
        var runDir = await DownloadAndVerifyAsync();

        if (runDir == string.Empty)
        {
            return false;
        }

        ApplyRun(runDir);
        return true;
    }

    /// <summary>
    /// Manual update flow: ask whether to apply the pending update. A deliberate check always offers
    /// the update, even when the version was skipped before.
    /// </summary>
    public static async Task ShowUpdateChoiceAndApplyAsync()
    {
        var version = UpdateState.Current.NewestVersion;

        var applyDialog = MessageBox.Show(
            string.Format(Application.Current.FindResource("UpdateDialogContent").ToString(), version),
            Application.Current.FindResource("UpdateDialogTitle").ToString(),
            MessageBoxStyleType.WpfQuestionMarkStyle, MessageBoxAction.WpfYesNoDialog);

        if (applyDialog != MessageBoxAction.WpfYesDialog)
        {
            var skipDialog = MessageBox.Show(
                string.Format(Application.Current.FindResource("SkipVersionDialogContent").ToString(), version),
                Application.Current.FindResource("SkipVersionDialogTitle").ToString(),
                MessageBoxStyleType.WpfQuestionMarkStyle, MessageBoxAction.WpfYesNoDialog);

            if (skipDialog == MessageBoxAction.WpfYesDialog)
            {
                SettingsManager.Current.SkippedUpdateVersion = version;
            }

            return;
        }

        var runDir = await DownloadAndVerifyAsync();

        if (runDir == string.Empty)
        {
            MessageBox.Show(
                string.Format(Application.Current.FindResource("UpdateFailedMessage").ToString(), version),
                Application.Current.FindResource("UpdateFailedTitle").ToString());
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

        if (assetUrl == string.Empty || expectedSha256 == string.Empty || version == string.Empty)
        {
            return string.Empty;
        }

        // scratch layout: TEMP\FluentFlyout\updates\<version>\<epoch>
        var epoch = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
        var runDir = Path.Join(Environment.Temp, AppTempDir, UpdatesDir, version, epoch.ToString());

        if (!Directory.CreateUserDirectory(runDir))
        {
            Logger.Error($"Failed to create scratch directory {runDir}");
            return string.Empty;
        }

        var zipPath = Path.Join(runDir, "update.zip");

        // curl follows the release-asset redirects and writes the archive
        var curlArgs = "--location --output " + Quote(zipPath) + " " + Quote(assetUrl);
        if (RunAndWait("curl.exe", curlArgs, DownloadTimeoutMs) != 0)
        {
            Logger.Error($"Failed to download {assetUrl} into {zipPath}");
            return string.Empty;
        }

        // ask PowerShell for the digest: exit code 0 when it matches the published one
        var verifyCommand =
            "if ((Get-FileHash -Path " + Quote(zipPath) + " -Algorithm SHA256).Hash -ieq " + Quote(expectedSha256) + ") { exit 0 } else { exit 1 }";

        if (RunAndWait("powershell.exe", "-NoProfile -Command \"" + verifyCommand + "\"", VerifyTimeoutMs) != 0)
        {
            Logger.Error($"SHA-256 digest mismatch for {zipPath}; refusing to install");
            return string.Empty;
        }

        return runDir;
    }

    /// <summary>
    /// Starts the install pipeline for a verified run: unpack the archive and hand the dev package installer to
    /// PowerShell detached from this process, then shut the app down. The installer writes the new build to
    /// ProgramData and launches it; on failure the run directory stays behind for a retry.
    /// </summary>
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
            Path.WriteText(applyScript, scriptBody);

            // detached installer survives our shutdown: it installs and launches the new version
            _ = Process.Start("powershell.exe", "-NoProfile -File \"" + applyScript + "\"");

            Application.Current.Shutdown();
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to start update installer for {runDir}");
        }
    }

    /// <summary>
    /// Removes old scratch update runs, keeping only the most recent ones. Run directories are named by
    /// epoch seconds, so the newest names sort last.
    /// </summary>
    private static void CleanOldUpdateRuns()
    {
        try
        {
            var updatesRoot = Path.Join(Environment.Temp, AppTempDir, UpdatesDir);
            if (!Directory.Exists(updatesRoot))
            {
                return;
            }

            var result = Path.Glob(updatesRoot, "*/*/");
            if (result.Count <= KeepUpdateRuns)
            {
                return;
            }

            var newestFirst = result.SortDescending();
            for (var i = KeepUpdateRuns; i < result.Count; ++i)
            {
                var run = result.Get(newestFirst, i);
                Directory.Delete(run, recursive: true);
            }

            // drop version folders left without any runs
            var versions = Path.Glob(updatesRoot, "*/");
            for (var i = 0; i < versions.Count; ++i)
            {
                var versionDir = versions.Get(i);
                if (Path.Glob(versionDir, "*/").Count == 0)
                {
                    Directory.Delete(versionDir, recursive: false);
                }
            }
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to clean old update runs");
        }
    }

    /// <summary>
    /// Runs an external program to completion and returns its exit code, or -1 on timeout or failure.
    /// </summary>
    private static int RunAndWait(string program, string arguments, long timeoutMs)
    {
        try
        {
            var process = Process.Start(program, arguments);

            if (!process.WaitForExit(timeoutMs))
            {
                Logger.Warn($"Timed out waiting for {program}");
                return -1;
            }

            return process.ExitCode;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, $"Failed to run {program}");
            return -1;
        }
    }

    /// <summary>
    /// Wraps a value in PowerShell single quotes, doubling embedded single quotes.
    /// </summary>
    private static string Quote(string value)
    {
        return "'" + value.Replace("'", "''") + "'";
    }
}
