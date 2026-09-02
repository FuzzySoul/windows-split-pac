# WSL 开发最佳实践与网络排障（实测总结）

> 触发背景：在本环境里，**WSL2 通过 Windows 侧 LAN 代理（`10.10.10.19:8080`）下载大文件（如 Rust 工具链 200MB+）又慢又容易失败（"网络下载总是碰壁"）**。
> 本文是结合本机实测 + 社区/官方资料的调研，专门针对你在用的这套环境写的后续开发参考。

---

## 0. 先看本机现状（2026 实测）

| 项 | 实测值 | 说明 |
| --- | --- | --- |
| WSL 版本 | `2.6.3.0`（内核 `6.6.87.2`） | 很新，**支持 mirrored + autoProxy** |
| Windows 版本 | `10.0.28120`（Win11 25H2 系） | 支持 mirrored / dnsTunneling / autoProxy |
| WSL 网络模式 | **NAT（默认）** | `.wslconfig` 只有 `localhostForwarding=true` |
| WSL IP | `172.31.177.201`，网关 `172.31.176.1` | 经典 WSL NAT 网段 |
| /etc/wsl.conf | `systemd=true`，无 network 段 | |
| Windows 代理状态 | `AutoConfigURL=http://127.0.0.1:8765/proxy.pac`，`ProxyEnable=0` | 走 PAC，**未启用手动代理** |
| WSL→LAN 代理实测 | crates.io `200 (0.4s)`；github `200 (15s)`；google `000(超时)` | 代理本身能用，但对部分境外站又慢又堵 |

**结论一句话**：你现在 WSL 是 NAT 模式，访问"你的 Windows 侧代理"只能靠 LAN IP，且这个代理对 github/google 等大文件站点吞吐很差——这就是下载动不动碰壁的根因。

---

## 1. 最有效的三个方向（按性价比排序）

### 1.1 国内镜像直连（立竿见影，改造最小）⭐ 推荐先做
很多下载瓶颈不是 WSL 本身，而是"走了慢又堵的境外代理"。**对国内有镜像的源，直接绕过代理走国内 CDN，快一个数量级**。

实测（本机）：
```
rsproxy.cn  dist 直连: 200 (0.28s)    走代理: 200 (3.09s)
```

- **Rust**: `RUSTUP_DIST_SERVER=https://rsproxy.cn` + `RUSTUP_UPDATE_ROOT=https://rsproxy.cn/rustup`，crates 用稀疏索引 `sparse+https://rsproxy.cn/index/`。
- **npm**: 已配 npmmirror（见全局记忆），且 `NO_PROXY` 必须含 `cdn.npmmirror.com`（tarball 会 302）。
- **apt**: 换清华/阿里源。
- **Python pip**: 换清华源 `https://pypi.tuna.tsinghua.edu.cn/simple`。
- 关键点：**"国内源能直连就不要硬套代理"** —— 用 `NO_PROXY` / 定向 `--noproxy` 或直接分环境区分。

### 1.2 改 `networkingMode=mirrored` + `autoProxy=true`（治本，需重启 WSL）
这是社区公认的"WSL2 网络终极解决方案"。效果：
- WSL 内直接用 **`127.0.0.1` 访问 Windows 侧服务/代理**（不再需要 LAN IP）。
- **`autoProxy=true`**：WSL 自动继承 Windows 的 HTTP 代理设置。
- IPv6、VPN 兼容、多播、LAN 直连都更好。

示例 `C:\Users\<你>\\.wslconfig`：
```ini
[wsl2]
networkingMode=mirrored
dnsTunneling=true
firewall=true
autoProxy=true
memory=8GB
# localhostForwarding 在 mirrored 下会被忽略，可注释掉
```
改完在 PowerShell 执行 `wsl --shutdown` 再进 WSL 生效。

> ⚠️ 注意你的特殊点：**Windows 当前是 PAC 模式（`AutoConfigURL`），`ProxyEnable=0`**。
> `autoProxy=true` 同步的是"手动代理设置"；纯 PAC 模式下 WSL 的 `autoProxy` 未必能帮你填好 `HTTPS_PROXY`。
> 所以更建议：**mirrored 后你能用 `127.0.0.1:端口` 访问 Windows 代理**，把 WSL 里 `HTTPS_PROXY` 指到本地映射即可；若 Windows 代理是 Clash 类工具，通常它自己也开一个 `127.0.0.1:7890` 之类的手动端口。

### 1.3 关掉 vEthernet(WSL) 的 Large Send Offload（LSO）
经典"WSL 下载 10-20KB/s"问题（microsoft/WSL#4901）。
控制面板 → 网络 → vEthernet (WSL) 适配器 → 属性 → 配置 → 高级 → **Large Send Offload V2 (IPv4/IPv6) → 禁用**。
如果你的速度已经由"代理慢"主导，这条收益次之；但若是"直连也很慢"，这通常是元凶。

---

## 2. 其它高频 WSL 开发坑（社区共识）

### 2.1 文件系统：项目放 WSL 的 ext4（`~/`），别放 `/mnt/c/...`
WSL 跨文件系统走 **9P 协议，极慢**。`/mnt/c` 下 git clone、`node_modules`、`cargo build` 都会慢到怀疑人生。
- **现状**：你的仓库在 `/home/dsh/Test/windows-split-pac` ✅ 已经放在 ext4，很好。
- 避免：把 WSL 项目、依赖缓存放 `/mnt/c`；`cargo`/`npm` 缓存默认在 `~`，OK。
- 若必须配合 Windows 侧工具：用 `rsync` 同步（`rsync -a --exclude target --exclude .git`）到临时目录再 build，比直接跨 FS 快。

### 2.2 Git 大小写
```bash
git config --global core.ignorecase false
```
跨 Windows/WSL 协作时常踩大小写坑。

### 2.3 代理环境变量"每条命令都要带"的替代方案
全局记忆里说"shell 状态不跨调用保留，每条命令都要设"——这本身就是 WSL 会话的一个痛苦点。
缓解：写进 `~/.bashrc`（仅 `export` 语句，不写死），或用一个小的 `proxysh` 别名/wrapper：
```bash
alias px='export http_proxy=http://... ...  &&'
```
但注意国内源要 `NO_PROXY` 排除（见 1.1）。

### 2.4 大下载用后台 + 断点续传
- `curl -C - -o file url`（断点续传）。
- 或 `wget -c`。
- 后台跑（`run_in_background`/`nohup`），别阻塞，避免"等半天超时又从头来"。

---

## 3. 针对本仓库的具体建议

- **Rust GUI 构建**：若要在 WSL 里 `cargo build` 出 Windows 版 GUI，应当：
  1. 配好 crates 稀疏镜像（rsproxy），否则 `eframe` 拉依赖会非常痛苦；
  2. 需要 **Windows 目标**（`cargo build --target x86_64-pc-windows-msvc`）或直接在 **Windows 侧原生 build**（这个项目本质是 Windows GUI，最稳妥是在 Windows 上 `cargo build --release`）。
- **PowerShell 体检/运维脚本**：`powershell.exe`/`cmd.exe` interop 能直接连 Windows，本仓库大量脚本走这条即可，不必额外装 MCP（见 `WSL-MCP-ASSESSMENT.md`）。
- **代理/PAC 别误停**：见 `TECHNICAL-DOC.md`——真实服务在 8765 由 `serve_pac.py` 驱动，WSL 排查网络时不要动它。

---

## 4. 参考资料
- microsoft/WSL issue #4901（WSL2 网络慢的经典 issue）
- Microsoft Learn：WSL 高级配置 / 网络访问（mirrored、dnsTunneling、autoProxy、LSO 相关）
- STAAGAZER《WSLg/WSL2 网络配置，终极解决方案 - 镜像网络》
- Ryan Shang《WSL2 设置镜像网络模式》
- markentier.tech《Speedy Rust builds under WSL2》（rsync 到 ext4 再 build）
- rsproxy.cn 官方镜像说明（Rust 国内镜像）
