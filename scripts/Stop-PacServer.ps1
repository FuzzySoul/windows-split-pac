[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$pidFile = Join-Path $root '.runtime\pac-server.pid'
$serverScript = (Resolve-Path (Join-Path $root 'src\pac_server.py')).Path

if (-not (Test-Path -LiteralPath $pidFile)) {
    Write-Output 'No managed PAC server PID file was found.'
    exit 0
}

$serverPid = (Get-Content -LiteralPath $pidFile -TotalCount 1).Trim()
if (-not $serverPid) {
    Remove-Item -LiteralPath $pidFile -Force
    Write-Output 'Removed an empty PAC server PID file.'
    exit 0
}

$processInfo = Get-CimInstance Win32_Process -Filter "ProcessId = $serverPid" -ErrorAction SilentlyContinue
if ($processInfo -and $processInfo.CommandLine -like "*$serverScript*") {
    Stop-Process -Id $serverPid -Force -ErrorAction Stop
    Write-Output "PAC server stopped. PID: $serverPid"
} elseif ($processInfo) {
    Write-Warning "PID $serverPid does not belong to this PAC server. It was not stopped."
} else {
    Write-Output "PAC server process $serverPid is already stopped."
}

Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
