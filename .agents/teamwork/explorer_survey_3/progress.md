# Progress — explorer_survey_3

Last visited: 2026-11-10T19:40:00Z

## Current Status
- Investigated `.github/workflows/build-msix.yml`, `dotnet-format.yml`, `notify-website.yml`.
- Investigated `FluentFlyoutMSIX.wapproj`, `Package.appxmanifest`, `FluentFlyout.csproj`, `FluentFlyout.sln`.
- Verified `dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64` succeeds locally with 0 errors and 0 warnings.
- Identified critical discrepancy between MSBuild 17 (VS 2022) and MSBuild 18+ (.NET 10 SDK) when building `.wapproj`.
- Identified multiple critical issues in `build-msix.yml`:
  1. Missing `actions/setup-dotnet` step for .NET 10 SDK.
  2. Certificate decoding step fails with exception if `MSIX_CERT_BASE64` is missing/empty (fork incompatibility).
  3. Certificate decoded is never passed to MSBuild; MSBuild is passed `AppxPackageSigningEnabled=false`, producing unsigned MSIX packages that fail Windows installation and fail `Add-AppDevPackage.ps1` due to missing `.cer`.
  4. Inappropriate `UapAppxPackageBuildMode=StoreUpload` instead of `SideloadOnly` for GitHub Release.
  5. Fragile `Move-Item` logic assuming non-null `*_Test` directory without validation.
  6. Lack of tag triggers (`tags: ['v*']`), preventing releases from being triggered via git tags.
  7. Destructive release editing that overwrites full release notes instead of updating or preserving them.
  8. Missing companion `.sha256` asset upload.
- Next: Prepare comprehensive `analysis.md` and `handoff.md`.
