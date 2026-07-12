# Windows Split PAC

[简体中文](README.md) | [English](README.en.md)

一个面向 Windows 的轻量 PAC 分流工具：GFWList 和你指定的网站走 HTTP 代理，其余流量直连。没有 SOCKS5、Clash/Mihomo 或隐藏安装器。

## 简单操作

适合不想记命令的用户。先安装 [Python 3](https://www.python.org/downloads/windows/)，安装时勾选 **Add Python to PATH**，然后：

1. 下载或克隆本项目。
2. 双击 `Start-WindowsSplitPAC.cmd`。
3. 在右上角选择 `简体中文` 或 `English`。
4. 点击“准备 Python 与 genpac”。
5. 输入手机 Every Proxy 的 **HTTP 地址**，例如 `192.168.1.100:8080`，不要写 `http://`。
6. 点击“生成 PAC 并启动”。
7. 点击“复制 PAC 地址并打开系统设置”，在 Windows 的“代理”页面启用“使用设置脚本”，粘贴已复制的地址：

```text
http://127.0.0.1:8765/proxy.pac
```

图形界面不会自动修改 Windows 代理设置。这样你始终能看见并掌控最后一步。

### 最常见的两件事

- 代理地址变了：重新输入新地址，点击“生成 PAC 并启动”。不用改 Windows 里的 PAC 地址。
- 某个网站必须走代理：点击“编辑自定义规则”，添加 `||example.com`，保存后再次点击“生成 PAC 并启动”。

## 工作原理

```text
浏览器 -> 本机 PAC 地址
             |
             +-> 匹配 GFWList 或自定义规则 -> HTTP 代理
             |
             +-> 其他所有网站 -> 直连
```

GFWList 不是严格的“国内/国外网站字典”，而是代理规则列表。没有命中的网站默认直连。你可以在 `rules/user-rules.txt` 覆盖规则：

```text
||example.com     # 强制走代理
@@||example.com   # 强制直连
```

PAC 文件重新生成后，运行中的本机服务会立刻读取新文件，通常**不需要重启服务**。

## 进阶操作

图形界面的“进阶操作”页提供相同能力，也可直接在 PowerShell 中执行：

```powershell
# 仅首次：检查 Python、pip 并安装 genpac
.\scripts\Install-Dependencies.ps1

# 从 GFWList 和 rules\user-rules.txt 生成 PAC
.\scripts\Build-Pac.ps1 -ProxyAddress '192.168.1.100:8080'

# 管理本机 PAC 服务
.\scripts\Start-PacServer.ps1
.\scripts\Stop-PacServer.ps1

# 独立测试：不使用真实代理，不修改 Windows 设置
.\scripts\Test-Package.ps1
```

可选开机自启：

```powershell
.\scripts\Install-Autostart.ps1
.\scripts\Uninstall-Autostart.ps1
```

它创建名为 `WindowsSplitPAC` 的登录后任务，只启动本机服务，不会改 Windows 代理设置。

## 安全与排查

- 服务只监听 `127.0.0.1`，局域网设备无法访问。
- 真实代理地址、规则、PAC 产物、PID 和日志均被 Git 忽略。
- 启动脚本在报告成功前会验证 HTTP 响应；停止脚本会确认 PID 属于本工具。
- 国内网站仍慢时，先确认它是否被规则命中；若已走代理，延迟通常来自手机/VPN/代理出口链路，而非 PAC 文件。

## 项目结构

```text
Start-WindowsSplitPAC.cmd  双击启动图形界面
WindowsSplitPAC.ps1       中英文 WinForms 图形界面
scripts/                  进阶 PowerShell 脚本
rules/                    可编辑的自定义规则
src/                      标准库 PAC 本机服务
dist/                     生成的 PAC（本地文件，不上传）
.runtime/                 PID 与日志（本地文件，不上传）
```

每次推送都会在 GitHub Actions 的干净 Windows 环境中执行隔离测试，验证 PAC 生成、规则写入、服务、MIME 类型、健康检查和 PowerShell 入口语法。

## 许可证

[MIT](LICENSE)
