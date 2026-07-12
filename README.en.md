# Windows Split PAC

[简体中文](README.md) | [English](README.en.md)

A lightweight Windows PAC split-routing tool. GFWList-matched sites and your explicit rules use an HTTP proxy; everything else stays direct. No SOCKS5, Clash/Mihomo, or hidden installer.

## Simple mode

Install [Python 3](https://www.python.org/downloads/windows/) first and select **Add Python to PATH** during setup. Then:

1. Download or clone this project.
2. Double-click `Start-WindowsSplitPAC.cmd`.
3. Choose `简体中文` or `English` in the top-right language selector.
4. Select **Prepare Python and genpac**.
5. Enter your Every Proxy **HTTP** endpoint, such as `192.168.1.100:8080`, without `http://`.
6. Select **Generate PAC and start**.
7. Select **Copy PAC URL and open Windows Settings**. In Windows Proxy settings, enable **Use setup script** and paste:

```text
http://127.0.0.1:8765/proxy.pac
```

The graphical interface never changes your Windows proxy setting automatically. You remain in control of that final step.

## Common tasks

- Proxy address changed: enter the new address and select **Generate PAC and start**. The Windows PAC URL stays the same.
- A site must use the proxy: select **Edit custom rules**, add `||example.com`, save, then generate again.

## How it works

```text
Browser -> local PAC URL
             |
             +-> GFWList or custom-rule match -> HTTP proxy
             |
             +-> everything else -> DIRECT
```

GFWList is a proxy rule list, not a perfect country classifier. Unmatched sites are direct. Override rules live in `rules/user-rules.txt`:

```text
||example.com     # force proxy
@@||example.com   # force direct
```

The local server reads the PAC file for every request, so regenerating the PAC normally does **not** require a server restart.

## Advanced mode

The Advanced tab exposes the same actions. You can also run the scripts directly:

```powershell
.\scripts\Install-Dependencies.ps1
.\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'
.\scripts\Start-PacServer.ps1
.\scripts\Stop-PacServer.ps1
.\scripts\Test-Package.ps1
```

Optional autostart is explicit and reversible:

```powershell
.\scripts\Install-Autostart.ps1
.\scripts\Uninstall-Autostart.ps1
```

It creates the `WindowsSplitPAC` logon task, which starts only the local server and never changes Windows proxy settings.

## Safety and troubleshooting

- The server listens only on `127.0.0.1`.
- Proxy addresses, rules, PAC output, PID files, and logs are ignored by Git.
- Start validates HTTP before reporting success; stop validates process ownership.
- If a domestic site remains slow, first check whether a rule is sending it through the proxy. If it is, latency usually comes from the phone/VPN/proxy exit chain rather than PAC generation.

## License

[MIT](LICENSE)
