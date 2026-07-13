# Security Policy

## Supported versions

Security fixes are applied to the latest release on the `main` branch.

## Reporting a vulnerability

Please use GitHub's private security advisory flow for this repository. Do not open a public issue for a vulnerability and do not include proxy addresses, PAC files, cookies, passwords, or private network information.

## Privacy and local data

Windows Split PAC stores its local UI settings and a temporary backup of the current user's proxy configuration under `data/`. That directory is ignored by Git. The backup is deleted after a successful restore. The project does not collect telemetry.

## Trust boundary

The tool runs local PowerShell scripts, starts a loopback PAC server, and writes only to the current user's Internet Settings registry key when smart routing is enabled. Review the source before use and verify release checksums before running a downloaded package.
