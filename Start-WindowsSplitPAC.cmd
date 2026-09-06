@echo off
setlocal
cd /d "%~dp0"

set "BUNDLED=%~dp0app\windows-split-pac-gui.exe"
set "ROOT_EXE=%~dp0windows-split-pac-gui.exe"
set "RELEASE=%~dp0rust-gui\target\release\windows-split-pac-gui.exe"
set "CROSS=%~dp0rust-gui\target\x86_64-pc-windows-gnu\release\windows-split-pac-gui.exe"
set "DEPENDENCIES=%~dp0scripts\Install-Dependencies.ps1"

if exist "%DEPENDENCIES%" (
  powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%DEPENDENCIES%"
  if errorlevel 1 (
    echo [WindowsSplitPAC] Dependency setup failed. Read the error above.
    pause
    exit /b 1
  )
)

if exist "%BUNDLED%" goto run
if exist "%ROOT_EXE%" goto run
if exist "%RELEASE%" goto run
if exist "%CROSS%" goto run

where cargo >nul 2>nul
if errorlevel 1 (
  echo [WindowsSplitPAC] GUI binary not found and Rust is not installed.
  echo Download the portable package from GitHub Releases, or install Rust from https://rustup.rs.
  pause
  exit /b 1
)

echo [WindowsSplitPAC] Source checkout detected: building the GUI...
cargo build --release --manifest-path "%~dp0rust-gui\Cargo.toml"
if errorlevel 1 (
  echo [WindowsSplitPAC] Build failed. Please read the error above.
  pause
  exit /b 1
)
set "RELEASE=%~dp0rust-gui\target\release\windows-split-pac-gui.exe"

:run
if exist "%BUNDLED%" (
  start "" "%BUNDLED%"
  exit /b 0
)
if exist "%ROOT_EXE%" (
  start "" "%ROOT_EXE%"
  exit /b 0
)
if exist "%RELEASE%" (
  start "" "%RELEASE%"
  exit /b 0
)
if exist "%CROSS%" (
  start "" "%CROSS%"
  exit /b 0
)
echo [WindowsSplitPAC] Executable not found after build attempt.
pause
exit /b 1
