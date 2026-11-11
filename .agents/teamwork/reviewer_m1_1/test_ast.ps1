# Test script generation and AST parsing
$pidTest = 12345
$systemFilesDir = "C:\Users\santi\AppData\Local\Temp\FluentFlyout\updates\v2.16.0\1731234567\files\SystemFiles"
$escapedDir = $systemFilesDir.Replace("'", "''")

$scriptBody = @"
`$ErrorActionPreference = 'Stop'
`$logPath = Join-Path `$PSScriptRoot 'update_install.log'
Start-Transcript -Path `$logPath -Append -Force

try {
    Write-Output 'Waiting for FluentFlyout process (PID: $pidTest) to terminate...'
    try {
        Wait-Process -Id $pidTest -Timeout 30 -ErrorAction SilentlyContinue
    } catch {
        Write-Output 'Process already exited or not found.'
    }
    Start-Sleep -Seconds 1

    `$systemFiles = '$escapedDir'
    Write-Output "Changing directory to SystemFiles: `$systemFiles"
    Set-Location -LiteralPath `$systemFiles

    Write-Output 'Executing Add-AppDevPackage.ps1 -Force -SkipLoggingTelemetry...'
    & '.\Add-AppDevPackage.ps1' -Force -SkipLoggingTelemetry
    Write-Output 'Add-AppDevPackage.ps1 completed.'

    Write-Output 'Relaunching FluentFlyout application...'
    `$pkg = Get-AppxPackage '*FluentFlyout*' | Select-Object -First 1
    if (`$pkg) {
        `$exe1 = Join-Path `$pkg.InstallLocation 'FluentFlyout\FluentFlyout.exe'
        `$exe2 = Join-Path `$pkg.InstallLocation 'FluentFlyout.exe'
        if (Test-Path `$exe1) {
            Start-Process -FilePath `$exe1
            Write-Output "Started `$exe1"
        } elseif (Test-Path `$exe2) {
            Start-Process -FilePath `$exe2
            Write-Output "Started `$exe2"
        } else {
            explorer.exe "shell:AppsFolder\`$(`$pkg.PackageFamilyName)!App"
            Write-Output 'Started via AppsFolder'
        }
    } else {
        Write-Warning 'Could not find installed FluentFlyout package to relaunch.'
    }
} catch {
    Write-Error "Update installation failed: `$_"
} finally {
    Stop-Transcript -ErrorAction SilentlyContinue
}
"@

$tokens = $null
$errors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseInput($scriptBody, [ref]$tokens, [ref]$errors)

if ($errors.Count -eq 0) {
    Write-Output "AST check: SUCCESS (0 errors)"
} else {
    Write-Output "AST check: FAILED with $($errors.Count) errors:"
    $errors | ForEach-Object { Write-Output $_.Message }
}
