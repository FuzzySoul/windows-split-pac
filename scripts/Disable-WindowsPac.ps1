[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$restored = & (Join-Path $PSScriptRoot 'Restore-WindowsProxyBackup.ps1')

if (-not $restored) {
    # Older installations may not have a backup. Remove only this PAC value and preserve manual settings.
    Remove-ItemProperty -Path $settingsPath -Name AutoConfigURL -ErrorAction SilentlyContinue
    Write-Warning 'No backup was found. Removed the PAC URL but preserved other proxy settings.'
}

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

[void][SplitPac.WinInet]::InternetSetOption([IntPtr]::Zero, 39, [IntPtr]::Zero, 0)
[void][SplitPac.WinInet]::InternetSetOption([IntPtr]::Zero, 37, [IntPtr]::Zero, 0)
Write-Output 'Windows PAC disabled and prior settings restored when available.'
