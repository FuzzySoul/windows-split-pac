[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$testKey = "HKCU:\Software\WindowsSplitPAC\Tests\$([Guid]::NewGuid().ToString('N'))"
$backupPath = Join-Path ([System.IO.Path]::GetTempPath()) ("windows-split-pac-backup-" + [Guid]::NewGuid().ToString('N') + '.json')

function Assert-Equal {
    param([object]$Actual, [object]$Expected, [string]$Message)
    if ($Actual -ne $Expected) { throw "$Message. Expected '$Expected', received '$Actual'." }
}

try {
    New-Item -Path $testKey -Force | Out-Null
    New-ItemProperty -Path $testKey -Name AutoConfigURL -Value 'https://previous.example/proxy.pac' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $testKey -Name ProxyEnable -Value 1 -PropertyType DWord -Force | Out-Null
    New-ItemProperty -Path $testKey -Name ProxyServer -Value '127.0.0.1:7890' -PropertyType String -Force | Out-Null
    New-ItemProperty -Path $testKey -Name ProxyOverride -Value '<local>' -PropertyType String -Force | Out-Null

    & (Join-Path $PSScriptRoot 'Save-WindowsProxyBackup.ps1') -SettingsPath $testKey -BackupPath $backupPath | Out-Null

    Set-ItemProperty -Path $testKey -Name AutoConfigURL -Value 'http://127.0.0.1:8765/proxy.pac'
    Set-ItemProperty -Path $testKey -Name ProxyEnable -Value 0
    Remove-ItemProperty -Path $testKey -Name ProxyServer
    Set-ItemProperty -Path $testKey -Name ProxyOverride -Value ''
    New-ItemProperty -Path $testKey -Name AutoDetect -Value 0 -PropertyType DWord -Force | Out-Null

    & (Join-Path $PSScriptRoot 'Restore-WindowsProxyBackup.ps1') -BackupPath $backupPath | Out-Null

    $restored = Get-ItemProperty -Path $testKey
    Assert-Equal $restored.AutoConfigURL 'https://previous.example/proxy.pac' 'PAC URL was not restored'
    Assert-Equal $restored.ProxyEnable 1 'ProxyEnable was not restored'
    Assert-Equal $restored.ProxyServer '127.0.0.1:7890' 'ProxyServer was not restored'
    Assert-Equal $restored.ProxyOverride '<local>' 'ProxyOverride was not restored'
    if ($null -ne $restored.PSObject.Properties['AutoDetect']) { throw 'AutoDetect should have been removed during restore.' }
    if (Test-Path -LiteralPath $backupPath) { throw 'Backup file should be removed after restore.' }

    Write-Output 'Windows proxy backup isolation test passed.'
} finally {
    Remove-Item -Path $testKey -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
}
