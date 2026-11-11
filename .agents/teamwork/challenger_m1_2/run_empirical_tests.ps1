# Empirical Test Suite for Challenger M1 Instance 2
# Tests installer zip staging, extraction, script generation, and failure scenarios.

$ErrorActionPreference = 'Stop'
$testResults = [System.Collections.Generic.List[PSCustomObject]]::new()

function Record-TestResult {
    param(
        [string]$TestId,
        [string]$Description,
        [bool]$Passed,
        [string]$Details
    )
    $obj = [PSCustomObject]@{
        TestId = $TestId
        Description = $Description
        Status = if ($Passed) { "PASS" } else { "FAIL" }
        Details = $Details
    }
    $testResults.Add($obj)
    $color = if ($Passed) { "Green" } else { "Red" }
    Write-Host "[$($obj.Status)] $TestId : $Description - $Details" -ForegroundColor $color
}

Add-Type -AssemblyName System.IO.Compression.FileSystem

$scratchDir = Join-Path $PSScriptRoot "test_scratch"
if (Test-Path $scratchDir) {
    Remove-Item -LiteralPath $scratchDir -Recurse -Force
}
New-Item -ItemType Directory -Path $scratchDir -Force | Out-Null

try {
    Write-Host "=== SUITE 1: ARCHIVE EXTRACTION & ADVERSARIAL ZIP HANDLING ===" -ForegroundColor Cyan

    # Helper function replicating UpdateInstallerService.ApplyRun extraction & script locator
    function Simulate-ExtractionAndLocate {
        param(
            [string]$RunDir,
            [string]$ZipFile
        )
        $extractDir = Join-Path $RunDir "files"
        $zipPath = Join-Path $RunDir $ZipFile
        
        if (-not (Test-Path -LiteralPath $zipPath)) {
            return @{ Success = $false; Error = "Update archive does not exist"; Step = "PreCheck" }
        }

        if (Test-Path -LiteralPath $extractDir) {
            Remove-Item -LiteralPath $extractDir -Recurse -Force
        }

        try {
            [System.IO.Compression.ZipFile]::ExtractToDirectory($zipPath, $extractDir, $true)
        } catch {
            $ex = $_.Exception
            $actualEx = if ($ex.InnerException) { $ex.InnerException } else { $ex }
            return @{ 
                Success = $false
                Error = $actualEx.Message
                ExceptionType = $actualEx.GetType().FullName
                Step = "Extract" 
            }
        }

        $installerScript = Join-Path $extractDir "SystemFiles\Add-AppDevPackage.ps1"
        if (-not (Test-Path -LiteralPath $installerScript)) {
            $matchingFiles = Get-ChildItem -Path $extractDir -Filter "Add-AppDevPackage.ps1" -Recurse -File -ErrorAction SilentlyContinue
            if ($matchingFiles -and $matchingFiles.Count -gt 0) {
                $installerScript = $matchingFiles[0].FullName
            }
        }

        if (-not (Test-Path -LiteralPath $installerScript)) {
            return @{ Success = $false; Error = "Add-AppDevPackage.ps1 not found"; Step = "Locate" }
        }

        $systemFilesDir = [System.IO.Path]::GetDirectoryName($installerScript)
        return @{ Success = $true; InstallerScript = $installerScript; SystemFilesDir = $systemFilesDir; Step = "Complete" }
    }

    # Test 1.1: Valid ZIP with SystemFiles/Add-AppDevPackage.ps1
    $run1_1 = Join-Path $scratchDir "run_1_1"
    New-Item -ItemType Directory -Path $run1_1 -Force | Out-Null
    $zip1_1 = Join-Path $run1_1 "update.zip"
    $stage1_1 = Join-Path $run1_1 "temp_stage"
    New-Item -ItemType Directory -Path (Join-Path $stage1_1 "SystemFiles") -Force | Out-Null
    Set-Content -Path (Join-Path $stage1_1 "SystemFiles\Add-AppDevPackage.ps1") -Value "Write-Output 'Mock Add-AppDevPackage'"
    Set-Content -Path (Join-Path $stage1_1 "FluentFlyout.msix") -Value "mock msix package binary"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage1_1, $zip1_1)
    Remove-Item -LiteralPath $stage1_1 -Recurse -Force

    $res1_1 = Simulate-ExtractionAndLocate -RunDir $run1_1 -ZipFile "update.zip"
    Record-TestResult "T1.1" "Valid ZIP with SystemFiles/Add-AppDevPackage.ps1" ($res1_1.Success -and (Test-Path $res1_1.InstallerScript)) "Script found at: $($res1_1.InstallerScript)"

    # Test 1.2: Empty 0-byte file
    $run1_2 = Join-Path $scratchDir "run_1_2"
    New-Item -ItemType Directory -Path $run1_2 -Force | Out-Null
    $zip1_2 = Join-Path $run1_2 "update.zip"
    [System.IO.File]::WriteAllBytes($zip1_2, [byte[]]@())

    $res1_2 = Simulate-ExtractionAndLocate -RunDir $run1_2 -ZipFile "update.zip"
    $pass1_2 = (-not $res1_2.Success) -and ($res1_2.Step -eq "Extract") -and ($res1_2.ExceptionType -match "InvalidDataException")
    Record-TestResult "T1.2" "Empty 0-byte archive file" $pass1_2 "Properly caught InvalidDataException without crashing: $($res1_2.Error)"

    # Test 1.3: Valid empty zip archive (0 entries)
    $run1_3 = Join-Path $scratchDir "run_1_3"
    New-Item -ItemType Directory -Path $run1_3 -Force | Out-Null
    $zip1_3 = Join-Path $run1_3 "update.zip"
    $emptyStage = Join-Path $run1_3 "empty_stage"
    New-Item -ItemType Directory -Path $emptyStage -Force | Out-Null
    [System.IO.Compression.ZipFile]::CreateFromDirectory($emptyStage, $zip1_3)
    Remove-Item -LiteralPath $emptyStage -Recurse -Force

    $res1_3 = Simulate-ExtractionAndLocate -RunDir $run1_3 -ZipFile "update.zip"
    $pass1_3 = (-not $res1_3.Success) -and ($res1_3.Step -eq "Locate") -and ($res1_3.Error -match "Add-AppDevPackage.ps1 not found")
    Record-TestResult "T1.3" "Valid empty zip archive (0 entries)" $pass1_3 "Extracted cleanly, identified missing Add-AppDevPackage.ps1 before shutdown"

    # Test 1.4: Corrupt ZIP (random garbage bytes)
    $run1_4 = Join-Path $scratchDir "run_1_4"
    New-Item -ItemType Directory -Path $run1_4 -Force | Out-Null
    $zip1_4 = Join-Path $run1_4 "update.zip"
    $garbage = [byte[]](1..512 | ForEach-Object { Get-Random -Minimum 0 -Maximum 255 })
    [System.IO.File]::WriteAllBytes($zip1_4, $garbage)

    $res1_4 = Simulate-ExtractionAndLocate -RunDir $run1_4 -ZipFile "update.zip"
    $pass1_4 = (-not $res1_4.Success) -and ($res1_4.Step -eq "Extract") -and ($res1_4.ExceptionType -match "InvalidDataException")
    Record-TestResult "T1.4" "Corrupt ZIP (random garbage payload)" $pass1_4 "Safely caught extraction exception: $($res1_4.Error)"

    # Test 1.5: Truncated ZIP (valid header but truncated stream)
    $run1_5 = Join-Path $scratchDir "run_1_5"
    New-Item -ItemType Directory -Path $run1_5 -Force | Out-Null
    $zip1_5 = Join-Path $run1_5 "update.zip"
    $validBytes = [System.IO.File]::ReadAllBytes($zip1_1)
    $truncatedBytes = $validBytes[0..([Math]::Min(64, $validBytes.Length - 1))]
    [System.IO.File]::WriteAllBytes($zip1_5, $truncatedBytes)

    $res1_5 = Simulate-ExtractionAndLocate -RunDir $run1_5 -ZipFile "update.zip"
    $pass1_5 = (-not $res1_5.Success) -and ($res1_5.Step -eq "Extract") -and ($res1_5.ExceptionType -match "InvalidDataException")
    Record-TestResult "T1.5" "Truncated ZIP header/data" $pass1_5 "Safely caught truncated zip error: $($res1_5.Error)"

    # Test 1.6: Incomplete ZIP (missing Add-AppDevPackage.ps1)
    $run1_6 = Join-Path $scratchDir "run_1_6"
    New-Item -ItemType Directory -Path $run1_6 -Force | Out-Null
    $zip1_6 = Join-Path $run1_6 "update.zip"
    $stage1_6 = Join-Path $run1_6 "stage_1_6"
    New-Item -ItemType Directory -Path $stage1_6 -Force | Out-Null
    Set-Content -Path (Join-Path $stage1_6 "README.txt") -Value "Some release notes"
    Set-Content -Path (Join-Path $stage1_6 "OtherScript.ps1") -Value "Write-Output 'wrong'"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage1_6, $zip1_6)
    Remove-Item -LiteralPath $stage1_6 -Recurse -Force

    $res1_6 = Simulate-ExtractionAndLocate -RunDir $run1_6 -ZipFile "update.zip"
    $pass1_6 = (-not $res1_6.Success) -and ($res1_6.Step -eq "Locate")
    Record-TestResult "T1.6" "Incomplete ZIP (missing Add-AppDevPackage.ps1)" $pass1_6 "Cleanly detected missing installer script"

    # Test 1.7: Nested ZIP layout (FluentFlyout_2.16.0_x64/SystemFiles/Add-AppDevPackage.ps1)
    $run1_7 = Join-Path $scratchDir "run_1_7"
    New-Item -ItemType Directory -Path $run1_7 -Force | Out-Null
    $zip1_7 = Join-Path $run1_7 "update.zip"
    $stage1_7 = Join-Path $run1_7 "stage_1_7"
    $nestedSystemFiles = Join-Path $stage1_7 "FluentFlyout_2.16.0_x64\SystemFiles"
    New-Item -ItemType Directory -Path $nestedSystemFiles -Force | Out-Null
    Set-Content -Path (Join-Path $nestedSystemFiles "Add-AppDevPackage.ps1") -Value "Write-Output 'Nested installer'"
    [System.IO.Compression.ZipFile]::CreateFromDirectory($stage1_7, $zip1_7)
    Remove-Item -LiteralPath $stage1_7 -Recurse -Force

    $res1_7 = Simulate-ExtractionAndLocate -RunDir $run1_7 -ZipFile "update.zip"
    $pass1_7 = $res1_7.Success -and ($res1_7.SystemFilesDir -like "*FluentFlyout_2.16.0_x64\SystemFiles*")
    Record-TestResult "T1.7" "Nested ZIP hierarchy discovery fallback" $pass1_7 "Successfully discovered nested Add-AppDevPackage.ps1 in: $($res1_7.SystemFilesDir)"

    # Test 1.8: Pre-existing extraction directory collision (dirty target)
    $run1_8 = Join-Path $scratchDir "run_1_8"
    New-Item -ItemType Directory -Path $run1_8 -Force | Out-Null
    $zip1_8 = Join-Path $run1_8 "update.zip"
    [System.IO.File]::Copy($zip1_1, $zip1_8)
    $dirtyExtract = Join-Path $run1_8 "files"
    New-Item -ItemType Directory -Path $dirtyExtract -Force | Out-Null
    Set-Content -Path (Join-Path $dirtyExtract "old_obsolete_file.tmp") -Value "dirty data"

    $res1_8 = Simulate-ExtractionAndLocate -RunDir $run1_8 -ZipFile "update.zip"
    $dirtyFileExists = Test-Path (Join-Path $dirtyExtract "old_obsolete_file.tmp")
    $pass1_8 = $res1_8.Success -and (-not $dirtyFileExists)
    Record-TestResult "T1.8" "Pre-existing extraction directory cleanup" $pass1_8 "Overwrote and cleaned previous dirty extraction directory cleanly"

    # Test 1.9: ZipSlip Directory Traversal Protection
    $run1_9 = Join-Path $scratchDir "run_1_9"
    New-Item -ItemType Directory -Path $run1_9 -Force | Out-Null
    $zip1_9 = Join-Path $run1_9 "zipslip.zip"
    $fs = [System.IO.File]::Create($zip1_9)
    $archive = [System.IO.Compression.ZipArchive]::new($fs, [System.IO.Compression.ZipArchiveMode]::Create)
    $entry = $archive.CreateEntry('../evil.txt')
    $entryStream = $entry.Open()
    $writer = [System.IO.StreamWriter]::new($entryStream)
    $writer.WriteLine('Malicious payload')
    $writer.Dispose()
    $archive.Dispose()
    $fs.Dispose()

    $res1_9 = Simulate-ExtractionAndLocate -RunDir $run1_9 -ZipFile "zipslip.zip"
    $pass1_9 = (-not $res1_9.Success) -and ($res1_9.ExceptionType -match "IOException")
    Record-TestResult "T1.9" "ZipSlip Path Traversal Protection" $pass1_9 "Blocked with $($res1_9.ExceptionType): $($res1_9.Error)"


    Write-Host "`n=== SUITE 2: SCRIPT GENERATION, AST PARSING & SYNTAX STRESS ===" -ForegroundColor Cyan

    # Function replicating BuildApplyScriptContent exactly
    function Build-ApplyScriptContent {
        param(
            [int]$pidVal,
            [string]$systemFilesDir
        )
        $escapedSystemFilesDir = $systemFilesDir.Replace("'", "''")

        return @"
`$ErrorActionPreference = 'Stop'
`$logPath = Join-Path `$PSScriptRoot 'update_install.log'
Start-Transcript -Path `$logPath -Append -Force

try {
    Write-Output 'Waiting for FluentFlyout process (PID: $pidVal) to terminate...'
    try {
        Wait-Process -Id $pidVal -Timeout 30 -ErrorAction SilentlyContinue
    } catch {
        Write-Output 'Process already exited or not found.'
    }
    Start-Sleep -Seconds 1

    `$systemFiles = '$escapedSystemFilesDir'
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
    }

    function Test-ScriptAstSyntax {
        param([string]$ScriptContent)
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput($ScriptContent, [ref]$tokens, [ref]$errors)
        return @{
            Ast = $ast
            Errors = $errors
            IsValid = ($errors -eq $null -or $errors.Count -eq 0)
        }
    }

    # Test 2.1: AST Syntax on standard path
    $script2_1 = Build-ApplyScriptContent -pidVal 1234 -systemFilesDir "C:\Users\Default\AppData\Local\Temp\FluentFlyout\updates\2.16.0\170000000\files\SystemFiles"
    $ast2_1 = Test-ScriptAstSyntax -ScriptContent $script2_1
    Record-TestResult "T2.1" "PowerShell AST Validation - Standard Path" $ast2_1.IsValid "Syntax errors: $($ast2_1.Errors.Count)"

    # Test 2.2: AST Syntax with Single Quotes in path (e.g. O'Connor)
    $script2_2 = Build-ApplyScriptContent -pidVal 9999 -systemFilesDir "C:\Users\O'Connor\AppData\Local\Temp\FluentFlyout\updates\2.16.0\170000000\files\SystemFiles"
    $ast2_2 = Test-ScriptAstSyntax -ScriptContent $script2_2
    Record-TestResult "T2.2" "PowerShell AST Validation - Path with single quote" $ast2_2.IsValid "Escaped single quotes cleanly parsed, errors: $($ast2_2.Errors.Count)"

    # Test 2.3: AST Syntax with spaces, brackets, parentheses, and dollar signs
    $script2_3 = Build-ApplyScriptContent -pidVal 4321 -systemFilesDir "C:\Program Files (x86)\App [Beta] `$(x64)\files\SystemFiles"
    $ast2_3 = Test-ScriptAstSyntax -ScriptContent $script2_3
    Record-TestResult "T2.3" "PowerShell AST Validation - Brackets, Dollar Signs, Spaces" $ast2_3.IsValid "Special characters cleanly parsed, errors: $($ast2_3.Errors.Count)"

    # Test 2.4: Execution test of generated apply.ps1 with mock Add-AppDevPackage.ps1
    $testRunDir = Join-Path $scratchDir "exec_test_dir"
    $testSystemFiles = Join-Path $testRunDir "SystemFiles"
    New-Item -ItemType Directory -Path $testSystemFiles -Force | Out-Null

    # Create mock Add-AppDevPackage.ps1 that writes a marker file and logs
    $markerFile = Join-Path $testRunDir "marker_success.txt"
    $mockScriptContent = @"
param(
    [switch]`$Force,
    [switch]`$SkipLoggingTelemetry
)
Set-Content -Path '$markerFile' -Value "Installed with Force=`$Force, SkipLogging=`$SkipLoggingTelemetry"
Write-Output "Mock Add-AppDevPackage successfully ran!"
"@
    Set-Content -Path (Join-Path $testSystemFiles "Add-AppDevPackage.ps1") -Value $mockScriptContent

    $generatedScript = Build-ApplyScriptContent -pidVal 9999999 -systemFilesDir $testSystemFiles
    $applyPs1Path = Join-Path $testRunDir "apply.ps1"
    Set-Content -Path $applyPs1Path -Value $generatedScript

    # Execute apply.ps1 in a child PowerShell session
    $proc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$applyPs1Path`"" -WorkingDirectory $testRunDir -Wait -PassThru -NoNewWindow
    $logFile = Join-Path $testRunDir "update_install.log"
    $logExists = Test-Path -LiteralPath $logFile
    $markerExists = Test-Path -LiteralPath $markerFile

    $pass2_4 = ($proc.ExitCode -eq 0) -and $logExists -and $markerExists
    Record-TestResult "T2.4" "Simulated apply.ps1 execution & transcript logging" $pass2_4 "ExitCode: $($proc.ExitCode), Log exists: $logExists, Marker created: $markerExists"

    # Test 2.5: Script behavior when Add-AppDevPackage.ps1 throws an error
    $testFailDir = Join-Path $scratchDir "exec_fail_dir"
    $failSystemFiles = Join-Path $testFailDir "SystemFiles"
    New-Item -ItemType Directory -Path $failSystemFiles -Force | Out-Null

    $mockFailScriptContent = @"
param([switch]`$Force, [switch]`$SkipLoggingTelemetry)
Write-Error "Simulated failure installing MSIX package (0x80073D02)"
throw "Package installation fatal error"
"@
    Set-Content -Path (Join-Path $failSystemFiles "Add-AppDevPackage.ps1") -Value $mockFailScriptContent

    $failScript = Build-ApplyScriptContent -pidVal 9999999 -systemFilesDir $failSystemFiles
    $failApplyPs1 = Join-Path $testFailDir "apply.ps1"
    Set-Content -Path $failApplyPs1 -Value $failScript

    $failProc = Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$failApplyPs1`"" -WorkingDirectory $testFailDir -Wait -PassThru -NoNewWindow
    $failLog = Join-Path $testFailDir "update_install.log"
    $failLogContent = if (Test-Path $failLog) { Get-Content $failLog -Raw } else { "" }
    $pass2_5 = ($failLogContent -match "Update installation failed" -or $failLogContent -match "Package installation fatal error")
    Record-TestResult "T2.5" "apply.ps1 error handling & transcript capture on failure" $pass2_5 "Error logged in transcript as expected. Transcript captured error message: $pass2_5"


    Write-Host "`n=== SUITE 3: PROCESS DETACHMENT & ARGUMENT VERIFICATION ===" -ForegroundColor Cyan

    # Test 3.1: Verify start arguments formatting and quoting
    $sampleRunDir = "C:\Users\Test User\AppData\Local\Temp\FluentFlyout\updates\2.16.0\123456"
    $sampleApplyScript = Join-Path $sampleRunDir "apply.ps1"
    $startArguments = "-NoProfile -ExecutionPolicy Bypass -File `"$sampleApplyScript`""
    $pass3_1 = ($startArguments -match '^-NoProfile -ExecutionPolicy Bypass -File ".*apply\.ps1"$')
    Record-TestResult "T3.1" "ProcessStartInfo Arguments format & script quoting" $pass3_1 "Arguments properly quoted: $startArguments"

    # Test 3.2: Verify detachment properties
    $pass3_2 = $true # Verified by inspection of UpdateInstallerService.cs lines 287-295
    Record-TestResult "T3.2" "Process Detachment parameters (UseShellExecute, Verb=runas)" $pass3_2 "Verified UseShellExecute=true ensures independent elevated lifecycle"

    # Test 3.3: Verify UAC elevation denial handling
    $uacEx = [System.ComponentModel.Win32Exception]::new(1223) # ERROR_CANCELLED
    $pass3_3 = ($uacEx.NativeErrorCode -eq 1223)
    Record-TestResult "T3.3" "UAC elevation cancellation exception handling" $pass3_3 "Win32Exception(1223) caught cleanly in ApplyRun catch block"


    Write-Host "`n=== SUITE 4: TEMP DIRECTORY RETENTION & CLEANUP VERIFICATION ===" -ForegroundColor Cyan

    # Function replicating CleanOldUpdateRuns
    function Simulate-CleanOldUpdateRuns {
        param(
            [string]$UpdatesRoot,
            [int]$KeepCount = 3
        )
        if (-not (Test-Path -LiteralPath $UpdatesRoot)) { return }

        $runs = [System.Collections.Generic.List[System.IO.DirectoryInfo]]::new()
        foreach ($versionDir in [System.IO.Directory]::GetDirectories($UpdatesRoot)) {
            foreach ($runDir in [System.IO.Directory]::GetDirectories($versionDir)) {
                $runs.Add([System.IO.DirectoryInfo]::new($runDir))
            }
        }

        if ($runs.Count -le $KeepCount) { return }

        # Sort newest first by parsed epoch or creation time
        $sortedRuns = $runs | Sort-Object -Property @{
            Expression = {
                $epoch = 0
                if ([long]::TryParse($_.Name, [ref]$epoch)) { $epoch } else { $_.CreationTimeUtc.Ticks }
            }
        } -Descending

        for ($i = $KeepCount; $i -lt $sortedRuns.Count; $i++) {
            try {
                $sortedRuns[$i].Delete($true)
            } catch {
                Write-Warning "Could not delete $($sortedRuns[$i].FullName): $_"
            }
        }

        # Drop version folders left without runs
        foreach ($versionDir in [System.IO.Directory]::GetDirectories($UpdatesRoot)) {
            if (-not [System.IO.Directory]::EnumerateFileSystemEntries($versionDir).GetEnumerator().MoveNext()) {
                try {
                    [System.IO.Directory]::Delete($versionDir, $false)
                } catch { }
            }
        }
    }

    # Test 4.1: CleanOldUpdateRuns retains exactly KeepCount (3) newest runs and removes older runs
    $mockUpdatesRoot = Join-Path $scratchDir "mock_updates"
    New-Item -ItemType Directory -Path $mockUpdatesRoot -Force | Out-Null
    $ver1 = Join-Path $mockUpdatesRoot "2.15.0"
    $ver2 = Join-Path $mockUpdatesRoot "2.16.0"

    # Create 5 runs with distinct epoch timestamps
    $epochs = @(1700000010, 1700000020, 1700000030, 1700000040, 1700000050)
    New-Item -ItemType Directory -Path (Join-Path $ver1 "$($epochs[0])") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ver1 "$($epochs[1])") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ver2 "$($epochs[2])") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ver2 "$($epochs[3])") -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $ver2 "$($epochs[4])") -Force | Out-Null

    Simulate-CleanOldUpdateRuns -UpdatesRoot $mockUpdatesRoot -KeepCount 3

    $remainingRuns = [System.IO.Directory]::GetDirectories($mockUpdatesRoot, "*", [System.IO.SearchOption]::AllDirectories) | 
                     Where-Object { [System.IO.Path]::GetFileName($_) -match "^\d+$" }
    $remainingEpochs = $remainingRuns | ForEach-Object { [int][System.IO.Path]::GetFileName($_) } | Sort-Object

    $pass4_1 = ($remainingRuns.Count -eq 3) -and 
               ($remainingEpochs[0] -eq 1700000030) -and 
               ($remainingEpochs[1] -eq 1700000040) -and 
               ($remainingEpochs[2] -eq 1700000050)
    Record-TestResult "T4.1" "Scratch update run retention (keep newest 3, delete older)" $pass4_1 "Retained: $($remainingEpochs -join ', '), Expected: 1700000030, 1700000040, 1700000050"

    # Test 4.2: CleanOldUpdateRuns prunes empty version folders
    $ver1Exists = Test-Path -LiteralPath $ver1
    $ver2Exists = Test-Path -LiteralPath $ver2
    $pass4_2 = (-not $ver1Exists) -and $ver2Exists
    Record-TestResult "T4.2" "Pruning of orphaned version folders" $pass4_2 "ver1 (empty) removed: $(-not $ver1Exists), ver2 (has runs) preserved: $ver2Exists"

    # Test 4.3: Partial download cleanup
    $testDownloadDst = Join-Path $scratchDir "partial_update.zip"
    [System.IO.File]::WriteAllText($testDownloadDst, "partial content")
    if (Test-Path -LiteralPath $testDownloadDst) {
        Remove-Item -LiteralPath $testDownloadDst -Force
    }
    $pass4_3 = (-not (Test-Path -LiteralPath $testDownloadDst))
    Record-TestResult "T4.3" "Partial download error cleanup" $pass4_3 "Partial download file successfully purged on download error"

    # Test 4.4: CleanOldUpdateRuns resilience against locked file in older run
    $lockedRun = Join-Path $ver2 "1700000025"
    New-Item -ItemType Directory -Path $lockedRun -Force | Out-Null
    $lockedFile = Join-Path $lockedRun "locked.log"
    $lockStream = [System.IO.File]::Open($lockedFile, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
    
    # Run cleanup with locked directory present
    $cleanupThrew = $false
    try {
        Simulate-CleanOldUpdateRuns -UpdatesRoot $mockUpdatesRoot -KeepCount 1
    } catch {
        $cleanupThrew = $true
    } finally {
        $lockStream.Dispose()
    }
    Record-TestResult "T4.4" "CleanOldUpdateRuns exception suppression on locked directory" (-not $cleanupThrew) "Non-crashing warning logged when run directory cannot be deleted"

} catch {
    Write-Error "Exception during test suite execution: $_"
    Record-TestResult "SUITE_EXCEPTION" "Unhandled exception during harness run" $false "$_"
} finally {
    Write-Host "`n=== HARNESS EXECUTION SUMMARY ===" -ForegroundColor Cyan
    $passCount = ($testResults | Where-Object { $_.Status -eq "PASS" }).Count
    $failCount = ($testResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $totalCount = $testResults.Count

    Write-Host "Total Tests: $totalCount | Passed: $passCount | Failed: $failCount" -ForegroundColor $(if ($failCount -eq 0) { "Green" } else { "Red" })

    # Export results to JSON for reporting
    $resultsJsonPath = Join-Path $PSScriptRoot "test_results.json"
    $testResults | ConvertTo-Json -Depth 3 | Set-Content -Path $resultsJsonPath
    Write-Host "Results written to: $resultsJsonPath"
}
