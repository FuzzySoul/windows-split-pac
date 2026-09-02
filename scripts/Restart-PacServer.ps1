#requires -Version 5.1
<#
.SYNOPSIS
    Restart the local PAC server process on a given port (keeps Windows registry unchanged).

.DESCRIPTION
    Stops whatever is listening on the port, then starts the product engine
    (src/pac_server.py) with the specified PAC file / runtime dir / pid file.
    Verifies /healthz and /proxy.pac after starting. Used by the GUI's optional
    "重启分流服务" button and by VM/isolated tests.

    NOTE: after a rules change the running serve_pac.py already serves the new
    PAC immediately (it reads the file on every request), so a restart is NOT
    required for rule updates. This script exists for service-code upgrades and
    manual force-refresh.

.PARAMETER Port
    Local PAC port (default 8765). Use a different port for isolated tests.

.PARAMETER PacFile
    PAC file to serve. Default C:\proxy\proxy.pac.

.PARAMETER RunDir
    Runtime directory for pid/log files. Default C:\proxy.

.PARAMETER ServiceScript
    Engine script to start. Defaults to this repo's src\pac_server.py.
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    [string]$PacFile = 'C:\proxy\proxy.pac',
    [string]$RunDir = 'C:\proxy',
    [string]$ServiceScript = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $ServiceScript) { $ServiceScript = Join-Path $root 'src\pac_server.py' }
$pidFile = Join-Path $RunDir 'pac-server.pid'
$url = "http://127.0.0.1:$Port/proxy.pac"
$hz = "http://127.0.0.1:$Port/healthz"

$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    $oldPid = [int]$listener.OwningProcess
    Write-Host "Stopping current PAC server on :$Port (PID $oldPid)"
    Stop-Process -Id $oldPid -Force
    Start-Sleep -Milliseconds 800
}

# Prefer pythonw (no console) then python / py
$launcher = $null
foreach ($candidate in @('pythonw', 'python', 'py')) {
    try {
        & $candidate -c 'import sys' *> $null
        if ($LASTEXITCODE -eq 0) { $launcher = $candidate; break }
    } catch { continue }
}
if (-not $launcher) { throw 'Python launcher not found (pythonw/python/py).' }

New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
if (-not (Test-Path -LiteralPath $PacFile)) { throw "PAC file not found: $PacFile" }
$resolvedPac = (Resolve-Path $PacFile).Path

$proc = Start-Process -FilePath $launcher `
    -ArgumentList @("`"$ServiceScript`"", '--pac-file', "`"$resolvedPac`"", '--port', $Port, '--pid-file', "`"$pidFile`"") `
    -WindowStyle Hidden `
    -RedirectStandardOutput (Join-Path $RunDir 'pac-server.stdout.log') `
    -RedirectStandardError (Join-Path $RunDir 'pac-server.stderr.log') `
    -PassThru

Start-Sleep -Seconds 2
$okH = $false; $okP = $false
try { $okH = ((Invoke-WebRequest -UseBasicParsing -Uri $hz -TimeoutSec 5).StatusCode -eq 200) } catch {}
try { $okP = ((Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5).StatusCode -eq 200) } catch {}
if (-not ($okH -and $okP)) {
    if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $proc.Id -Force }
    throw "Service restart failed on :$Port (healthz=$okH pac=$okP)"
}
Write-Host "PAC server restarted: PID $($proc.Id), :$Port"