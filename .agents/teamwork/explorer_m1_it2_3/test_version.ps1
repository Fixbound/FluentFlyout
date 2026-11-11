$v3 = [Version]'2.16.0'
$v4 = [Version]'2.16.0.0'
Write-Host "v3 Revision: $($v3.Revision)"
Write-Host "v4 Revision: $($v4.Revision)"
Write-Host "v4 > v3: $($v4 -gt $v3)"
Write-Host "v3 == v4: $($v3 -eq $v4)"
Write-Host "v3.CompareTo(v4): $($v3.CompareTo($v4))"

$v2 = [Version]'2.16'
Write-Host "v2 Build: $($v2.Build)"
Write-Host "v3 > v2: $($v3 -gt $v2)"
