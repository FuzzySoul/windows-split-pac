[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https?://127\.0\.0\.1:\d+/proxy\.pac$')]
    [string]$PacUrl
)

$ErrorActionPreference = 'Stop'
$settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'

# Preserve the user's settings once, so disabling this tool can restore them exactly.
& (Join-Path $PSScriptRoot 'Save-WindowsProxyBackup.ps1')

Set-ItemProperty -Path $settingsPath -Name AutoConfigURL -Value $PacUrl
Set-ItemProperty -Path $settingsPath -Name ProxyEnable -Value 0
Remove-ItemProperty -Path $settingsPath -Name ProxyServer -ErrorAction SilentlyContinue

if (-not ('SplitPac.WinInet' -as [type])) {
    Add-Type @'
using System;
using System.Runtime.InteropServices;
namespace SplitPac {
    public static class WinInet {
        [DllImport("wininet.dll", SetLastError = true)]
        public static extern bool InternetSetOption(IntPtr hInternet, int dwOption, IntPtr lpBuffer, int dwBufferLength);
    }
}
'@
}

# Ask WinINet applications to reload the current-user proxy configuration.
[void][SplitPac.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
[void][SplitPac.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
Write-Output "Windows PAC enabled: $PacUrl"
