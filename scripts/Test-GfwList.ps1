#requires -Version 5.1
<#
.SYNOPSIS
    Fresh-machine GFWList E2E: generate a PAC from an empty temp dir and
    verify that BOTH the online GFWList and custom user rules are baked in.

.DESCRIPTION
    Simulates a brand-new machine (no dist\, no C:\proxy): writes two custom
    rules into a temp file, runs Build-Pac.ps1 (which fetches GFWList online),
    then asserts known GFWList domains (google.com / youtube.com) and the
    custom rules (coolinet.net / twitch.tv) are present in the PAC.

.EXAMPLE
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-GfwList.ps1
#>
[CmdletBinding()]
param(
    [string]$ProxyAddress = '10.10.10.19:8080',
    [string]$TempRoot = ''
)

$ErrorActionPreference = 'Stop'
if (-not $TempRoot) { $TempRoot = Join-Path $env:TEMP 'wsp-gfwtest' }
New-Item -ItemType Directory -Force -Path $TempRoot | Out-Null

$rules = Join-Path $TempRoot 'user-rules.txt'
$pac = Join-Path $TempRoot 'proxy.pac'
Set-Content -Encoding ascii -Path $rules -Value '||coolinet.net', '||twitch.tv'

& (Join-Path $PSScriptRoot 'Build-Pac.ps1') `
    -ProxyAddress $ProxyAddress `
    -RulesFile $rules `
    -OutputPath $pac

$text = Get-Content -LiteralPath $pac -Raw
$checks = @('google.com', 'youtube.com', 'coolinet.net', 'twitch.tv')
$missing = @($checks | Where-Object { -not $text.Contains($_) })
if ($missing.Count -gt 0) {
    throw "GFWList / custom rule missing in generated PAC: $($missing -join ', ')"
}

[pscustomobject]@{
    pac_file             = $pac
    size                 = (Get-Item -LiteralPath $pac).Length
    gfwlist_included     = $true
    custom_rules_included = $true
    checks               = $checks
} | ConvertTo-Json -Compress
