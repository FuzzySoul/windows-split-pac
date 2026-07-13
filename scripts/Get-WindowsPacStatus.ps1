[CmdletBinding()]
param()

$settings = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$pacUrl = [string]$settings.AutoConfigURL

[pscustomobject]@{
    enabled = -not [string]::IsNullOrWhiteSpace($pacUrl)
    pac_url = $pacUrl
    manual_proxy_enabled = [bool]$settings.ProxyEnable
} | ConvertTo-Json -Compress
