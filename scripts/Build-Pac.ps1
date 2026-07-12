[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[^\s:]+:\d+$')]
    [string]$ProxyAddress,

    [string]$RulesFile = (Join-Path $PSScriptRoot '..\rules\user-rules.txt'),

    [string]$OutputPath = (Join-Path $PSScriptRoot '..\dist\proxy.pac'),

    [string]$GfwListUrl = 'https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt'
)

$ErrorActionPreference = 'Stop'

foreach ($candidate in @('python', 'py')) {
    try {
        & $candidate -m genpac --version *> $null
        if ($LASTEXITCODE -eq 0) {
            $python = $candidate
            break
        }
    } catch {
        continue
    }
}

if (-not $python) {
    throw 'genpac is not available. Run .\scripts\Install-Dependencies.ps1 first.'
}

if (-not (Test-Path -LiteralPath $RulesFile)) {
    throw "Rules file not found: $RulesFile"
}

$outputDirectory = Split-Path -Parent $OutputPath
New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null

& $python -m genpac --format pac --pac-proxy "PROXY $ProxyAddress" --gfwlist-url $GfwListUrl --user-rule-from $RulesFile --output $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw 'PAC generation failed. Check the proxy address and whether GitHub is reachable.'
}

if (-not (Test-Path -LiteralPath $OutputPath)) {
    throw "genpac completed without creating: $OutputPath"
}

Write-Output "PAC generated: $(Resolve-Path $OutputPath)"
Write-Output "Proxy endpoint: $ProxyAddress"
