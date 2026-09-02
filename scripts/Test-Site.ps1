#requires -Version 5.1
<#
.SYNOPSIS
    Test one domain end-to-end: what the PAC says AND whether the site actually
    opens through the chosen upstream proxy (or directly).

.DESCRIPTION
    Steps:
      1. Evaluate the real PAC's FindProxyForURL for the domain (cscript/JScript).
      2. If the PAC says PROXY, perform a real HTTPS request through that proxy
         with a timeout.
      3. If DIRECT, perform a direct HTTPS request (proxy disabled in-process).
    Returns JSON: {domain, decision, reachable, status, error}.

    This is the test that tells a user "did it really work", not just "which
    bucket the rule is in".

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Site.ps1 -Domain www.coolinet.net
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-zA-Z0-9\-\.]+$')]
    [string]$Domain,

    [string]$PacFile = 'C:\proxy\proxy.pac',

    [string]$ProxyAddress = '',

    [ValidateRange(1, 60)]
    [int]$TimeoutSec = 15
)

$ErrorActionPreference = 'Stop'
[System.Net.WebRequest]::DefaultWebProxy = $null  # never let local logic go through a random proxy

if (-not (Test-Path -LiteralPath $PacFile)) { throw "PAC file not found: $PacFile" }

# --- 1) PAC decision ---
$js = Join-Path $PSScriptRoot 'pac_eval.js'
if (-not (Test-Path -LiteralPath $js)) { throw "Missing helper: $js" }
$raw = & cscript.exe //nologo //E:JScript $js $PacFile $Domain 2>&1
if ($LASTEXITCODE -ne 0) { throw "PAC evaluation failed: $($raw -join ' ')" }
$decision = ($raw | Select-Object -Last 1) -join ''

# Infer the upstream proxy from the PAC if not given explicitly.
if (-not $ProxyAddress -and $decision -match 'PROXY\s+(\S+)') {
    $ProxyAddress = $Matches[1].Trim()
}

$url = "https://$Domain/"
$status = $null
$errorMsg = $null

# --- 2) Real connectivity check ---
if ($decision -eq 'DIRECT') {
    try {
        $r = Invoke-WebRequest -UseBasicParsing -Uri $url -TimeoutSec $TimeoutSec -MaximumRedirection 5
        $status = $r.StatusCode
    } catch {
        $errorMsg = $_.Exception.Message
    }
} else {
    if (-not $ProxyAddress) {
        $errorMsg = "No proxy address in PAC decision: $decision"
    } else {
        $proxyUrl = "http://$ProxyAddress"
        try {
            $r = Invoke-WebRequest -UseBasicParsing -Uri $url -Proxy $proxyUrl -TimeoutSec $TimeoutSec -MaximumRedirection 5
            $status = $r.StatusCode
        } catch {
            $errorMsg = $_.Exception.Message
        }
    }
}

[pscustomobject]@{
    domain    = $Domain
    decision  = $decision
    reachable = ($null -ne $status)
    status    = $status
    error     = $errorMsg
} | ConvertTo-Json -Compress