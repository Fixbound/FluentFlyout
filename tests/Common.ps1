# Copyright (c) 2024-2026 The FluentFlyout Authors
# SPDX-License-Identifier: GPL-3.0-or-later

<#
.SYNOPSIS
    Common test infrastructure, assertion framework, and reflection helpers for FluentFlyout tests.
#>

$ErrorActionPreference = "Stop"

# Ensure execution in PowerShell 7+ (Core) for full .NET 10 runtime support
if ($PSVersionTable.PSVersion.Major -lt 7) {
    if (Get-Command pwsh -ErrorAction SilentlyContinue) {
        Write-Warning "Switching to pwsh (PowerShell 7+) for .NET 10 assembly compatibility..."
        & pwsh -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath @args
        exit $LASTEXITCODE
    } else {
        Write-Error "PowerShell 7+ (pwsh) is required to execute .NET 10 assembly test suites."
        exit 1
    }
}

if (-not (Get-Variable -Name TestResults -Scope Global -ErrorAction SilentlyContinue)) {
    $global:TestResults = [System.Collections.Generic.List[PSCustomObject]]::new()
}

function Reset-TestResults {
    $global:TestResults.Clear()
}

function Record-TestResult {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$true)][string]$Status,
        [string]$Expected = "",
        [string]$Actual = "",
        [string]$Details = ""
    )

    $record = [PSCustomObject]@{
        Tier     = $Tier
        Category = $Category
        Name     = $Name
        Status   = $Status
        Expected = $Expected
        Actual   = $Actual
        Details  = $Details
    }
    $global:TestResults.Add($record)

    $color = switch ($Status) {
        "PASS" { "Green" }
        "FAIL" { "Red" }
        default { "Yellow" }
    }
    Write-Host "[$Status] [$Tier] ($Category) $Name" -ForegroundColor $color
    if ($Status -eq "FAIL") {
        Write-Host "       Expected: '$Expected'" -ForegroundColor DarkRed
        Write-Host "       Actual:   '$Actual'" -ForegroundColor DarkRed
        if ($Details) {
            Write-Host "       Details:  $Details" -ForegroundColor DarkGray
        }
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)]$Actual,
        [Parameter(Mandatory=$false)]$Expected,
        [string]$Details = ""
    )
    $actStr = if ($null -eq $Actual) { "<null>" } else { $Actual.ToString() }
    $expStr = if ($null -eq $Expected) { "<null>" } else { $Expected.ToString() }

    $passed = ($actStr -eq $expStr)
    $status = if ($passed) { "PASS" } else { "FAIL" }
    Record-TestResult -Tier $Tier -Category $Category -Name $Name -Status $status -Expected $expStr -Actual $actStr -Details $Details
}

function Assert-True {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)]$Actual,
        [string]$Details = ""
    )
    $passed = ($Actual -eq $true)
    $status = if ($passed) { "PASS" } else { "FAIL" }
    $actStr = if ($null -eq $Actual) { "<null>" } else { $Actual.ToString() }
    Record-TestResult -Tier $Tier -Category $Category -Name $Name -Status $status -Expected "True" -Actual $actStr -Details $Details
}

function Assert-False {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)]$Actual,
        [string]$Details = ""
    )
    $passed = ($Actual -eq $false)
    $status = if ($passed) { "PASS" } else { "FAIL" }
    $actStr = if ($null -eq $Actual) { "<null>" } else { $Actual.ToString() }
    Record-TestResult -Tier $Tier -Category $Category -Name $Name -Status $status -Expected "False" -Actual $actStr -Details $Details
}

function Assert-Match {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Actual,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [string]$Details = ""
    )
    $passed = ($Actual -match $Pattern)
    $status = if ($passed) { "PASS" } else { "FAIL" }
    Record-TestResult -Tier $Tier -Category $Category -Name $Name -Status $status -Expected "Match '$Pattern'" -Actual $Actual -Details $Details
}

function Assert-NotMatch {
    param(
        [Parameter(Mandatory=$true)][string]$Tier,
        [Parameter(Mandatory=$true)][string]$Category,
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Actual,
        [Parameter(Mandatory=$true)][string]$Pattern,
        [string]$Details = ""
    )
    $passed = -not ($Actual -match $Pattern)
    $status = if ($passed) { "PASS" } else { "FAIL" }
    Record-TestResult -Tier $Tier -Category $Category -Name $Name -Status $status -Expected "Not match '$Pattern'" -Actual $Actual -Details $Details
}

function Initialize-FluentFlyoutAssembly {
    param(
        [string]$RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
    )

    $dllDir = Join-Path $RepoRoot "FluentFlyoutWPF\bin\x64\GitHub Release\net10.0-windows10.0.22000.0"
    $dllPath = Join-Path $dllDir "FluentFlyout.dll"

    if (-not (Test-Path -LiteralPath $dllPath)) {
        Write-Host "Target assembly not found at $dllPath. Compiling..." -ForegroundColor Yellow
        $buildProc = Start-Process dotnet -ArgumentList "build FluentFlyoutWPF/FluentFlyout.csproj -c `"GitHub Release`" -p:Platform=x64" -WorkingDirectory $RepoRoot -NoNewWindow -Wait -PassThru
        if ($buildProc.ExitCode -ne 0) {
            throw "Failed to compile FluentFlyoutWPF for testing. ExitCode: $($buildProc.ExitCode)"
        }
    }

    # Register assembly resolver for dependencies located in the output folder
    if (-not (Get-Variable -Name FF_ResolverRegistered -Scope Global -ErrorAction SilentlyContinue)) {
        [System.AppDomain]::CurrentDomain.add_AssemblyResolve({
            param($sender, $args)
            $name = ($args.Name -split ',')[0].Trim()
            $candidate = Join-Path $dllDir "$name.dll"
            if (Test-Path -LiteralPath $candidate) {
                return [System.Reflection.Assembly]::LoadFrom($candidate)
            }
            return $null
        })
        $global:FF_ResolverRegistered = $true
    }

    $asm = [System.Reflection.Assembly]::LoadFrom($dllPath)
    $UpdateCheckerType = $asm.GetType("FluentFlyoutWPF.Classes.Services.UpdateCheckerService")
    $UpdateInstallerType = $asm.GetType("FluentFlyoutWPF.Classes.Services.UpdateInstallerService")
    $LicenseManagerType = $asm.GetType("FluentFlyout.Classes.LicenseManager")

    if ($null -eq $UpdateCheckerType) {
        throw "Could not resolve type FluentFlyoutWPF.Classes.Services.UpdateCheckerService in $dllPath"
    }
    if ($null -eq $UpdateInstallerType) {
        throw "Could not resolve type FluentFlyoutWPF.Classes.Services.UpdateInstallerService in $dllPath"
    }

    return @{
        Assembly = $asm
        UpdateChecker = $UpdateCheckerType
        UpdateInstaller = $UpdateInstallerType
        LicenseManager = $LicenseManagerType
        DllPath = $dllPath
        RepoRoot = $RepoRoot
    }
}

function New-TestSandbox {
    $sandboxPath = Join-Path ([System.IO.Path]::GetTempPath()) "FF_Test_Sandbox_$([System.Guid]::NewGuid().ToString('N'))"
    New-Item -ItemType Directory -Path $sandboxPath -Force | Out-Null
    return $sandboxPath
}

function Remove-TestSandbox {
    param([string]$SandboxPath)
    if (-not [string]::IsNullOrWhiteSpace($SandboxPath) -and (Test-Path -LiteralPath $SandboxPath)) {
        Remove-Item -LiteralPath $SandboxPath -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-WithEnv {
    param(
        [Parameter(Mandatory=$true)][string]$Name,
        [Parameter(Mandatory=$false)][string]$Value,
        [Parameter(Mandatory=$true)][scriptblock]$ScriptBlock
    )
    $orig = [System.Environment]::GetEnvironmentVariable($Name)
    try {
        [System.Environment]::SetEnvironmentVariable($Name, $Value)
        & $ScriptBlock
    } finally {
        [System.Environment]::SetEnvironmentVariable($Name, $orig)
    }
}
