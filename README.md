# Windows Split PAC

> A small, inspectable Windows toolkit for sending only GFWList-matched sites through an HTTP proxy while leaving all other traffic direct.

`Windows Split PAC` uses [genpac](https://github.com/JinnLynn/genpac) to generate a standard PAC file and publishes it from `127.0.0.1`. It is deliberately boring: no SOCKS5, no Clash/Mihomo, no permanent system changes, and no hidden background installer.

## What it does

```text
Browser -> http://127.0.0.1:8765/proxy.pac
              |
              +-> matches GFWList or your forced-proxy rules -> HTTP proxy
              |
              +-> everything else -> DIRECT
```

Important: GFWList is a proxy rule list, not a perfect "domestic versus foreign" database. A site not matched by GFWList is sent direct. You can add your own overrides in `rules/user-rules.txt`.

## Safety properties

- Your proxy address and personal rules stay local. Generated files and runtime state are ignored by Git.
- The server listens only on `127.0.0.1`, never on the LAN.
- `Start-PacServer.ps1` verifies HTTP service before reporting success.
- `Stop-PacServer.ps1` verifies its PID belongs to this toolkit before stopping it.
- The PAC file is read on every request, so regenerating it does **not** require restarting the PAC server.
- Nothing changes the Windows proxy setting automatically. You decide when to paste the local PAC URL into Windows Settings.

## Requirements

- Windows 10/11
- Python 3.10 or newer, with `pip`
- An HTTP proxy reachable from the PC, for example a phone running Every Proxy
- PowerShell 5.1 or PowerShell 7

## Quick start

Open PowerShell in the cloned repository and run:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\scripts\Install-Dependencies.ps1
notepad .\rules\user-rules.txt
.\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'
.\scripts\Start-PacServer.ps1
```

Replace `192.168.1.100:8080` with your own **HTTP** proxy address. The command produces `dist\proxy.pac` and starts a local server at:

```text
http://127.0.0.1:8765/proxy.pac
```

Then open **Windows Settings -> Network & Internet -> Proxy -> Use setup script**, enable it, and paste the URL above. Do not also enable the Windows manual proxy switch; PAC is the routing decision-maker.

## Add a site that must use the proxy

Edit `rules/user-rules.txt` and add one rule per line:

```text
||example.com
```

Then rebuild:

```powershell
.\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'
```

The running server serves the new file immediately. You may need to refresh the browser or wait for its PAC cache to expire.

To force a site to stay direct, use an exception rule:

```text
@@||example.com
```

The rule format is the standard Adblock Plus / GFWList syntax. User rules take priority over GFWList.

## Daily commands

```powershell
# Regenerate after changing proxy address, rules, or when refreshing GFWList.
.\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'

# Start or stop the local PAC server.
.\scripts\Start-PacServer.ps1
.\scripts\Stop-PacServer.ps1

# Check that the PAC URL responds.
Invoke-WebRequest http://127.0.0.1:8765/proxy.pac -UseBasicParsing
```

## Optional autostart

If you want the local PAC server to start when you sign in, after generating a PAC file run:

```powershell
.\scripts\Install-Autostart.ps1
```

This creates a visible Scheduled Task named `WindowsSplitPAC`; it only starts the local PAC server and does not touch Windows proxy settings. Remove it with:

```powershell
.\scripts\Uninstall-Autostart.ps1
```

## Test the package in isolation

The test never changes Windows proxy settings and never uses your actual proxy. It generates a temporary PAC file using the reserved documentation IP `192.0.2.10`, launches an isolated local server on a random port, verifies the PAC content, MIME type, and health endpoint, then cleans everything up.

```powershell
.\scripts\Test-Package.ps1
```

The same test runs on GitHub Actions for every push and pull request.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| `genpac is not available` | Run `.\scripts\Install-Dependencies.ps1`. |
| PAC URL does not open | Run `.\scripts\Start-PacServer.ps1`, then open `http://127.0.0.1:8765/healthz`. |
| A domestic site is still slow | Verify whether it is matched by a rule. If it is proxied, the delay usually comes from the upstream phone/VPN/proxy chain, not PAC generation. |
| A site should use the proxy but does not | Add `||domain.example` to `rules/user-rules.txt`, then rebuild. |
| Proxy address changed | Re-run `Build-Pac.ps1` with the new address; do not change the server URL. |

## Project layout

```text
scripts/     Install, generate, start, stop, test, and optional autostart
rules/       Your human-editable custom proxy rules
src/         Tiny standard-library PAC HTTP server
dist/        Generated PAC output (local only, ignored by Git)
.runtime/    PID and logs for the managed local server (local only, ignored by Git)
```

## License

[MIT](LICENSE)
