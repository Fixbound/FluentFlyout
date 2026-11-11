$dllPath = "E:\Programacion\FluentFlyout\FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0\FluentFlyout.dll"
$asm = [System.Reflection.Assembly]::LoadFrom($dllPath)
$type = $asm.GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService")
$methods = $type.GetMethods() | Where-Object { $_.Name -eq "ParseInstallerAsset" }

$jsonString = @"
{
  "tag_name": "v2.16.0",
  "body": "Some description\r\n\r\nGitHub Release x64 installer: FluentFlyout_2.16.0_x64_Installer.zip\r\nGitHub Release x64 checksum: 0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
  "assets": [
    {
      "name": "FluentFlyout_2.16.0_x64_Installer.zip",
      "browser_download_url": "https://github.com/unchihugo/FluentFlyout/releases/download/v2.16.0/FluentFlyout_2.16.0_x64_Installer.zip"
    }
  ]
}
"@

$doc = [System.Text.Json.JsonDocument]::Parse($jsonString)
$argsArr = [object[]]@($doc)
$result = $methods[0].Invoke($null, $argsArr)
Write-Host "AssetUrl: $($result.Item1)"
Write-Host "ExpectedSha256: $($result.Item2)"
Write-Host "Sha match: $($result.Item2 -eq '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef')"
