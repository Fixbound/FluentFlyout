// Copyright (c) 2024-2026 The FluentFlyout Authors
// SPDX-License-Identifier: GPL-3.0-or-later

using CommunityToolkit.Mvvm.ComponentModel;

namespace FluentFlyoutWPF.ViewModels;

/// <summary>
/// Runtime state for update checking (not persisted)
/// </summary>
public partial class UpdateState : ObservableObject
{
    public static UpdateState Current { get; } = new();

    /// <summary>
    /// Whether an update is available
    /// </summary>
    [ObservableProperty]
    public partial bool IsUpdateAvailable { get; set; }

    /// <summary>
    /// The newest version available from the API
    /// </summary>
    [ObservableProperty]
    public partial string NewestVersion { get; set; } = string.Empty;

    /// <summary>
    /// The URL to download the update (if available)
    /// </summary>
    [ObservableProperty]
    public partial string UpdateUrl { get; set; } = string.Empty;

    /// <summary>
    /// Direct download URL of the installer asset of the newest GitHub release (when resolvable)
    /// </summary>
    [ObservableProperty]
    public partial string AssetUrl { get; set; } = string.Empty;

    /// <summary>
    /// Expected SHA-256 digest of the installer asset, taken from the GitHub release notes (when present)
    /// </summary>
    [ObservableProperty]
    public partial string ExpectedSha256 { get; set; } = string.Empty;

    /// <summary>
    /// Timestamp of the last update check
    /// </summary>
    [ObservableProperty]
    [NotifyPropertyChangedFor(nameof(LastCheckedText))]
    public partial DateTime LastUpdateCheck { get; set; }

    /// <summary>
    /// Formatted text for the last update check time
    /// </summary>
    public string LastCheckedText => LastUpdateCheck == default
        ? string.Empty
        : LastUpdateCheck.ToString("G");
}