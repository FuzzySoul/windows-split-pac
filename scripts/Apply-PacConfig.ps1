#requires -Version 5.1
<#
.SYNOPSIS
    One-click atomic "apply" for the PAC split-routing product (engine layer).

.DESCRIPTION
    Turns "edit rules -> regenerate PAC -> (re)start service -> point Windows at
    the PAC -> refresh WinINET -> verify" into ONE step, with rollback on failure.

    SAFETY: the script is READ-ONLY by default. Without -Apply it only prints the
    plan (dry-run) and reports what it WOULD do. Nothing is written, nothing is
    started/stopped/restarted. Pass -Apply explicitly to execute.

    Before regenerating, it backs up BOTH the rules file and the current PAC, so a
    failed generation can be rolled back byte-for-byte. genpac's GFWList fetch gets
    the LAN proxy via process env (restored afterwards).

    Reuses the existing tooling:
      Build-Pac.ps1 (genpac)          -> regenerate the PAC
      Enable-WindowsPac.ps1           -> back up, set AutoConfigURL, refresh WinINET
      Get-ServiceIdentity.ps1         -> detect who is actually serving the port
    plus an inline service step that reuses/rewrites the pid file from the REAL
    listener (fixing stale pid files regardless of which script started it).

.PARAMETER ProxyAddress
    Upstream proxy host:port, e.g. "10.10.10.19:8080". If omitted it is inferred
    from the currently served PAC (read-only). Also used as the LAN proxy for the
    genpac GFWList fetch when no HTTP(S)_PROXY env is already set.

.PARAMETER RulesFile
    Rule file read by genpac (single source of truth). Default C:\proxy\user-rules.txt.

.PARAMETER PacFile
    Output PAC. Default C:\proxy\proxy.pac.

.PARAMETER RunDir
    Directory for the runtime pid file. Default C:\proxy.

.PARAMETER ServiceScript
    Python script to start when nothing is serving the port yet. Defaults to this
    repo's src\pac_server.py (the product engine). Point at the real
    C:\Users\...\.hermes\serve_pac.py to take over that service instead.

.PARAMETER GfwListUrl
    readonly override of the GFWList source for regeneration (default GFWList).

.PARAMETER Port
    Local PAC port (default 8765).

.PARAMETER Apply
    Execute for real. Omit to only dry-run.

.EXAMPLE
    # Dry-run against the live system (read-only):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-PacConfig.ps1

.EXAMPLE
    # Execute against the live system (will write registry/files, but never kills
    # an existing live PAC listener - it reuses it):
    powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Apply-PacConfig.ps1 -Apply
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [string]$ProxyAddress,
    [string]$RulesFile = 'C:\proxy\user-rules.txt',
    [string]$PacFile = 'C:\proxy\proxy.pac',
    [string]$RunDir = 'C:\proxy',
    [string]$ServiceScript = '',
    [string]$GfwListUrl = 'https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt',
    [int]$Port = 8765,
    [switch]$Apply,
    [switch]$SkipWindows,
    [switch]$SkipGenerate,
    [string]$ResultFile = ''
)

$ErrorActionPreference = 'Stop'
[System.Net.WebRequest]::DefaultWebProxy = $null  # local checks never go through a proxy

# All human-readable progress goes to STDERR so stdout stays pure JSON for the GUI/Rust engine.
function Write-Log([string]$msg) {
    [Console]::Error.WriteLine($msg)
}

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$dryRun = -not $Apply

# ---- result object (consumed by the Rust engine / surfaced in the GUI) ----
$result = [ordered]@{
    applied               = -not $dryRun
    steps                 = @()
    errors                = @()
    service               = $null
    pac_ok                = $false
    healthz_ok            = $false
    windows_using_our_pac = $false
    rules_drift           = $false
}

$completedSteps = [System.Collections.Generic.List[string]]::new()
$serviceStarted = $false
$windowsEnabled = $false
$rulesBackup = $null
$pacBackup = $null
$generatedPac = $false
$pidFile = Join-Path $RunDir 'pac-server.pid'

# ---- rollback on failure (only for a REAL apply that touched something) ----
trap {
    if (-not $dryRun -and $completedSteps.Count -gt 0) {
        Write-Log '[ROLLBACK] Undoing applied steps...'
        if ($windowsEnabled) {
            try { & (Join-Path $PSScriptRoot 'Disable-WindowsPac.ps1') *> $null } catch {}
        }
        if ($serviceStarted) {
            try {
                if (Test-Path -LiteralPath $pidFile) {
                    $p = (Get-Content -LiteralPath $pidFile -TotalCount 1).Trim()
                    if ($p -and (Get-Process -Id ([int]$p) -ErrorAction SilentlyContinue)) {
                        Stop-Process -Id ([int]$p) -Force
                        Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
                    }
                }
            } catch {}
        }
        if ($rulesBackup -and (Test-Path -LiteralPath $rulesBackup)) {
            try { Copy-Item -LiteralPath $rulesBackup -Destination $RulesFile -Force } catch {}
        }
        if ($pacBackup -and (Test-Path -LiteralPath $pacBackup)) {
            try { Copy-Item -LiteralPath $pacBackup -Destination $PacFile -Force } catch {}
        }
    }
    # Surface the real failure to the engine/GUI: the ResultFile is written
    # on failure too, so "Apply-PacConfig.ps1 failed (see PowerShell errors)"
    # can be replaced by the actual error in the UI.
    $result.applied = $false
    # Step-level errors (with step prefix) are already recorded; only add the
    # bare message when the failure happened outside Invoke-SafeStep.
    if ($result.errors.Count -eq 0) {
        $result.errors += $_.Exception.Message
    }
    if ($ResultFile) {
        try {
            $failJson = [pscustomobject]$result | ConvertTo-Json -Compress -Depth 6
            Set-Content -LiteralPath $ResultFile -Value $failJson -Encoding ascii
        } catch {}
    }
    Write-Error "Apply-PacConfig failed: $($_.Exception.Message)"
    exit 1
}

function Write-Step([string]$msg) {
    if ($dryRun) { Write-Log "[DRY-RUN] $msg" } else { Write-Log "[APPLY] $msg" }
}
function Add-Step([string]$name) {
    $result.steps += $name
    $completedSteps.Add($name)
}

function Invoke-SafeStep {
    param([string]$Name, [scriptblock]$Body)
    if ($dryRun) {
        Write-Step "would run step: $Name"
        $result.steps += "planned:$Name"
        return
    }
    try {
        & $Body
        Add-Step "ok:$Name"
    } catch {
        $result.errors += "$Name`: $($_.Exception.Message)"
        throw
    }
}

# --------------------------------------------------------------------------
# 0. Read-only snapshot: who is serving the port today, and what rules exist
# --------------------------------------------------------------------------
$identityScript = Join-Path $PSScriptRoot 'Get-ServiceIdentity.ps1'
$identity = & $identityScript -PacFile $PacFile -OnlineRulesFile $RulesFile -Port $Port | ConvertFrom-Json

# Rule drift (online rules vs repo default), surfaced for the GUI "advanced" view.
$ruleDiff = $identity.rule_file_diff
$result.rules_drift = -not [bool]$ruleDiff.in_sync

# Preflight (read-only): what does a real apply need?
$genpacOk = $false
foreach ($candidate in @('python', 'py')) {
    try {
        & $candidate -m genpac --version *> $null
        if ($LASTEXITCODE -eq 0) { $genpacOk = $true; break }
    } catch { continue }
}
$rulesPresent = Test-Path -LiteralPath $RulesFile
Write-Log ("Preflight: rules={0} ({1})  genpac={2}  live-service={3} (pid {4})  rules-drift={5}" -f `
    $rulesPresent, $RulesFile, $genpacOk, $identity.server_kind, $identity.pid, $result.rules_drift)
if (-not $rulesPresent) { Write-Log "WARNING: rules file missing -> $RulesFile" }
if (-not $genpacOk)     { Write-Log 'WARNING: genpac not found; install with .\scripts\Install-Dependencies.ps1 (apply will fail today).' }

# Infer the upstream proxy from the currently served PAC when not given.
if (-not $ProxyAddress) {
    if ($identity.pac_proxy -match 'PROXY\s+(.+)') {
        $ProxyAddress = $Matches[1].Trim()
        Write-Log "Inferred upstream proxy from served PAC: $ProxyAddress"
    } else {
        $ProxyAddress = ''
    }
}
if (-not $ProxyAddress) {
    throw 'No -ProxyAddress given and none could be inferred from the served PAC.'
}

$pacUrl = "http://127.0.0.1:$Port/proxy.pac"

# --------------------------------------------------------------------------
# 1. Backup rules AND current PAC (byte-for-byte rollback insurance)
# --------------------------------------------------------------------------
Invoke-SafeStep 'backup' {
    $rulesBackup = "$PacFile.rules.bak"
    $pacBackup = "$PacFile.genpac.bak"
    if (Test-Path -LiteralPath $RulesFile) {
        Copy-Item -LiteralPath $RulesFile -Destination $rulesBackup -Force
        Write-Step "Backed up rules -> $rulesBackup"
    }
    if (Test-Path -LiteralPath $PacFile) {
        Copy-Item -LiteralPath $PacFile -Destination $pacBackup -Force
        Write-Step "Backed up current PAC -> $pacBackup"
    }
}

# --------------------------------------------------------------------------
# 2. Regenerate PAC (genpac) into the live path, LAN proxy for the GFWList fetch
# --------------------------------------------------------------------------
if ($SkipGenerate) {
    $result.steps += 'skipped:generate-pac'
    Write-Log '[SKIP] PAC generation skipped (-SkipGenerate); expecting an existing PAC file.'
} else {
Invoke-SafeStep 'generate-pac' {
    $pacDir = Split-Path -Parent $PacFile
    New-Item -ItemType Directory -Force -Path $pacDir | Out-Null

    # Point genpac's GFWList fetch at the LAN proxy (only when not already set);
    # restore the process env afterwards.
    $savedProxyEnv = @{}
    if (-not $env:HTTP_PROXY -and -not $env:http_proxy) {
        foreach ($n in @('HTTP_PROXY', 'HTTPS_PROXY', 'http_proxy', 'https_proxy')) {
            $savedProxyEnv[$n] = [Environment]::GetEnvironmentVariable($n)
            [Environment]::SetEnvironmentVariable($n, "http://$ProxyAddress")
        }
    }
    try {
        & (Join-Path $PSScriptRoot 'Build-Pac.ps1') `
            -ProxyAddress $ProxyAddress `
            -RulesFile $RulesFile `
            -OutputPath $PacFile `
            -GfwListUrl $GfwListUrl
    } finally {
        foreach ($n in $savedProxyEnv.Keys) { [Environment]::SetEnvironmentVariable($n, $savedProxyEnv[$n]) }
    }
    $script:generatedPac = $true
}
}
# --------------------------------------------------------------------------
# 3. Service: reuse the real listener, or start the engine server
# --------------------------------------------------------------------------
Invoke-SafeStep 'service' {
    if ($identity.server_running -and $identity.pid) {
        # Reuse whatever is actually listening/responding, and REWRITE the pid file
        # from the real listener — this fixes stale pid files without killing
        # anything.
        $realPid = [int]$identity.pid
        Set-Content -LiteralPath $pidFile -Value $realPid -Encoding ascii
        $result.service = [ordered]@{ running = $true; pid = $realPid; kind = $identity.server_kind }
        Write-Step "Reusing live server on :$Port (PID $realPid, kind $($identity.server_kind)); pid file rewritten from reality."
    } else {
        if ($identity.pid) {
            throw "Port :$Port is occupied by an unknown process (PID $($identity.pid)); refusing to start the PAC server over it."
        }
        if (-not $ServiceScript) {
            $ServiceScript = Join-Path $root 'src\pac_server.py'
        }
        if (-not (Test-Path -LiteralPath $ServiceScript)) {
            throw "Service script not found: $ServiceScript"
        }
        $python = $null
        foreach ($candidate in @('python', 'py')) {
            try {
                $pyPath = & $candidate -c 'import sys; print(sys.executable)' 2>$null
                if ($LASTEXITCODE -eq 0 -and $pyPath) { $python = ($pyPath | Select-Object -Last 1).Trim(); break }
            } catch { continue }
        }
        if (-not $python) { throw 'Python 3 not found; cannot start the PAC server.' }
        New-Item -ItemType Directory -Force -Path $RunDir | Out-Null
        $resolvedPac = (Resolve-Path $PacFile).Path
        $proc = Start-Process -FilePath $python `
            -ArgumentList @("`"$ServiceScript`"", '--pac-file', "`"$resolvedPac`"", '--port', $Port, '--pid-file', "`"$pidFile`"") `
            -WindowStyle Hidden -RedirectStandardOutput (Join-Path $RunDir 'pac-server.stdout.log') `
            -RedirectStandardError (Join-Path $RunDir 'pac-server.stderr.log') -PassThru
        Start-Sleep -Milliseconds 700
        try {
            $resp = Invoke-WebRequest -UseBasicParsing -Uri $pacUrl -TimeoutSec 5
            if ($resp.StatusCode -ne 200) { throw "HTTP $($resp.StatusCode)" }
        } catch {
            if (Get-Process -Id $proc.Id -ErrorAction SilentlyContinue) { Stop-Process -Id $proc.Id -Force }
            Remove-Item -LiteralPath $pidFile -Force -ErrorAction SilentlyContinue
            throw "Server failed to start: $($_.Exception.Message)"
        }
        $script:serviceStarted = $true
        $result.service = [ordered]@{ running = $true; pid = $proc.Id; kind = 'managed (product engine)'; }
        Write-Step "Started product PAC server (PID $($proc.Id)) serving $resolvedPac"
    }
}

# --------------------------------------------------------------------------
# 4. Enable on Windows (+ backup + WinINET refresh)
# --------------------------------------------------------------------------
if ($SkipWindows) {
    $result.steps += 'skipped:enable-windows'
    Write-Log '[SKIP] Windows registry enable skipped (-SkipWindows); no HKCU change.'
} else {
Invoke-SafeStep 'enable-windows' {
    & (Join-Path $PSScriptRoot 'Enable-WindowsPac.ps1') -PacUrl $pacUrl
    $script:windowsEnabled = $true
}
}

# --------------------------------------------------------------------------
# 5. Verify: PAC serves, /healthz responds, registry points at us
# --------------------------------------------------------------------------
Invoke-SafeStep 'verify' {
    $pac = Invoke-WebRequest -UseBasicParsing -Uri $pacUrl -TimeoutSec 5
    $result.pac_ok = ($pac.StatusCode -eq 200)
    $healthzUrl = "http://127.0.0.1:$Port/healthz"
    try {
        $hz = Invoke-WebRequest -UseBasicParsing -Uri $healthzUrl -TimeoutSec 3
        $result.healthz_ok = ($hz.StatusCode -eq 200)
    } catch { $result.healthz_ok = $false }

    $s = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
    $result.windows_using_our_pac = ([string]$s.AutoConfigURL) -match [regex]::Escape("$pacUrl")

    if (-not $result.pac_ok) { throw 'PAC endpoint did not verify after apply.' }
}

# --------------------------------------------------------------------------
# finalize
# --------------------------------------------------------------------------
if ($dryRun) {
    Write-Log ''
    Write-Log ('Dry-run complete. To actually apply, re-run with -Apply.').ToUpper()
} else {
    Write-Log ''
    Write-Log 'Apply complete.'
}
$json = [pscustomobject]$result | ConvertTo-Json -Compress -Depth 6
if ($ResultFile) {
    # Used by the Rust engine: avoids stdout-pipe hangs from background services.
    Set-Content -LiteralPath $ResultFile -Value $json -Encoding ascii
}
$json
