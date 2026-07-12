[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-split-pac-test-" + [Guid]::NewGuid().ToString('N'))
$rulesFile = Join-Path $testRoot 'rules.txt'
$pacFile = Join-Path $testRoot 'proxy.pac'
$port = Get-Random -Minimum 20000 -Maximum 30000
$serverScript = Join-Path $root 'src\pac_server.py'
$process = $null

function Get-PythonExecutable {
    foreach ($candidate in @('python', 'py')) {
        try {
            $pythonPath = & $candidate -c 'import sys; print(sys.executable)' 2>$null
            if ($LASTEXITCODE -eq 0 -and $pythonPath) {
                return ($pythonPath | Select-Object -Last 1).Trim()
            }
        } catch {
            continue
        }
    }
    throw 'Python 3 was not found.'
}

try {
    New-Item -ItemType Directory -Force -Path $testRoot | Out-Null
    Set-Content -LiteralPath $rulesFile -Value '||example.com' -Encoding ascii
    $python = Get-PythonExecutable

    & $python -m genpac --format pac --gfwlist-disabled --pac-proxy 'PROXY 192.0.2.10:8080' --user-rule-from $rulesFile --output $pacFile
    if ($LASTEXITCODE -ne 0) {
        throw 'genpac did not generate a test PAC file.'
    }

    $pacContent = Get-Content -LiteralPath $pacFile -Raw
    if ($pacContent -notmatch "PROXY 192\.0\.2\.10:8080" -or $pacContent -notmatch 'example\.com') {
        throw 'Generated PAC does not contain the expected proxy endpoint and custom rule.'
    }

    $process = Start-Process -FilePath $python -ArgumentList @("`"$serverScript`"", '--pac-file', "`"$pacFile`"", '--port', $port) -WindowStyle Hidden -PassThru
    $response = $null
    foreach ($attempt in 1..20) {
        try {
            $response = Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$port/proxy.pac" -TimeoutSec 1
            break
        } catch {
            Start-Sleep -Milliseconds 150
        }
    }
    if (-not $response) {
        throw 'PAC server did not become ready within 3 seconds.'
    }
    if ($response.StatusCode -ne 200 -or $response.Headers['Content-Type'] -notmatch 'application/x-ns-proxy-autoconfig') {
        throw 'PAC server did not return the expected response or MIME type.'
    }

    $health = Invoke-RestMethod -Uri "http://127.0.0.1:$port/healthz" -TimeoutSec 5
    if ($health.status -ne 'ok') {
        throw 'PAC server health endpoint did not return ok.'
    }

    Write-Output 'Package test passed: generation, custom rules, serving, MIME type, and health check.'
} finally {
    if ($process -and (Get-Process -Id $process.Id -ErrorAction SilentlyContinue)) {
        Stop-Process -Id $process.Id -Force
    }
    Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
}
