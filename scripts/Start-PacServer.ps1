[CmdletBinding()]
param(
    [string]$PacFile = (Join-Path $PSScriptRoot '..\dist\proxy.pac'),
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runtimeDirectory = Join-Path $root '.runtime'
$pidFile = Join-Path $runtimeDirectory 'pac-server.pid'
$stdoutFile = Join-Path $runtimeDirectory 'pac-server.stdout.log'
$stderrFile = Join-Path $runtimeDirectory 'pac-server.stderr.log'
$serverScript = Join-Path $root 'src\pac_server.py'
$url = "http://127.0.0.1:$Port/proxy.pac"

if (-not (Test-Path -LiteralPath $PacFile)) {
    throw "PAC file not found: $PacFile. Run .\scripts\Build-Pac.ps1 first."
}

try {
    $existing = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 2
    if ($existing.StatusCode -eq 200) {
        Write-Output "PAC server is already responding: $url"
        exit 0
    }
} catch {
    # The port is available or contains a non-responsive process; continue and let Python report a real bind failure.
}

foreach ($candidate in @('python', 'py')) {
    try {
        $pythonPath = & $candidate -c 'import sys; print(sys.executable)' 2>$null
        if ($LASTEXITCODE -eq 0 -and $pythonPath) {
            $python = ($pythonPath | Select-Object -Last 1).Trim()
            break
        }
    } catch {
        continue
    }
}
if (-not $python) {
    throw 'Python 3 was not found. Run .\scripts\Install-Dependencies.ps1 first.'
}

New-Item -ItemType Directory -Force -Path $runtimeDirectory | Out-Null
$resolvedPacFile = (Resolve-Path $PacFile).Path
$process = Start-Process -FilePath $python -ArgumentList @("`"$serverScript`"", '--pac-file', "`"$resolvedPacFile`"", '--port', $Port) -WindowStyle Hidden -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile -PassThru
Set-Content -LiteralPath $pidFile -Value $process.Id -Encoding ascii
Start-Sleep -Milliseconds 700

try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec 5
    if ($response.StatusCode -ne 200) {
        throw "HTTP $($response.StatusCode)"
    }
} catch {
    if (Get-Process -Id $process.Id -ErrorAction SilentlyContinue) {
        Stop-Process -Id $process.Id -Force
    }
    Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
    throw "PAC server failed to start: $($_.Exception.Message)"
}

Write-Output "PAC server started: $url"
Write-Output "PID: $($process.Id)"
