#requires -Version 5.1
<#
.SYNOPSIS
    Restart Microsoft Edge once so it re-reads the current system PAC.

.DESCRIPTION
    Method E: after rules are applied, Edge needs a full restart to drop its
    in-memory PAC cache and fetch the updated PAC. This script:
      1. stops every msedge.exe process
      2. relaunches Edge with --restore-last-session (restores previous tabs
         when the session data allows)
    Returns JSON {edge_stopped, relaunched}.
#>
[CmdletBinding()]
param(
    [switch]$SkipRelaunch
)

$ErrorActionPreference = 'Continue'
$edge = @(Get-Process msedge -ErrorAction SilentlyContinue)
$stopped = $false
if ($edge.Count -gt 0) {
    $edge | Stop-Process -Force -ErrorAction SilentlyContinue
    $stopped = $true
    Start-Sleep -Milliseconds 1200
}
if (-not $SkipRelaunch) {
    Start-Process -FilePath 'msedge.exe' -ArgumentList '--restore-last-session' -ErrorAction SilentlyContinue
}
[pscustomobject]@{
    edge_stopped = $stopped
    relaunched   = (-not $SkipRelaunch)
} | ConvertTo-Json -Compress
