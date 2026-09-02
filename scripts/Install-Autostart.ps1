#requires -Version 5.1
<#
.SYNOPSIS
    Install per-user autostart for the product PAC engine.

.DESCRIPTION
    Preferred method: "WindowsSplitPAC" scheduled task (AtLogOn) running
    <root>\src\pac_server.py via pythonw. Creating scheduled tasks generally
    needs admin rights; if that fails (0x80070005 on non-admin), this script
    falls back to the current user's HKCU\...\Run startup entry which requires
    no elevation. It never depends on a pre-generated PAC file.

.PARAMETER Port
    Local PAC port (default 8765).
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$serverScript = Join-Path $root 'src\pac_server.py'
$taskName = 'WindowsSplitPAC'
$runValueName = 'WindowsSplitPAC'

# Find a python launcher (pythonw hides the console).
$launcher = $null
foreach ($candidate in @('pythonw', 'python', 'py')) {
    try {
        & $candidate -c 'import sys' *> $null
        if ($LASTEXITCODE -eq 0) { $launcher = $candidate; break }
    } catch { continue }
}
if (-not $launcher) { throw 'Python launcher not found (pythonw/python/py).' }
$launcherPath = (Get-Command $launcher -ErrorAction SilentlyContinue).Source
if (-not $launcherPath) { $launcherPath = $launcher }

$runCommand = "`"$launcherPath`" `"$serverScript`" --port $Port"

try {
    $action = New-ScheduledTaskAction -Execute $launcherPath -Argument "`"$serverScript`" --port $Port"
    $trigger = New-ScheduledTaskTrigger -AtLogOn
    $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings `
        -Description 'Starts the Windows Split PAC product engine at user logon.' -Force | Out-Null
    Write-Output "Autostart installed: $taskName (scheduled task)"
} catch {
    Write-Warning "Scheduled task registration failed: $($_.Exception.Message). Falling back to HKCU Run."
    $runKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path -LiteralPath $runKey)) { New-Item -Path $runKey -Force | Out-Null }
    Set-ItemProperty -Path $runKey -Name $runValueName -Value $runCommand
    Write-Output "Autostart installed: $runValueName (HKCU Run, no admin needed)"
}
