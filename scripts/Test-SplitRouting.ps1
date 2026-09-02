[CmdletBinding()]
param(
    [string]$PacFile = (Join-Path $PSScriptRoot '..\dist\proxy.pac'),
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    [string]$ProxyDomain = 'www.google.com',
    [string]$DirectDomain = 'www.baidu.com'
)

$ErrorActionPreference = 'Stop'
$testScript = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-split-pac-decision-" + [Guid]::NewGuid().ToString('N') + '.js')

function Get-PacDecision([string]$domain) {
    $escapedPacFile = $PacFile.Replace('\', '\\').Replace('"', '\"')
    $escapedDomain = $domain.Replace('"', '\"')
    @"
var fso = new ActiveXObject("Scripting.FileSystemObject");
var file = fso.OpenTextFile("$escapedPacFile", 1);
eval(file.ReadAll());
file.Close();
WScript.Echo(FindProxyForURL("https://$escapedDomain/", "$escapedDomain"));
"@ | Set-Content -LiteralPath $testScript -Encoding ascii

    try {
        $decision = (& cscript.exe //nologo $testScript 2>&1 | Select-Object -Last 1).ToString().Trim()
        if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($decision)) { throw 'cscript could not evaluate the generated PAC file.' }
        return $decision
    } finally {
        Remove-Item -LiteralPath $testScript -Force -ErrorAction SilentlyContinue
    }
}

$serverHealthy = $false
try { $serverHealthy = (Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:$Port/proxy.pac" -TimeoutSec 3).StatusCode -eq 200 } catch { $serverHealthy = $false }
if (-not (Test-Path -LiteralPath $PacFile)) { throw "PAC file not found: $PacFile" }

$proxyDecision = Get-PacDecision $ProxyDomain
$directDecision = Get-PacDecision $DirectDomain

[pscustomobject]@{
    pac_server_healthy = $serverHealthy
    proxy_domain = $ProxyDomain
    proxy_decision = $proxyDecision
    direct_domain = $DirectDomain
    direct_decision = $directDecision
    split_routing_verified = $serverHealthy -and $proxyDecision -match '^PROXY\s+' -and $directDecision -eq 'DIRECT'
} | ConvertTo-Json -Compress
