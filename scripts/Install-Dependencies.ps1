[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Get-PythonCommand {
    foreach ($candidate in @('py', 'python')) {
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
& $python -m pip --version
if ($LASTEXITCODE -ne 0) {
    throw 'pip is unavailable for this Python installation.'
}

& $python -m pip install --user --upgrade -r (Join-Path $PSScriptRoot '..\requirements.txt')
if ($LASTEXITCODE -ne 0) {
    throw 'Failed to install genpac.'
}

& $python -m genpac --version
if ($LASTEXITCODE -ne 0) {
    throw 'genpac was installed but could not be started.'
}

Write-Output 'Dependencies are ready.'
