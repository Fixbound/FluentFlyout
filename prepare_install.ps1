$publishDir = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\publish"
$manifestSrc = "E:\Programacion\FluentFlyout\FluentFlyoutMSIX\Package.appxmanifest"
$imagesSrc = "E:\Programacion\FluentFlyout\FluentFlyoutMSIX\Images"

Copy-Item -Path $imagesSrc -Destination (Join-Path $publishDir "Images") -Recurse -Force

$manifestContent = Get-Content $manifestSrc -Raw
$manifestContent = $manifestContent.Replace('$targetnametoken$.exe', 'FluentFlyout.exe')
$manifestContent = $manifestContent.Replace('$targetentrypoint$', 'Windows.FullTrustApplication')

Set-Content -Path (Join-Path $publishDir "AppxManifest.xml") -Value $manifestContent -Encoding utf8
Write-Output "AppxManifest created successfully: $(Test-Path (Join-Path $publishDir 'AppxManifest.xml'))"
