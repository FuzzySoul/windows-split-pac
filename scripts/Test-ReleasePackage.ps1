#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$PackageDir,

    [switch]$SkipRuntimeTest
)

$ErrorActionPreference = 'Stop'
$package = (Resolve-Path -LiteralPath $PackageDir).Path

$required = @(
    'Start-WindowsSplitPAC.cmd',
    'requirements.txt',
    'app\windows-split-pac-gui.exe',
    'scripts\Install-Dependencies.ps1',
    'scripts\Build-Pac.ps1',
    'scripts\Test-Package.ps1',
    'src\pac_server.py',
    'rules\user-rules.txt'
)
foreach ($relative in $required) {
    $path = Join-Path $package $relative
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Portable package is missing required file: $relative"
    }
}

if (Test-Path -LiteralPath (Join-Path $package 'windows-split-pac-gui.exe')) {
    throw 'Portable package contains a stale root-level GUI executable; the canonical binary location is app\windows-split-pac-gui.exe.'
}

$launcher = Get-Content -LiteralPath (Join-Path $package 'Start-WindowsSplitPAC.cmd') -Raw
if ($launcher -notmatch 'app\\windows-split-pac-gui\.exe') {
    throw 'Launcher does not reference the canonical app\windows-split-pac-gui.exe binary.'
}

$requirements = (Get-Content -LiteralPath (Join-Path $package 'requirements.txt') -Raw).Trim()
if ($requirements -ne 'genpac==3.0.1') {
    throw "Unexpected dependency lock: '$requirements'"
}

Get-ChildItem -LiteralPath (Join-Path $package 'scripts') -Filter '*.ps1' -File | ForEach-Object {
    [ScriptBlock]::Create((Get-Content -LiteralPath $_.FullName -Raw)) | Out-Null
}

if (-not $SkipRuntimeTest) {
    & (Join-Path $package 'scripts\Install-Dependencies.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Dependency bootstrap failed inside the extracted portable package.'
    }

    & (Join-Path $package 'scripts\Test-Package.ps1')
    if ($LASTEXITCODE -ne 0) {
        throw 'Runtime package test failed inside the extracted portable package.'
    }
}

Write-Output 'Portable release package validation passed.'
