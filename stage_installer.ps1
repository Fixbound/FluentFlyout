$outDir = "E:\Programacion\FluentFlyout\InstallerOutput"
$systemFiles = Join-Path $outDir "SystemFiles"

if (Test-Path $outDir) { Remove-Item $outDir -Recurse -Force }
New-Item -ItemType Directory -Path $systemFiles -Force | Out-Null

# Copy MSIX
Copy-Item "E:\Programacion\FluentFlyout\FluentFlyout_2.16.0_x64.msix" -Destination (Join-Path $systemFiles "FluentFlyout_2.16.0.0_x64.msix")

# Export CER
$cert = Get-ChildItem -Path "Cert:\CurrentUser\My" | Where-Object { $_.Subject -like "*49793F74-1457-4B66-A672-4ED3A640FC76*" } | Select-Object -First 1
$cerPath = Join-Path $systemFiles "FluentFlyout_2.16.0.0_x64.cer"
[System.IO.File]::WriteAllBytes($cerPath, $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert))

# Copy Add-AppDevPackage.ps1 and resources from VS
$vsAppxDir = "C:\Program Files\Microsoft Visual Studio\2022\Community\Msbuild\Microsoft\VisualStudio\v17.0\AppxPackage"
Copy-Item (Join-Path $vsAppxDir "Add-AppDevPackage.ps1") -Destination $systemFiles -Force
Get-ChildItem -Path $vsAppxDir -Filter "Add-AppDevPackage.resources" -Directory | ForEach-Object {
    Copy-Item $_.FullName -Destination $systemFiles -Recurse -Force
}

# Copy installer bat and readme
Copy-Item "E:\Programacion\FluentFlyout\.github\build-files\FluentFlyout_Installer.bat" -Destination $outDir -Force
Copy-Item "E:\Programacion\FluentFlyout\.github\build-files\README.txt" -Destination $outDir -Force

Write-Output "Installer directory staged successfully at $outDir"
Get-ChildItem $systemFiles | Select-Object Name
