# Test Challenger's proposed fix vs full prerelease comparison

function CleanVersionString([string]$version) {
    if ([string]::IsNullOrWhiteSpace($version)) { return "0.0.0.0" }
    $v = $version.Trim().TrimStart('v', 'V')
    $splitIndex = $v.IndexOfAny(@('-', '+'))
    if ($splitIndex -ge 0) {
        $v = $v.Substring(0, $splitIndex)
    }
    return $v
}

function NormalizeVersion([string]$cleaned, [ref]$version) {
    $version.Value = [Version]::new(0, 0, 0, 0)
    $parts = $cleaned.Split('.')
    if ($parts.Length -eq 0 -or $parts.Length -gt 4) { return $false }
    $major = 0; $minor = 0; $build = 0; $rev = 0
    if ($parts.Length -gt 0 -and [int]::TryParse($parts[0], [ref]$major) -eq $false) { return $false }
    if ($parts.Length -gt 1 -and [int]::TryParse($parts[1], [ref]$minor) -eq $false) { return $false }
    if ($parts.Length -gt 2 -and [int]::TryParse($parts[2], [ref]$build) -eq $false) { return $false }
    if ($parts.Length -gt 3 -and [int]::TryParse($parts[3], [ref]$rev) -eq $false) { return $false }
    $version.Value = [Version]::new($major, $minor, $build, $rev)
    return $true
}

function ChallengerProposed-IsNewer([string]$currentVersion, [string]$newestVersion) {
    $cleanCurrent = CleanVersionString $currentVersion
    $cleanNewest = CleanVersionString $newestVersion

    $cur = [Version]::new(0,0,0,0)
    $new = [Version]::new(0,0,0,0)
    if ((NormalizeVersion $cleanCurrent ([ref]$cur)) -and (NormalizeVersion $cleanNewest ([ref]$new))) {
        if ($new -gt $cur) { return $true }
        if ($new -eq $cur) {
            $currentIsPrerelease = $currentVersion.Contains('-')
            $newestIsPrerelease = $newestVersion.Contains('-')
            if ($currentIsPrerelease -and -not $newestIsPrerelease) { return $true }
        }
    }
    return $false
}

Write-Host "Challenger proposed fix on beta.1 -> beta.2:" (ChallengerProposed-IsNewer "v2.16.0-beta.1" "v2.16.0-beta.2")
Write-Host "Challenger proposed fix on beta.1 -> 2.16.0:" (ChallengerProposed-IsNewer "v2.16.0-beta.1" "v2.16.0")
Write-Host "Challenger proposed fix on 2.16.0 -> 2.16.0.0:" (ChallengerProposed-IsNewer "2.16.0" "2.16.0.0")
Write-Host "Challenger proposed fix on 2.16 -> 2.16.0:" (ChallengerProposed-IsNewer "2.16" "2.16.0")
