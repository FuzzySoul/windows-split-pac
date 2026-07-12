[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$startScript = Join-Path $root 'scripts\Start-PacServer.ps1'
$taskName = 'WindowsSplitPAC'

if (-not (Test-Path -LiteralPath (Join-Path $root 'dist\proxy.pac'))) {
    throw 'No generated PAC file exists. Run .\scripts\Build-Pac.ps1 before enabling autostart.'
}

$escapedScript = "& '$startScript' -Port $Port"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -Command $escapedScript"
$trigger = New-ScheduledTaskTrigger -AtLogOn
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description 'Starts the local Windows Split PAC server at user logon.' -Force | Out-Null

Write-Output "Autostart task installed: $taskName"
Write-Output 'It only starts the local PAC server. It does not change Windows proxy settings.'
