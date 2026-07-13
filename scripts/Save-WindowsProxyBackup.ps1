[CmdletBinding()]
param(
    [string]$SettingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings',
    [string]$BackupPath = (Join-Path (Join-Path $PSScriptRoot '..') 'data\windows-proxy-backup.json')
)

$ErrorActionPreference = 'Stop'
$managedValues = @('AutoConfigURL', 'ProxyEnable', 'ProxyServer', 'ProxyOverride', 'AutoDetect')

if (Test-Path -LiteralPath $BackupPath) {
    Write-Output "Windows proxy backup already exists: $BackupPath"
    return
}

$settings = Get-ItemProperty -Path $SettingsPath
$values = [ordered]@{}
foreach ($name in $managedValues) {
    $property = $settings.PSObject.Properties[$name]
    $values[$name] = [ordered]@{
        exists = $null -ne $property
        value = if ($property) { $property.Value } else { $null }
    }
}

New-Item -ItemType Directory -Force -Path (Split-Path -Parent $BackupPath) | Out-Null
[ordered]@{
    schema_version = 1
    created_at_utc = [DateTime]::UtcNow.ToString('o')
    registry_path = $SettingsPath
    values = $values
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $BackupPath -Encoding utf8

Write-Output "Windows proxy backup saved: $BackupPath"
