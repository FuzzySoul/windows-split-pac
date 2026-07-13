# 推广素材包

本页用于对外介绍 Windows Split PAC。所有表述基于已实现功能，不使用“最快”“全自动识别国内外网站”等不可验证宣传语。

## 一句话介绍

一个用 Rust 构建的 Windows 本地 PAC 分流控制台：一键生成规则、自动配置系统 PAC、备份并恢复旧代理设置，还能实际验证 `PROXY` / `DIRECT` 决策。

## 中文发布稿

我开源了 **Windows Split PAC**，一个面向 Windows 的本地 PAC 分流控制台。

它不依赖 Clash、Mihomo 或 SOCKS5：输入 HTTP 上游代理后，程序会生成 GFWList PAC、启动本机服务、写入 Windows 自动代理脚本，并在关闭时恢复原有代理设置。

我比较在意“有没有真的分流”和“关闭后会不会把网络设置弄乱”，所以它内置了真实 PAC 决策测试，并在 CI 中覆盖代理设置备份恢复、PAC 生成、HTTP/MIME 和 `PROXY` / `DIRECT` 验证。

Release 已附带 Windows ZIP 与 SHA-256：
https://github.com/FuzzySoul/windows-split-pac/releases

## English launch post

I open-sourced **Windows Split PAC**, a native Windows control center for local PAC split routing.

It builds GFWList and custom rules into a PAC file, serves it on loopback, applies the Windows automatic proxy script, and restores the user's previous proxy configuration on disable. The built-in test evaluates real `PROXY` / `DIRECT` PAC decisions instead of only checking whether a process is alive.

The release includes a portable Windows ZIP and SHA-256 checksum:
https://github.com/FuzzySoul/windows-split-pac/releases

## 30 秒演示脚本

1. 打开 GUI，展示“恢复保障”为未启用状态。
2. 输入示例 HTTP 代理地址，不点击启用，说明启用前会保存旧代理设置。
3. 展开“自定义规则与诊断”，展示一条强制代理与一条强制直连规则。
4. 展示“分流测试”区域，说明它会执行 PAC 并返回 `PROXY` / `DIRECT`。
5. 结尾展示 GitHub Release 的 ZIP、SHA-256 和 CI 徽章。

## 推荐配图

- `assets/social-card.svg`：中文社交封面图。
- `assets/workflow.zh-CN.svg`：中文技术流程图。
- `assets/demo.gif`：真实 GUI 演示，生成后放在 README 首屏下方。

## 发布渠道

- GitHub Release：面向下载和技术背书。
- Bilibili：发布 30 秒录屏，标题强调“Windows PAC 分流、备份恢复、真实验证”。
- 掘金或知乎：发布技术复盘，重点写 Rust GUI、WinINet 刷新、PAC JScript 求值、隔离测试。
- V2EX 或相关开源社区：发布项目介绍，附 Release、截图和已知边界说明。

对外发布前，移除截图、日志和录屏中任何真实代理地址、内网 IP、浏览记录或账号信息。
