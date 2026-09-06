[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$requiredGenpacVersion = '3.0.1'

function Get-PythonCommand {
    foreach ($candidate in @('python', 'py')) {
        try {
            & $candidate --version *> $null
            if ($LASTEXITCODE -eq 0) {
                return $candidate
            }
        } catch {
            continue
        }
    }

    throw 'Python 3 was not found. Install it from https://www.python.org/downloads/windows/ and enable "Add Python to PATH".'
}

$python = Get-PythonCommand
& $python -m pip --version *> $null
if ($LASTEXITCODE -ne 0) {
    throw 'pip is unavailable for this Python installation.'
}

$currentVersion = $null
try {
    $currentVersion = (& $python -c "import importlib.metadata as m; print(m.version('genpac'))" 2>$null | Select-Object -Last 1).Trim()
} catch {
    $currentVersion = $null
}

if ($currentVersion -eq $requiredGenpacVersion) {
    Write-Output "Dependencies are ready (genpac $requiredGenpacVersion)."
    return
}

$requirements = Join-Path $PSScriptRoot '..\requirements.txt'
if (-not (Test-Path -LiteralPath $requirements)) {
    throw "requirements.txt is missing: $requirements"
}

Write-Output "Installing tested PAC dependency set (genpac $requiredGenpacVersion)..."
& $python -m pip install --disable-pip-version-check --user -r $requirements
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install genpac.'
}

$installedVersion = (& $python -c "import importlib.metadata as m; print(m.version('genpac'))" 2>$null | Select-Object -Last 1).Trim()
if ($installedVersion -ne $requiredGenpacVersion) {
    throw "genpac version verification failed. Expected $requiredGenpacVersion, got $installedVersion."
}

Write-Output "Dependencies are ready (genpac $installedVersion)."
