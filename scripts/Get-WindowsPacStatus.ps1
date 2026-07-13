[CmdletBinding()]
param()

$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$backupPath = Join-Path $root 'data\windows-proxy-backup.json'
$settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$pacUrl = [string]$settings.AutoConfigURL

[pscustomobject]@{
    enabled = -not [string]::IsNullOrWhiteSpace($pacUrl)
    pac_url = $pacUrl
    manual_proxy_enabled = [bool]$settings.ProxyEnable
    backup_available = Test-Path -LiteralPath $backupPath
} | ConvertTo-Json -Compress
