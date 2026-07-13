@echo off
setlocal
set "APP=%~dp0rust-gui\target\release\windows-split-pac-gui.exe"
if exist "%APP%" (
  start "Windows Split PAC" "%APP%"
  exit /b 0
)

where cargo >nul 2>nul
if errorlevel 1 (
  echo Rust GUI has not been built yet.
  echo Download the Windows package from GitHub Releases, or install Rust and run this file again.
  pause
  exit /b 1
)

cargo run --release --manifest-path "%~dp0rust-gui\Cargo.toml"
