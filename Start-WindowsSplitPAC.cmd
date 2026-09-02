@echo off
setlocal
cd /d "%~dp0"

set "BUNDLED=%~dp0app\windows-split-pac-gui.exe"
set "RELEASE=%~dp0rust-gui\target\release\windows-split-pac-gui.exe"
set "CROSS=%~dp0rust-gui\target\x86_64-pc-windows-gnu\release\windows-split-pac-gui.exe"

if exist "%BUNDLED%" goto run
if exist "%RELEASE%" goto run
if exist "%CROSS%" goto run

where cargo >nul 2>nul
if errorlevel 1 (
  echo [WindowsSplitPAC] GUI binary not found and Rust is not installed.
  echo Please install Rust from https://rustup.rs then run this file again.
  pause
  exit /b 1
)

echo [WindowsSplitPAC] First run: building the GUI, this can take a few minutes...
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
