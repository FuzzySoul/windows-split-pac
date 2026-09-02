[CmdletBinding()]
param(
    # Optional override of the real service PAC port (default 8765).
    # This script is strictly READ-ONLY: it never starts/stops/restarts any service.
    [ValidateRange(1024, 65535)]
    [int]$Port = 8765,
    # Optional override of the real service PAC file path (rule diff + proxy extraction).
    [string]$PacFile = 'C:\proxy\proxy.pac',
    # Optional override of the real service rules file path.
    [string]$OnlineRulesFile = 'C:\proxy\user-rules.txt'
)
$ErrorActionPreference = 'Stop'
[System.Net.WebRequest]::DefaultWebProxy = $null  # local checks never go through a proxy

# Repo-side rules file (the GUI default; lives one level above this script).
$repoRoot = Split-Path -Parent $PSScriptRoot
$repoRules = Join-Path $repoRoot 'rules\user-rules.txt'
# Repo-side dist artifact (the GUI parallel service would use this as its PAC).
$repoDistPac = Join-Path $repoRoot 'dist\proxy.pac'

# ---------- A. Port + process (most authoritative) ----------
$serverPid = $null
$serverCmd = ''
try {
    $listener = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction Stop | Select-Object -First 1
} catch { $listener = $null }

if ($null -ne $listener) {
    $serverPid = [int]$listener.OwningProcess
    try {
        $proc = Get-CimInstance Win32_Process -Filter "ProcessId=$serverPid" -ErrorAction Stop
        $serverCmd = [string]$proc.CommandLine
    } catch {
        $serverCmd = ''
    }
}

# Classify: who is actually serving on the port
$serverKind = 'none'
if ($null -ne $serverPid) {
    if ($serverCmd -match 'serve_pac\.py') {
        $serverKind = 'real_serve_pac'
    } elseif ($serverCmd -match 'pac_server\.py') {
        $serverKind = 'gui_pac_server'
    } else {
        $serverKind = 'unknown'
    }
}

# Does it respond to /proxy.pac ? (read-only GET probe)
$pacUrl = "http://127.0.0.1:$Port/proxy.pac"
$pacHttpOk = $false
$pacProxy = ''
try {
    # Note: Invoke-WebRequest returns the PAC payload as a byte array for
    # non-text MIME types; use WebClient.DownloadString to get a proper string.
    $content = (New-Object System.Net.WebClient).DownloadString($pacUrl)
    if ($null -ne $content) {
        $pacHttpOk = $true
        # Extract the PROXY target from the served PAC, e.g. "PROXY 10.10.10.19:8080"
        # -cmatch is case-sensitive: the PAC declares `var proxy = "PROXY ..."` and
        # we only want the literal uppercase PROXY directive after whitespace.
        if ($content -cmatch 'PROXY\s+[^\s"'';]+') {
            $pacProxy = $Matches[0]
        }
    }
} catch { $pacHttpOk = $false }
# Does /healthz respond? (product engine supports it; the old live serve_pac.py did not)
$healthzOk = $false
$healthzPid = $null
try {
    $hzContent = (New-Object System.Net.WebClient).DownloadString("http://127.0.0.1:$Port/healthz")
    $hzJson = $hzContent | ConvertFrom-Json
    if ($null -ne $hzJson.status -and [string]$hzJson.status -eq 'ok') {
        $healthzOk = $true
        if ($hzJson.PSObject.Properties.Name -contains 'pid') { $healthzPid = [int]$hzJson.pid }
    }
} catch { $healthzOk = $false }

# ---------- B. PID file (auxiliary; stale-prone; must cross-check with A) ----------
$pidFile = Join-Path (Split-Path -Parent $PacFile) 'pac-server.pid'
$pidFileExists = Test-Path -LiteralPath $pidFile
$pidFileValue = $null
$pidFileMatches = $false
if ($pidFileExists) {
    $raw = (Get-Content -LiteralPath $pidFile -Raw -ErrorAction SilentlyContinue).Trim()
    if ($raw -match '^\d+$') { $pidFileValue = [int]$raw } else { $pidFileValue = $null }
    $pidFileMatches = ($null -ne $serverPid) -and ($pidFileValue -eq $serverPid)
}

# ---------- C. Registry (is Windows really using the PAC) ----------
$s = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$autoConfigUrl = [string]$s.AutoConfigURL
$proxyEnable = ([int]$s.ProxyEnable -ne 0)
$proxyServer = [string]$s.ProxyServer
$proxyOverride = [string]$s.ProxyOverride
$autoDetect = ([bool]$s.AutoDetect)

# Is Windows using our local PAC service?
$windowsUsingOurPac = $false
if (-not [string]::IsNullOrWhiteSpace($autoConfigUrl)) {
    $windowsUsingOurPac = $autoConfigUrl -match [regex]::Escape("$Port/proxy.pac")
}

# ---------- D. Autostart scheduled tasks ----------
function Get-TaskState([string]$name) {
    try {
        $t = Get-ScheduledTask -TaskName $name -ErrorAction Stop
        [pscustomobject]@{ exists = $true; name = $name; state = [string]$t.State }
    } catch {
        [pscustomobject]@{ exists = $false; name = $name; state = 'Not present' }
    }
}
$realTask = Get-TaskState 'PACServer'
$guiTask  = Get-TaskState 'WindowsSplitPAC'

# ---------- E. Rules file comparison ----------
function Get-RuleLines([string]$path) {
    if (-not (Test-Path -LiteralPath $path)) { return @() }
    @(Get-Content -LiteralPath $path -ErrorAction SilentlyContinue |
        ForEach-Object { ($_ -replace '#.*$', '').Trim() } |
        Where-Object { $_ -and -not $_.StartsWith('!') -and -not $_.StartsWith('#') })
}
$onlineRuleLines = @(Get-RuleLines $OnlineRulesFile)
$repoRuleLines   = @(Get-RuleLines $repoRules)
$ruleCountOnline = $onlineRuleLines.Count
$ruleCountRepo   = $repoRuleLines.Count
$rulesInSync = ($ruleCountOnline -eq $ruleCountRepo) -and -not (Compare-Object $onlineRuleLines $repoRuleLines)

# ---------- Summary ----------
[pscustomobject]@{
    server_running         = ($null -ne $serverPid) -and $pacHttpOk
    server_kind            = $serverKind
    pid                    = $serverPid
    pid_file_matches       = $pidFileMatches
    pid_file_value         = $pidFileValue
    port                   = $Port
    pac_url                = $pacUrl
    pac_http_ok            = $pacHttpOk
    pac_proxy              = $pacProxy
        healthz_ok = $healthzOk
        healthz_pid = $healthzPid
    server_cmd             = $serverCmd
    auto_config_url        = $autoConfigUrl
    proxy_enable           = $proxyEnable
    proxy_server           = $proxyServer
    proxy_override         = $proxyOverride
    auto_detect            = $autoDetect
    windows_using_our_pac  = $windowsUsingOurPac
    autostart_real         = $realTask
    autostart_gui          = $guiTask
    rule_file_diff         = [pscustomobject]@{
        online_rules = $ruleCountOnline
        gui_rules    = $ruleCountRepo
        in_sync      = $rulesInSync
        online_file  = $OnlineRulesFile
        repo_file    = $repoRules
    }
} | ConvertTo-Json -Compress -Depth 6
