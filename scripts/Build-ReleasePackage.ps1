#requires -Version 5.1
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExecutablePath,

    [string]$OutputRoot = (Join-Path (Split-Path -Parent $PSScriptRoot) 'release'),

    [string]$PackageName = 'WindowsSplitPAC'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$exe = (Resolve-Path -LiteralPath $ExecutablePath).Path
$output = [System.IO.Path]::GetFullPath($OutputRoot)
$package = Join-Path $output $PackageName
$zip = Join-Path $output "$PackageName.zip"
$checksum = "$zip.sha256"

if (Test-Path -LiteralPath $package) {
    Remove-Item -LiteralPath $package -Recurse -Force
}
if (Test-Path -LiteralPath $zip) {
    Remove-Item -LiteralPath $zip -Force
}
if (Test-Path -LiteralPath $checksum) {
    Remove-Item -LiteralPath $checksum -Force
}

New-Item -ItemType Directory -Force -Path (Join-Path $package 'app') | Out-Null
Copy-Item -LiteralPath $exe -Destination (Join-Path $package 'app\windows-split-pac-gui.exe') -Force

$rootFiles = @(
    'Start-WindowsSplitPAC.cmd',
    'README.md',
    'README.en.md',
    'LICENSE',
    'CHANGELOG.md',
    'SECURITY.md',
    'THIRD_PARTY_NOTICES.md',
    'requirements.txt'
)
foreach ($relative in $rootFiles) {
    $source = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Release input is missing: $relative"
    }
    Copy-Item -LiteralPath $source -Destination $package -Force
}

foreach ($directory in @('assets', 'scripts', 'rules', 'src')) {
    $source = Join-Path $root $directory
    if (-not (Test-Path -LiteralPath $source)) {
        throw "Release directory is missing: $directory"
    }
    Copy-Item -LiteralPath $source -Destination $package -Recurse -Force
}

New-Item -ItemType Directory -Force -Path $output | Out-Null
Compress-Archive -Path (Join-Path $package '*') -DestinationPath $zip -Force

$hash = (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant()
"$hash *$PackageName.zip" | Set-Content -LiteralPath $checksum -Encoding ascii -NoNewline

[pscustomobject]@{
    package_dir = $package
    zip = $zip
    checksum = $checksum
    sha256 = $hash
} | ConvertTo-Json -Compress
