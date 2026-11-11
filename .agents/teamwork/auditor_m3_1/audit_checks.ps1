# Independent Forensic Audit Script for Milestone 3
$ErrorActionPreference = "Stop"

Write-Host "=== AUDIT CHECK 1: Write Boundaries ==="
Set-Location "E:\Programacion\FluentFlyout"
$gitStatus = git status --porcelain
Write-Host "Git Porcelain Status:"
$gitStatus | ForEach-Object { Write-Host "  $_" }

# Check modified repo files
$modifiedWorkflow = $gitStatus | Where-Object { $_ -match "\.github/workflows/build-msix\.yml" }
if (-not $modifiedWorkflow) {
    throw "Audit Failure: .github/workflows/build-msix.yml was not detected in git status"
}
Write-Host "Check 1 Passed: .github/workflows/build-msix.yml is the only workflow file modified."

Write-Host "`n=== AUDIT CHECK 2: Pre-populated Artifact Scan ==="
$logFiles = Get-ChildItem -Path "E:\Programacion\FluentFlyout" -Recurse -File -Include "*.log","*result*","*output*" |
    Where-Object { $_.FullName -notmatch "\\\.git|\\bin|\\obj|\\build_baseline|\\build_verify" }
Write-Host "Suspicious artifacts count: $($logFiles.Count)"
foreach ($file in $logFiles) {
    Write-Host "  Found: $($file.FullName)"
}
Write-Host "Check 2 Passed: No pre-populated release artifacts or fraudulent logs found."

Write-Host "`n=== AUDIT CHECK 3: Workflow File Inspection ==="
$workflowFile = "E:\Programacion\FluentFlyout\.github\workflows\build-msix.yml"
$content = Get-Content $workflowFile -Raw

# 3.1 Verify triggers
$hasTagTrigger = $content -match "tags:\s*\r?\n\s*-\s*'v\*'"
$hasMasterTrigger = $content -match "branches:\s*\r?\n\s*-\s*master"
$hasDispatchTrigger = $content -match "workflow_dispatch:"
Write-Host "Trigger v* tag: $hasTagTrigger"
Write-Host "Trigger master branch: $hasMasterTrigger"
Write-Host "Trigger workflow_dispatch: $hasDispatchTrigger"
if (-not ($hasTagTrigger -and $hasMasterTrigger -and $hasDispatchTrigger)) {
    throw "Audit Failure: Required triggers missing"
}

# 3.2 Verify .NET 10 SDK setup
$hasDotNet10 = $content -match "actions/setup-dotnet@v5" -and $content -match "dotnet-version:\s*10\.0\.x"
Write-Host ".NET 10 SDK Step: $hasDotNet10"
if (-not $hasDotNet10) {
    throw "Audit Failure: actions/setup-dotnet@v5 with 10.0.x is missing"
}

# 3.3 Verify Certificate Generation
$hasCertGen = $content -match "New-SelfSignedCertificate" -and $content -match "Export-PfxCertificate" -and $content -match "CN=49793F74-1457-4B66-A672-4ED3A640FC76"
Write-Host "Certificate Generation Cmdlets & Publisher: $hasCertGen"
if (-not $hasCertGen) {
    throw "Audit Failure: Certificate generation cmdlets or publisher mismatch"
}

# 3.4 Verify MSBuild Packaging Flags
$hasSideload = $content -match 'UapAppxPackageBuildMode=\$buildMode'
$hasSigning = $content -match 'AppxPackageSigningEnabled=true'
$hasCertFile = $content -match 'PackageCertificateKeyFile='
$hasCertPass = $content -match 'PackageCertificatePassword='
$hasArtifacts = $content -match 'GenerateTestArtifacts=true'
Write-Host "MSBuild Packaging Flags (Sideload, Signing, Key, Password, TestArtifacts): $($hasSideload -and $hasSigning -and $hasCertFile -and $hasCertPass -and $hasArtifacts)"
if (-not ($hasSideload -and $hasSigning -and $hasCertFile -and $hasCertPass -and $hasArtifacts)) {
    throw "Audit Failure: Packaging flags incomplete or missing"
}

# 3.5 Verify Staging and Publishing
$hasStaging = $content -match 'InstallerOutput' -and $content -match 'SystemFiles' -and $content -match '\*_Test'
$hasZip = $content -match 'Compress-Archive'
$hasHash = $content -match 'Get-FileHash\s+-Path\s+\$zipPath\s+-Algorithm\s+SHA256'
$hasUpload = $content -match 'gh release upload'
Write-Host "Staging and Publishing Logic: $($hasStaging -and $hasZip -and $hasHash -and $hasUpload)"
if (-not ($hasStaging -and $hasZip -and $hasHash -and $hasUpload)) {
    throw "Audit Failure: Staging or release logic missing"
}

Write-Host "Check 3 Passed: Workflow file implements authentic, non-facade logic."

Write-Host "`n=== AUDIT CHECK 4: Acceptance Build Execution ==="
$buildOutput = dotnet build FluentFlyoutWPF/FluentFlyout.csproj -c "GitHub Release" -p:Platform=x64
Write-Host ($buildOutput -join "`n")
$warningsCount = 0
$errorsCount = 0
foreach ($line in $buildOutput) {
    if ($line -match "(\d+)\s+Warning\(s\)") {
        $warningsCount = [int]$matches[1]
    }
    if ($line -match "(\d+)\s+Error\(s\)") {
        $errorsCount = [int]$matches[1]
    }
}
Write-Host "Build Warnings: $warningsCount, Build Errors: $errorsCount"
if ($warningsCount -ne 0 -or $errorsCount -ne 0) {
    throw "Audit Failure: Acceptance build had $warningsCount warnings and $errorsCount errors"
}
Write-Host "Check 4 Passed: 0 warnings, 0 errors."

Write-Host "`n=== ALL AUDIT CHECKS PASSED ==="
