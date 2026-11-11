$env:CONFIGURATION = 'GitHub Release'
$testFile = Join-Path $PSScriptRoot "echo_args.bat"
"@echo off
echo arg1=%1
echo arg2=%2
" | Out-File -FilePath $testFile -Encoding ascii

& $testFile /p:Configuration=$env:CONFIGURATION
Remove-Item $testFile -Force
