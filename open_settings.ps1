try {
    $event = [System.Threading.EventWaitHandle]::OpenExisting("FluentFlyout_OpenSettings")
    $event.Set() | Out-Null
    Write-Output "SUCCESS: Signal sent to FluentFlyout to display Settings Window!"
} catch {
    Write-Output "ERROR: $($_.Exception.Message)"
}
