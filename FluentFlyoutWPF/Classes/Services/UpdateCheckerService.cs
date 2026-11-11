// Copyright (c) 2024-2026 The FluentFlyout Authors
// SPDX-License-Identifier: GPL-3.0-or-later

using FluentFlyoutWPF.Classes.Clients;
using NLog;
using System.Net.Http;
using System.Text.Json;
using System.Text.RegularExpressions;

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

    public const string DefaultGitHubOwner = "Fixbound";
    public const string DefaultGitHubRepo = "FluentFlyout";

    private static readonly TimeSpan GitHubTimeout = TimeSpan.FromSeconds(15);
    private static readonly HttpClient GitHubHttpClient = CreateGitHubHttpClient();

    private static readonly Regex Sha256WorkflowRegex = new(
        @"(?im)^[^\r\n]*?\bgithub\s+release\s+x64\b[^\r\n]*?\b([0-9a-fA-F]{64})\b",
        RegexOptions.Compiled);

    private static readonly Regex Sha256X64Regex = new(
        @"(?im)^[^\r\n]*?\bx64\b[^\r\n]*?(?:checksum|sha-?256|hash|digest|[|:])[^\r\n]*?\b([0-9a-fA-F]{64})\b",
        RegexOptions.Compiled);

    private static readonly Regex Sha256FallbackRegex = new(
        @"(?im)^[^\r\n]*?\b(?:sha-?256|checksum)\b[^\r\n]*?\b([0-9a-fA-F]{64})\b",
        RegexOptions.Compiled);

    private static readonly Regex Sha256GenericRegex = new(
        @"\b([0-9a-fA-F]{64})\b",
        RegexOptions.Compiled);

    /// <summary>
    /// Dynamic GitHub API endpoint for the latest release, with optional developer override support.
    /// </summary>
    public static string GitHubApiLatestRelease
    {
        get
        {
            var customRepo = Environment.GetEnvironmentVariable("FLUENTFLYOUT_UPDATE_REPO");
            if (!string.IsNullOrWhiteSpace(customRepo))
            {
                if (customRepo.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                    customRepo.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
                {
                    return customRepo.Trim();
                }

                if (customRepo.Contains('/'))
                {
                    return $"https://api.github.com/repos/{customRepo.Trim()}/releases/latest";
                }
            }
            return $"https://api.github.com/repos/{DefaultGitHubOwner}/{DefaultGitHubRepo}/releases/latest";
        }
    }

    private static HttpClient CreateGitHubHttpClient()
    {
        var client = new HttpClient
        {
            Timeout = GitHubTimeout
        };
        client.DefaultRequestHeaders.TryAddWithoutValidation("Accept", "application/vnd.github.v3+json");
        return client;
    }

    /// <summary>
    /// Check for updates: GitHub Releases is the source of truth for GitHub builds; the site API is the fallback.
    /// Under GITHUB_RELEASE, fallback to upstream site API is strictly disabled.
    /// </summary>
    /// <param name="currentVersion">The current app version (e.g., "v2.5.0")</param>
    /// <returns>UpdateCheckResult with update information</returns>
    public static async Task<UpdateCheckResult> CheckForUpdatesAsync(string currentVersion)
    {
        var result = new UpdateCheckResult
        {
            CheckedAt = DateTime.Now
        };

#if GITHUB_RELEASE
        try
        {
            var response = await FetchGitHubReleaseJsonAsync(GitHubApiLatestRelease, currentVersion);
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
        catch (HttpRequestException ex)
        {
            Logger.Info($"GitHub update check failed - network error: {ex.Message}");
            result.Success = false;
        }
        catch (TaskCanceledException ex)
        {
            Logger.Info(ex, "GitHub update check failed - request timed out (15s).");
            result.Success = false;
        }
        catch (Exception ex)
        {
            Logger.Error(ex, "Unexpected error checking for updates from GitHub");
            result.Success = false;
        }

        return result;
#else
        try
        {
            try
            {
                var response = await FetchGitHubReleaseJsonAsync(GitHubApiLatestRelease, currentVersion);
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

            var siteResponse = await FluentFlyoutApiClient.GetStringAsync(ApiEndpoint);
            var siteJson = JsonDocument.Parse(siteResponse);

            result.NewestVersion = siteJson.RootElement.GetProperty("version").GetString() ?? string.Empty;
            result.UpdateUrl = siteJson.RootElement.GetProperty("url").GetString() ?? string.Empty;
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
#endif
    }

    private static async Task<string> FetchGitHubReleaseJsonAsync(string url, string currentVersion)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, url);
        string userAgentVersion = string.IsNullOrWhiteSpace(currentVersion) ? "unknown" : currentVersion;
        request.Headers.TryAddWithoutValidation("User-Agent", $"FluentFlyout/{userAgentVersion}");

        using var response = await GitHubHttpClient.SendAsync(request);
        response.EnsureSuccessStatusCode();
        return await response.Content.ReadAsStringAsync();
    }

    /// <summary>
    /// Picks the installer asset download URL and its expected SHA-256 (from the release notes) out of a GitHub release payload.
    /// Prefers *x64*Installer.zip assets.
    /// Returns empty strings when the release carries no installer asset or digest, which disables the in-app update path.
    /// </summary>
    public static (string assetUrl, string sha256) ParseInstallerAsset(JsonDocument release)
    {
        string assetUrl = string.Empty;
        string sha256 = string.Empty;

        if (release.RootElement.TryGetProperty("assets", out var assetsElement))
        {
            foreach (var asset in assetsElement.EnumerateArray())
            {
                if (!asset.TryGetProperty("name", out var nameElement))
                    continue;

                var name = nameElement.GetString();
                if (string.IsNullOrEmpty(name))
                    continue;

                bool isInstallerZip = name.EndsWith("Installer.zip", StringComparison.OrdinalIgnoreCase) ||
                                     name.EndsWith("Setup.zip", StringComparison.OrdinalIgnoreCase);
                bool isSetupExe = name.EndsWith(".exe", StringComparison.OrdinalIgnoreCase) &&
                                  (name.Contains("Setup", StringComparison.OrdinalIgnoreCase) ||
                                   name.Contains("Installer", StringComparison.OrdinalIgnoreCase) ||
                                   name.StartsWith("FluentFlyout", StringComparison.OrdinalIgnoreCase));

                if (!isInstallerZip && !isSetupExe)
                    continue;

                if (!asset.TryGetProperty("browser_download_url", out var urlElement))
                    continue;

                var url = urlElement.GetString();
                if (string.IsNullOrEmpty(url))
                    continue;

                // Prefer explicit x64 installer assets
                if (name.Contains("x64", StringComparison.OrdinalIgnoreCase))
                {
                    assetUrl = url;
                    break;
                }
                else if (string.IsNullOrEmpty(assetUrl) && !name.Contains("arm64", StringComparison.OrdinalIgnoreCase))
                {
                    assetUrl = url;
                }
            }
        }

        if (release.RootElement.TryGetProperty("body", out var bodyElement))
        {
            var bodyText = bodyElement.GetString() ?? string.Empty;
            var match = Sha256WorkflowRegex.Match(bodyText);
            if (!match.Success)
            {
                match = Sha256X64Regex.Match(bodyText);
            }
            if (!match.Success)
            {
                match = Sha256FallbackRegex.Match(bodyText);
            }
            if (!match.Success)
            {
                match = Sha256GenericRegex.Match(bodyText);
            }

            if (match.Success && match.Groups.Count > 1)
            {
                sha256 = match.Groups[1].Value.Trim().ToLowerInvariant();
            }
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

    /// <summary>
    /// Compares two version strings taking into account SemVer 2.0.0 rules,
    /// 2-part/3-part/4-part normalization (defaulting omitted parts to 0),
    /// and prerelease upgrade transitions.
    /// </summary>
    /// <param name="currentVersion">The currently installed application version</param>
    /// <param name="newestVersion">The remote release version to evaluate</param>
    /// <returns>True if newestVersion represents a newer upgrade; otherwise false.</returns>
    public static bool IsNewerVersion(string currentVersion, string newestVersion)
    {
        try
        {
            if (string.IsNullOrWhiteSpace(newestVersion)) return false;

            string cleanCurrent = CleanVersionString(currentVersion);
            string cleanNewest = CleanVersionString(newestVersion);

            if (NormalizeVersion(cleanCurrent, out var current) && NormalizeVersion(cleanNewest, out var newest))
            {
                if (newest > current) return true;
                if (newest < current) return false;

                // Base versions are identical (e.g. 2.16.0 vs 2.16.0.0 or 2.16.0-beta.1 vs 2.16.0)
                string? preCurrent = ExtractPrerelease(currentVersion);
                string? preNewest = ExtractPrerelease(newestVersion);

                bool currentHasPre = !string.IsNullOrEmpty(preCurrent);
                bool newestHasPre = !string.IsNullOrEmpty(preNewest);

                // Case 1: Current is prerelease and newest is stable release of same base -> upgrade available
                if (currentHasPre && !newestHasPre) return true;

                // Case 2: Current is stable and newest is prerelease of same base -> not an upgrade
                if (!currentHasPre && newestHasPre) return false;

                // Case 3: Both are prereleases of same base -> compare prerelease identifiers
                if (currentHasPre && newestHasPre)
                {
                    return ComparePrerelease(preCurrent!, preNewest!) < 0;
                }

                // Case 4: Both are stable releases and identical (e.g. 2.16.0 vs 2.16.0.0) -> not an upgrade
                return false;
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
        var v = version.Trim().TrimStart('v', 'V').Trim();
        var splitIndex = v.IndexOfAny(['-', '+']);
        if (splitIndex >= 0)
        {
            v = v[..splitIndex];
        }
        return v.Trim();
    }

    private static string? ExtractPrerelease(string version)
    {
        if (string.IsNullOrWhiteSpace(version)) return null;
        var v = version.Trim().TrimStart('v', 'V').Trim();
        var dashIndex = v.IndexOf('-');
        if (dashIndex < 0) return null;

        var pre = v[(dashIndex + 1)..];
        var plusIndex = pre.IndexOf('+');
        if (plusIndex >= 0)
        {
            pre = pre[..plusIndex];
        }
        return string.IsNullOrWhiteSpace(pre) ? null : pre.Trim();
    }

    private static int ComparePrerelease(string preA, string preB)
    {
        if (string.Equals(preA, preB, StringComparison.OrdinalIgnoreCase))
            return 0;

        var partsA = preA.Split('.');
        var partsB = preB.Split('.');
        int minLen = Math.Min(partsA.Length, partsB.Length);

        for (int i = 0; i < minLen; i++)
        {
            string a = partsA[i];
            string b = partsB[i];

            if (string.Equals(a, b, StringComparison.OrdinalIgnoreCase))
                continue;

            bool isNumA = long.TryParse(a, out long numA);
            bool isNumB = long.TryParse(b, out long numB);

            if (isNumA && isNumB)
            {
                int cmpNum = numA.CompareTo(numB);
                if (cmpNum != 0) return cmpNum;
                continue;
            }

            if (isNumA && !isNumB)
            {
                // SemVer 2.0 §11.4: Numeric identifiers have lower precedence than non-numeric identifiers
                return -1;
            }

            if (!isNumA && isNumB)
            {
                return 1;
            }

            int cmpStr = string.Compare(a, b, StringComparison.OrdinalIgnoreCase);
            if (cmpStr != 0) return cmpStr;
        }

        return partsA.Length.CompareTo(partsB.Length);
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
}