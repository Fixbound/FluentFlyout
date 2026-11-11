$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ([System.Guid]::NewGuid().ToString())
New-Item -ItemType Directory -Path $tempRoot | Out-Null

try {
    $workspace = Join-Path $tempRoot "workspace"
    $appxPackages = Join-Path $workspace "AppxPackages\FluentFlyoutMSIX_2.16.0.0_Test"
    New-Item -ItemType Directory -Path $appxPackages -Force | Out-Null
    Set-Content -Path (Join-Path $appxPackages "Add-AppDevPackage.ps1") -Value "# Script"
    Set-Content -Path (Join-Path $appxPackages "FluentFlyout.cer") -Value "CERTDATA"
    $depDir = Join-Path $appxPackages "Dependencies\x64"
    New-Item -ItemType Directory -Path $depDir -Force | Out-Null
    Set-Content -Path (Join-Path $depDir "dep.msix") -Value "DEP"

    $buildFilesDir = Join-Path $workspace ".github\build-files"
    New-Item -ItemType Directory -Path $buildFilesDir -Force | Out-Null
    Set-Content -Path (Join-Path $buildFilesDir "FluentFlyout_Installer.bat") -Value "@echo off"
    Set-Content -Path (Join-Path $buildFilesDir "README.txt") -Value "Readme"

    # Now execute the staging logic
    $outDir = Join-Path $workspace "InstallerOutput"
    $systemFilesDir = Join-Path $outDir "SystemFiles"
    New-Item -ItemType Directory -Path $systemFilesDir -Force | Out-Null

    $testFolder = Get-ChildItem (Join-Path $workspace "AppxPackages") -Directory -Recurse |
        Where-Object { $_.Name -like '*_Test' } | Select-Object -First 1

    if (-not $testFolder) {
        throw "No *_Test folder found!"
    }

    Copy-Item -Path "$($testFolder.FullName)\*" -Destination $systemFilesDir -Recurse -Force
    Copy-Item (Join-Path $buildFilesDir "FluentFlyout_Installer.bat") "$outDir\"
    Copy-Item (Join-Path $buildFilesDir "README.txt") "$outDir\"

    # Verify staged files
    $expectedFiles = @(
        (Join-Path $outDir "FluentFlyout_Installer.bat"),
        (Join-Path $outDir "README.txt"),
        (Join-Path $systemFilesDir "Add-AppDevPackage.ps1"),
        (Join-Path $systemFilesDir "FluentFlyout.cer"),
        (Join-Path $systemFilesDir "Dependencies\x64\dep.msix")
    )

    foreach ($file in $expectedFiles) {
        if (-not (Test-Path $file)) {
            throw "Missing staged file: $file"
        }
    }

    Write-Host "Staging logic verified successfully!"
}
finally {
    Remove-Item $tempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
