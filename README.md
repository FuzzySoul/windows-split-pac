# Windows Split PAC

[简体中文](README.md) | [English](README.en.md)

一个原生 Rust 桌面控制台：用 GFWList 和自定义规则把需要访问的站点送到 HTTP 代理，其余流量保持直连。它不需要 Clash、Mihomo 或 SOCKS5。

## 简单操作

1. 在 GitHub 的 **Actions -> Build Windows Package** 下载 `WindowsSplitPAC` 压缩包，解压到任意目录。
2. 双击 `Start-WindowsSplitPAC.cmd` 打开 Rust 图形界面。
3. 右上角选择 `简体中文` 或 `English`。
4. 输入手机 Every Proxy 的 HTTP 地址，例如 `192.168.1.100:8080`，不要输入 `http://`。
5. 如需开机后保持服务，勾选“登录后自动启动本机 PAC 服务”。
6. 点击“启用智能分流”。程序会自动安装 genpac、下载 GFWList、生成 PAC、启动本机服务，并写入 Windows 的自动代理脚本设置。
7. 点击“测试是否分流”，确认代理命中域名返回 `PROXY`、直连域名返回 `DIRECT`。

启用完成后，Windows 使用的 PAC 地址是：

```text
http://127.0.0.1:8765/proxy.pac
```

点击“停止并关闭分流”会同时清除 Windows PAC 设置并停止本机服务。程序会在界面上明确显示当前启用状态，避免“看似开着其实没生效”。

## 一站式能力

- 输入 HTTP 代理地址并一键启用 GFWList 分流。
- 自动写入和刷新 Windows PAC 设置，不需要再手动进系统代理页。
- 简单界面内就有“开机自启”选项。
- 内置分流测试：用 Windows JScript 实际执行 PAC，验证一个代理规则和一个直连规则。
- 内置中英文切换、自定义规则编辑、服务状态和 Windows 设置状态。
- 本地保存的地址和设置位于 `data/`，不会提交到 Git。

## 自定义规则

在界面的“自定义规则与诊断”展开区填写，一行一条：

```text
||example.com     # 强制走代理
@@||example.com   # 强制直连
```

保存后再次点击“启用智能分流”即可重新生成 PAC。GFWList 是代理规则列表，不是严格的国内/国外网站字典；未匹配的网站默认直连。

## 诊断与维护

旧版“专业模式”已移除，因为核心操作已经全部收进主界面。保留的诊断区只用于编辑规则和查看分流测试结果；需要命令行时，仍可调用：

```powershell
.\scripts\Test-Package.ps1       # 隔离验证，不改系统代理
.\scripts\Test-SplitRouting.ps1  # 检查当前 PAC 规则决策
.\scripts\Disable-WindowsPac.ps1 # 仅关闭 Windows PAC
```

## 从源代码运行

若不使用构建好的压缩包，安装 [Rust](https://www.rust-lang.org/tools/install) 与 Python 3 后，双击 `Start-WindowsSplitPAC.cmd`；它会自动以 release 模式编译并启动原生 GUI。

## 质量保证

GitHub Actions 在干净的 Windows 环境中运行两条独立质量门禁：

- Rust：`cargo fmt --check`、`cargo clippy -D warnings`、单元测试。
- PAC：PowerShell 入口解析、临时 PAC 生成、本机 HTTP 服务、PAC MIME 类型和实际路由决策测试。

`Build Windows Package` 工作流会构建可携带的 `.exe` 并上传 ZIP 构件。

## 许可证

[MIT](LICENSE)
