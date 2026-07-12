[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'WindowsSplitPAC'
$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue

if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Autostart task removed: $taskName"
} else {
    Write-Output "Autostart task was not installed: $taskName"
}
