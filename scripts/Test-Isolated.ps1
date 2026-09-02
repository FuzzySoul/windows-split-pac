#requires -Version 5.1
<#
.SYNOPSIS
    Isolated end-to-end test for the PAC apply pipeline - safe for a VM or any
    machine because it does NOT touch the live C:\proxy, the 8765 service, or
    the Windows registry.

.DESCRIPTION
    Uses a temp directory + a non-default port + SkipWindows + SkipGenerate so
    the pipeline is exercised in isolation:
      1. writes tiny sample rules + a tiny PAC
      2. runs Apply-PacConfig.ps1 -Apply -SkipWindows -SkipGenerate on a temp port
      3. verifies applied=true, errors=[], pac_ok=true, healthz_ok=true
      4. stops the temp service and cleans up

    Full genpac/GFWList generation is intentionally skipped here (needs network);
    that path is already covered by the live apply / Test-Package.ps1.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Isolated.ps1
#>
[CmdletBinding()]
param(
    [ValidateRange(1024, 65535)]
    [int]$Port = 18899,
    [string]$TempRoot = ''
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
if (-not $TempRoot) { $TempRoot = Join-Path $env:TEMP 'wsp-vm-test' }

New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null
$rules = Join-Path $TempRoot 'user-rules.txt'
$pac = Join-Path $TempRoot 'proxy.pac'

# Tiny sample rules + tiny PAC (no network, no genpac needed)
@('||vmtest-proxy.example', '||vmtest-direct.example', '@@||vmtest-no-proxy.example') |
    Set-Content -Encoding ascii -Path $rules
@'
function FindProxyForURL(url, host) {
  if (host == "vmtest-no-proxy.example") return "DIRECT";
  if (dnsDomainIs(host, ".example")) return "PROXY 127.0.0.1:9999";
  return "DIRECT";
}
'@ | Set-Content -Encoding ascii -Path $pac

Write-Host "Isolated apply on :$Port (temp=$TempRoot, no registry, no genpac)"
# Capture ONLY stdout (diagnostics go to stderr) and parse the whole stdout as
# one JSON document - exactly what the Rust engine does. Any stray stdout line
# (e.g. regression) makes this test fail loudly.
$stdout = & (Join-Path $PSScriptRoot 'Apply-PacConfig.ps1') `
    -Apply `
    -Port $Port `
    -ProxyAddress '127.0.0.1:9999' `
    -PacFile $pac `
    -RulesFile $rules `
    -RunDir $TempRoot `
    -SkipWindows `
    -SkipGenerate 2>$null
$stdoutText = $stdout | Out-String
try {
    $apply = $stdoutText | ConvertFrom-Json
} catch {
    throw "stdout is not pure JSON (got: $stdoutText)"
}

if (-not $apply.applied) { throw 'apply did not run' }
if ($apply.errors.Count -gt 0) { throw "apply errors: $($apply.errors -join '; ')" }
if (-not $apply.pac_ok) { throw 'pac endpoint not serving' }
if (-not $apply.healthz_ok) { throw 'healthz endpoint not serving' }
if (-not $apply.service.pid) { throw 'no service pid reported' }

Write-Host "ISOLATED APPLY OK: pid=$($apply.service.pid) port=$Port steps=$($apply.steps -join ',')"

# Cleanup: stop the temp service and remove pid file (keep temp files for log review)
$listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
if ($listener) {
    Stop-Process -Id ([int]$listener.OwningProcess) -Force
    Write-Host "Stopped temp service PID $($listener.OwningProcess)"
}
Remove-Item -LiteralPath (Join-Path $TempRoot 'pac-server.pid') -Force -ErrorAction SilentlyContinue

Write-Host 'ISOLATED TEST PASS'