#requires -Version 5.1
<#
.SYNOPSIS
    Evaluates the live PAC's own FindProxyForURL for one domain, using Windows
    built-in JScript (cscript.exe). No external runtime needed.

.DESCRIPTION
    Reads the generated PAC file and asks the exact same JavaScript that
    browsers evaluate: "for example.com, does the PAC say DIRECT or PROXY ...?"
    Returns a JSON object {domain, decision}. Read-only; never modifies files.

    The PAC's IP-based rules (GEOIP) are stubbed as "not matched" for this
    domain-oriented test, because the evaluator does not perform DNS resolution.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-PacDomain.ps1 -Domain www.google.com
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-PacDomain.ps1 -Domain jcomic.net -PacFile C:\proxy\proxy.pac
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
    [string]$Domain,

    [string]$PacFile = 'C:\proxy\proxy.pac'
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PacFile)) { throw "PAC file not found: $PacFile" }

$js = Join-Path $PSScriptRoot 'pac_eval.js'
if (-not (Test-Path -LiteralPath $js)) { throw "Missing helper: $js" }

$raw = & cscript.exe //nologo //E:JScript $js $PacFile $Domain 2>&1
if ($LASTEXITCODE -ne 0) { throw "PAC evaluation failed: $($raw -join ' ')" }
$decision = ($raw | Select-Object -Last 1) -join ''

[pscustomobject]@{
    domain   = $Domain
    decision = $decision
} | ConvertTo-Json -Compress