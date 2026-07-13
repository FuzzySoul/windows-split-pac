[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$settingsPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
Remove-ItemProperty -Path $settingsPath -Name AutoConfigURL -ErrorAction SilentlyContinue
Set-ItemProperty -Path $settingsPath -Name ProxyEnable -Value 0

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
Write-Output 'Windows PAC disabled.'
