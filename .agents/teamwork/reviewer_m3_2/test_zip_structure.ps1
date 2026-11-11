$testDir = Join-Path ([System.IO.Path]::GetTempPath()) "TestZipLayout"
Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $testDir 'InstallerOutput\SystemFiles') -Force | Out-Null
Set-Content -Path (Join-Path $testDir 'InstallerOutput\SystemFiles\Add-AppDevPackage.ps1') -Value '# test ps1'
Set-Content -Path (Join-Path $testDir 'InstallerOutput\FluentFlyout_Installer.bat') -Value 'bat'
Set-Content -Path (Join-Path $testDir 'InstallerOutput\README.txt') -Value 'readme'

$zipPath = Join-Path $testDir 'test.zip'
Compress-Archive -Path (Join-Path $testDir 'InstallerOutput\*') -DestinationPath $zipPath

$unzipDir = Join-Path $testDir 'unzipped\files'
[System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $unzipDir)

$file1 = Join-Path $unzipDir 'SystemFiles\Add-AppDevPackage.ps1'
$file2 = Join-Path $unzipDir 'FluentFlyout_Installer.bat'
$file3 = Join-Path $unzipDir 'README.txt'

Write-Host "Add-AppDevPackage.ps1 exists: $(Test-Path $file1)"
Write-Host "FluentFlyout_Installer.bat exists: $(Test-Path $file2)"
Write-Host "README.txt exists: $(Test-Path $file3)"

Remove-Item $testDir -Recurse -Force -ErrorAction SilentlyContinue
