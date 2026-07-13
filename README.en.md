# Windows Split PAC

[简体中文](README.md) | [English](README.en.md)

A native Rust desktop control center for GFWList PAC split routing. Matching sites and custom rules use an HTTP proxy; all other traffic stays direct. No Clash, Mihomo, SOCKS5, or manual proxy-setting steps.

## Simple workflow

1. Download the `WindowsSplitPAC` artifact from **Actions -> Build Windows Package** and extract it anywhere.
2. Double-click `Start-WindowsSplitPAC.cmd`.
3. Choose `简体中文` or `English` in the top-right corner.
4. Enter the HTTP endpoint of Every Proxy, for example `192.168.1.100:8080`, without `http://`.
5. Enable **Start the local PAC service after sign-in** if you want autostart.
6. Click **Enable smart routing**. The app installs genpac, downloads GFWList, generates PAC, starts the local service, and applies the Windows automatic proxy-script setting.
7. Click **Run split test**. A successful result shows one `PROXY` decision and one `DIRECT` decision.

The active PAC URL is:

```text
http://127.0.0.1:8765/proxy.pac
```

**Stop and disable routing** clears the Windows PAC setting and stops the local server. The dashboard always shows both Windows and local-service state.

## Included capabilities

- One-click GFWList routing for HTTP proxies.
- Automatic Windows PAC application and refresh.
- Autostart in the simple dashboard.
- A real PAC decision test using Windows JScript.
- Chinese/English UI, custom-rule editor, and diagnostics.
- Local proxy addresses and settings remain under ignored `data/` files.

## Custom rules

Use the expandable custom-rules panel:

```text
||example.com     # force proxy
@@||example.com   # force direct
```

Save and enable smart routing again to regenerate PAC. GFWList is a proxy rule list, not a strict country database; unmatched sites are direct.

## Diagnostics

The old “professional mode” has been removed because the dashboard contains the normal workflow. The remaining diagnostic panel is only for rule editing and test output. Command-line maintenance is still available:

```powershell
.\scripts\Test-Package.ps1
.\scripts\Test-SplitRouting.ps1
.\scripts\Disable-WindowsPac.ps1
```

## Build and test

GitHub Actions uses clean Windows runners for a Rust quality gate (`fmt`, `clippy`, tests) and a separate PAC isolation test. The **Build Windows Package** workflow creates a portable ZIP artifact containing the native executable and helper scripts.

## License

[MIT](LICENSE)
