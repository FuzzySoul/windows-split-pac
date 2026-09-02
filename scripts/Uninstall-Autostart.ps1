#requires -Version 5.1
<#
.SYNOPSIS
    Remove the WindowsSplitPAC autostart (scheduled task and/or HKCU Run).
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$taskName = 'WindowsSplitPAC'
$runValueName = 'WindowsSplitPAC'

$task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
if ($task) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    Write-Output "Autostart task removed: $taskName"
}

$runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
Remove-ItemProperty -Path $runKey -Name $runValueName -ErrorAction SilentlyContinue
Write-Output 'Autostart entries cleaned.'
