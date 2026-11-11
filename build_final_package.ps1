$publishDir = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\publish"
$imagesDir = Join-Path $publishDir "Images"
$kitsBin = "C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64"
$makepri = Join-Path $kitsBin "makepri.exe"
$makeappx = Join-Path $kitsBin "makeappx.exe"
$signtool = Join-Path $kitsBin "signtool.exe"
$pfxPath = "E:\Programacion\FluentFlyout\dev_cert.pfx"
$pfxPassword = "FluentFlyoutDevPassword123!"

# 1. Create base unscaled image fallbacks
Copy-Item (Join-Path $imagesDir "SplashScreen.scale-200.png") (Join-Path $imagesDir "SplashScreen.png") -Force
Copy-Item (Join-Path $imagesDir "Square150x150Logo.scale-200.png") (Join-Path $imagesDir "Square150x150Logo.png") -Force
Copy-Item (Join-Path $imagesDir "FluentFlyout.scale-200.png") (Join-Path $imagesDir "FluentFlyout.png") -Force
Copy-Item (Join-Path $imagesDir "Wide310x150Logo.scale-200.png") (Join-Path $imagesDir "Wide310x150Logo.png") -Force
Copy-Item (Join-Path $imagesDir "SmallTile.scale-200.png") (Join-Path $imagesDir "SmallTile.png") -Force
Copy-Item (Join-Path $imagesDir "LargeTile.scale-200.png") (Join-Path $imagesDir "LargeTile.png") -Force
Copy-Item (Join-Path $imagesDir "StoreLogo.scale-200.png") (Join-Path $imagesDir "StoreLogo.png") -Force

Write-Host "Created base image copies successfully."

# 2. Generate resources.pri using makepri
$priconfig = "E:\Programacion\FluentFlyout\priconfig.xml"
& $makepri createconfig /cf $priconfig /dq en-US /o | Out-Null
& $makepri new /pr $publishDir /cf $priconfig /mn (Join-Path $publishDir "AppxManifest.xml") /of (Join-Path $publishDir "resources.pri") /o | Out-Null

Write-Host "Generated resources.pri: $(Test-Path (Join-Path $publishDir 'resources.pri'))"

# 3. Pack with makeappx
$msixDest = "E:\Programacion\FluentFlyout\InstallerOutput\SystemFiles\FluentFlyout_2.16.0.0_x64.msix"
& $makeappx pack /d $publishDir /p $msixDest /nv /o | Out-Null
Write-Host "Packed MSIX package."

# 4. Sign with signtool
& $signtool sign /fd SHA256 /a /f $pfxPath /p $pfxPassword $msixDest | Out-Null
Write-Host "Signed MSIX package."

# 5. Unblock files
Get-ChildItem -Path "E:\Programacion\FluentFlyout\InstallerOutput" -Recurse | Unblock-File
Write-Host "All files unblocked."
