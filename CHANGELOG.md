# Changelog

All notable changes to Windows Split PAC are documented here.

## [Unreleased]

## [0.3.4] - 2026-09-06

### Fixed

- Repaired the portable release layout so `Start-WindowsSplitPAC.cmd` launches the packaged GUI from `app\windows-split-pac-gui.exe` instead of falling through to a broken source-build path.
- Added `requirements.txt` to portable releases and pinned the tested PAC generator to `genpac==3.0.1`.
- Made dependency bootstrap idempotent: an already-correct genpac installation is reused, while missing or mismatched versions are installed from the pinned requirements file.
- Removed the generated GUI executable from source control to prevent the checked-in binary from drifting behind the Rust source.

### Changed

- Added a single `Build-ReleasePackage.ps1` path for assembling ZIP releases and SHA-256 checksums.
- CI now builds, extracts, and tests the actual portable ZIP instead of validating only the source checkout.
- GitHub Releases are now published only from a successful `main` Continuous Integration run. The CD workflow tags and publishes the exact tested commit, while manual runs remain preview builds only.

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
