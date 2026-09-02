# Changelog

All notable changes to Windows Split PAC are documented here.

## [Unreleased]

## [0.3.3] - 2026-09-02

### Fixed

- The GUI now shows the real error when an apply fails (e.g. missing genpac) instead of the generic "Apply-PacConfig.ps1 failed (see PowerShell errors)" message: Apply-PacConfig.ps1 writes its structured result on failure, and the engine reads it (with a captured PowerShell stderr tail as fallback).
- Fixed a Windows-only unit-test failure in path resolution assertions.

## [0.3.2] - 2026-07-13

### Fixed

- Embedded Noto Sans SC in the native GUI so Simplified Chinese renders correctly in portable releases.

## [0.3.1] - 2026-07-13

### Changed

- Updated the release artifact uploader to the current GitHub Actions runtime.

## [0.3.0] - 2026-07-13

### Added

- Backup and restore of the current user's Windows PAC and proxy settings.
- Portable-package SHA-256 checksum and tag-triggered GitHub Release publishing.
- Community health files, dependency update configuration, and an architecture overview.

### Changed

- The desktop dashboard now displays whether a proxy-settings backup is available.
- Enable failures now stop the local PAC server, and autostart failures restore the previous Windows settings.

## [0.2.0] - 2026-07-13

### Added

- Native Rust desktop control center with Chinese and English UI.
- One-click Windows PAC configuration, autostart, custom rules, and PAC decision testing.
