[CmdletBinding()]
param(
    [string]$BackupPath = (Join-Path (Join-Path $PSScriptRoot '..') 'data\windows-proxy-backup.json')
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $BackupPath)) {
    Write-Output 'No Windows proxy backup is available.'
    return $false
}

$backup = Get-Content -LiteralPath $BackupPath -Raw | ConvertFrom-Json
if ($backup.schema_version -ne 1 -or -not $backup.registry_path -or -not $backup.values) {
    throw "Windows proxy backup is invalid: $BackupPath"
}

foreach ($property in $backup.values.PSObject.Properties) {
    $name = $property.Name
    $entry = $property.Value
    if ($entry.exists) {
        Set-ItemProperty -Path $backup.registry_path -Name $name -Value $entry.value
    } else {
        Remove-ItemProperty -Path $backup.registry_path -Name $name -ErrorAction SilentlyContinue
    }
}

Remove-Item -LiteralPath $BackupPath -Force
Write-Output 'Original Windows proxy settings restored.'
return $true
