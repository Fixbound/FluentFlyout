// Copyright (c) 2024-2026 The FluentFlyout Authors
// SPDX-License-Identifier: GPL-3.0-or-later

using FluentFlyoutWPF.Classes.Clients;
using NLog;
using System.Net.Http;
using System.Text.Json;

namespace FluentFlyoutWPF.Classes.Services;

/// <summary>
/// Handles checking for application updates from the API
/// </summary>
public static class UpdateCheckerService
{
    private static readonly Logger Logger = LogManager.GetCurrentClassLogger();
    private const string ApiEndpoint = "newest-version";

    /// <summary>
    /// Result of an update check
    /// </summary>
    public class UpdateCheckResult
    {
        public bool IsUpdateAvailable { get; set; }
        public string NewestVersion { get; set; } = string.Empty;
        public string UpdateUrl { get; set; } = string.Empty;
        public string AssetUrl { get; set; } = string.Empty;
        public string ExpectedSha256 { get; set; } = string.Empty;
        public DateTime CheckedAt { get; set; }
        public bool Success { get; set; }
    }

    private const string GitHubApiLatestRelease = "https://api.github.com/repos/unchihugo/FluentFlyout/releases/latest";

    /// <summary>
    /// Check for updates: GitHub Releases is the source of truth for GitHub builds; the site API is the fallback.
    /// </summary>
    /// <param name="currentVersion">The current app version (e.g., "v2.5.0")</param>
    /// <returns>UpdateCheckResult with update information</returns>
    public static async Task<UpdateCheckResult> CheckForUpdatesAsync(string currentVersion)
    {
        var result = new UpdateCheckResult
        {
            CheckedAt = DateTime.Now
        };

        try
        {
            try
            {
                var response = await FluentFlyoutApiClient.GetUrlAsync(GitHubApiLatestRelease);
                var json = JsonDocument.Parse(response);

                var (assetUrl, expectedSha256) = ParseInstallerAsset(json);

                result.NewestVersion = json.RootElement.GetProperty("tag_name").GetString() ?? string.Empty;
                result.UpdateUrl = json.RootElement.GetProperty("html_url").GetString() ?? string.Empty;
                result.AssetUrl = assetUrl;
                result.ExpectedSha256 = expectedSha256;
                result.Success = true;

                // Compare versions
                result.IsUpdateAvailable = currentVersion != "debug" && IsNewerVersion(currentVersion, result.NewestVersion);

                Logger.Info($"Update check complete (GitHub). Current: {currentVersion}, Newest: {result.NewestVersion}, Update available: {result.IsUpdateAvailable}");
                return result;
            }
            catch (Exception ex) when (ex is HttpRequestException or TaskCanceledException)
            {
                Logger.Info(ex, "GitHub update check failed, falling back to the site API.");
            }

            var response = await FluentFlyoutApiClient.GetStringAsync(ApiEndpoint);
            var json = JsonDocument.Parse(response);

            result.NewestVersion = json.RootElement.GetProperty("version").GetString() ?? string.Empty;
            result.UpdateUrl = json.RootElement.GetProperty("url").GetString() ?? string.Empty;
            result.Success = true;

            // Compare versions
            result.IsUpdateAvailable = currentVersion != "debug" && IsNewerVersion(currentVersion, result.NewestVersion);

            Logger.Info($"Update check complete (site). Current: {currentVersion}, Newest: {result.NewestVersion}, Update available: {result.IsUpdateAvailable}");
        }
        catch (HttpRequestException ex)
        {
            Logger.Info($"Failed to check for updates - network error: {ex.Message}");
            result.Success = false;
        }
        catch (TaskCanceledException ex)
        {
            Logger.Info(ex, "Failed to check for updates - request timed out.");
            result.Success = false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Unexpected error checking for updates");
            result.Success = false;
        }

        return result;
    }

    /// <summary>
    /// Picks the installer asset download URL and its expected SHA-256 (from the release notes) out of a GitHub release payload.
    /// Returns empty strings when the release carries no installer asset or digest, which disables the in-app update path.
    /// </summary>
    private static (string assetUrl, string sha256) ParseInstallerAsset(JsonDocument release)
    {
        string assetUrl = string.Empty;
        string sha256 = string.Empty;

        if (release.RootElement.TryGetProperty("assets", out var assetsElement))
        {
            foreach (var asset in assetsElement.GetJsonArray())
            {
                if (!asset.TryGetProperty("name", out var nameElement))
                    continue;

                var name = nameElement.GetString();
                if (name is null || !name.EndsWith("Installer.zip", true))
                    continue;

                var url = asset.GetProperty("browser_download_url").GetString();
                if (url is not null && (assetUrl == string.Empty || name.Contains("x64", true)))
                {
                    assetUrl = url;
                }
            }
        }

        if (release.RootElement.TryGetProperty("body", out var bodyElement))
        {
            var match = Regex.Match(bodyElement.GetString() ?? string.Empty, @"GitHub Release x64\D*?([0-9a-fA-F]{64})");
            sha256 = match?[1]?["1"] ?? string.Empty;
        }

        return (assetUrl, sha256);
    }

    public static void OpenUpdateUrl(string url)
    {
        if (string.IsNullOrEmpty(url)) return;

        try
        {
            System.Diagnostics.Process.Start(new System.Diagnostics.ProcessStartInfo
            {
                FileName = url,
                UseShellExecute = true
            });
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Failed to open update URL");
        }
    }

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
}