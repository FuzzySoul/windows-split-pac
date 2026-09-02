#requires -Version 5.1
<#
.SYNOPSIS
    One-command test harness for windows-split-pac. Run on Windows.

.DESCRIPTION
    Verifies, in order:
      1. every PowerShell script in scripts/ parses
      2. rust-gui/core unit tests pass (headless-safe)
      3. the full Rust workspace compiles (cargo check)
      4. live identity (read-only) reports a healthy real serve_pac + /healthz
      5. Apply-PacConfig dry-run (read-only) plans all 5 steps

    Nothing here modifies the live service: steps 4-5 are strictly read-only.

.PARAMETER SkipLive
    Skip the live read-only probes (for CI machines that don't run the service).

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-All.ps1
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-All.ps1 -SkipLive
#>
[CmdletBinding()]
param(
    [switch]$SkipLive
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$manifest = Join-Path $root 'rust-gui\Cargo.toml'
$failures = [System.Collections.Generic.List[string]]::new()

function Test-Step([string]$name, [scriptblock]$body) {
    Write-Host "▶ $name"
    try {
        & $body
        Write-Host "  ✔ PASS"
    } catch {
        Write-Host "  ✘ FAIL: $($_.Exception.Message)"
        $failures.Add($name)
    }
}

Test-Step 'PowerShell scripts parse' {
    $errs = $null
    foreach ($f in Get-ChildItem -Path $PSScriptRoot -Filter '*.ps1') {
        [void][System.Management.Automation.PSParser]::Tokenize((Get-Content -Raw $f.FullName), [ref]$errs)
        if ($errs.Count -gt 0) { throw "Syntax errors in $($f.Name): $($errs[0].Message)" }
        $errs = $null
    }
}

Test-Step 'Core crate unit tests (cargo test -p windows-split-pac-core)' {
    & cargo test -p windows-split-pac-core --manifest-path $manifest *> $null
    if ($LASTEXITCODE -ne 0) { throw 'cargo core tests failed' }
}

Test-Step 'Rust workspace compiles (cargo check --workspace)' {
    & cargo check --workspace --manifest-path $manifest *> $null
    if ($LASTEXITCODE -ne 0) { throw 'cargo check failed' }
}

if (-not $SkipLive) {
    Test-Step 'Live identity (read-only) reports healthy real serve_pac' {
        $json = & (Join-Path $PSScriptRoot 'Get-ServiceIdentity.ps1') | ConvertFrom-Json
        if (-not $json.server_running) { throw 'no PAC server is running' }
        if ($json.server_kind -ne 'real_serve_pac') { throw "unexpected server_kind=$($json.server_kind)" }
        if (-not $json.healthz_ok) { throw '/healthz is not responding' }
        if (-not $json.pid_file_matches) { throw 'pid file does not match the live listener' }
        if (-not $json.windows_using_our_pac) { throw 'Windows is not using our PAC' }
    }

    Test-Step 'Apply dry-run plans all 5 steps (read-only)' {
        $json = & (Join-Path $PSScriptRoot 'Apply-PacConfig.ps1') | ConvertFrom-Json
        if ($json.applied) { throw 'dry-run unexpectedly applied' }
        $planned = @($json.steps | ForEach-Object { ($_ -replace '^planned:', '') })
        foreach ($need in @('backup', 'generate-pac', 'service', 'enable-windows', 'verify')) {
            if ($planned -notcontains $need) { throw "missing planned step: $need" }
        }
    }
}

Write-Host ''
if ($failures.Count -gt 0) {
    Write-Host "TEST RESULT: FAIL -> $($failures -join ', ')"
    exit 1
}
Write-Host 'TEST RESULT: ALL PASS'