# 分析：GUI 仓库 vs 你实际在用的分流脚本

> 结论先行：**这个 GUI 仓库是「另起炉灶、平行重写」的实现，并不是套在你实际分流脚本上的壳。**
> 它与你线上正在跑的 `C:\Users\62003\.hermes\serve_pac.py` 服务是两套不同代码，只共享同样的**设计思路**（GFWList + genpac + 本机 8765 端口的 Python PAC 服务 + 改 Windows AutoConfigURL）。

---

## 1. 判定依据（GUI 是"另外做的"）

### 1.1 两个完全不同且互不引用的代码库

| 维度 | 你**线上真实运行**的服务 | **GUI 仓库** (windows-split-pac) |
| --- | --- | --- |
| PAC 服务脚本 | `C:\Users\62003\.hermes\serve_pac.py`（32 行，硬编码端口 8765、PAC 路径） | `src/pac_server.py`（63 行，独立重写的另一个 HTTP 服务，支持 `--pac-file/--port` 参数） |
| PAC 生成 | 手动/脚本调用 `genpac`，产物写到 `C:\proxy\proxy.pac` | `scripts/Build-Pac.ps1` 调 genpac 写到 `dist\proxy.pac` |
| 运行时目录 | `C:\proxy\`（扁平：proxy.pac、user-rules.txt、pac-server.pid、日志、若干 `_*.pac` 诊断文件） | `dist\`/`.runtime\`（GUI 自己的布局） |
| 自启 | 计划任务 `PACServer` → `pythonw.exe .hermes\serve_pac.py` | `scripts/Install-Autostart.ps1` → 计划任务 `WindowsSplitPAC` |
| 备份/恢复 | 无（.hermes 只有 hand-made 的 switch_to_pac / check_proxy / remove_proxy_env） | `scripts/Save-/Restore-WindowsProxyBackup.ps1`（完整 JSON 备份恢复机制） |
| 启动器 | `start_pac_server.bat`、`switch_to_pac.ps1` | `Start-WindowsSplitPAC.cmd` + Rust GUI + 全套 PowerShell |

**核心证据**：GUI 的 `Start-PacServer.ps1` 用的是 `src\pac_server.py`，跑的是 `.runtime\pac-server.pid`；而你真实的服务是 `~/.hermes/serve_pac.py`，跑在 `C:\proxy\`。GUI 从没引用过 `serve_pac.py` 或 `C:\proxy`。两者是**平行实现**。

### 1.2 结论与建议

- **是"另外做的"** → 按你的要求 **不采用这套 GUI 的现有架构作为继续开发的基础，而是保留它作为"参考实现"**（它的备份/恢复、测试脚本、双语 UI 很成熟，值得借鉴）。
- 后续开发**优先围绕你真实的 `serve_pac.py` + `C:\proxy\` 工作流**做整合（让 GUI 去控制它，而不是再造一个平行服务）。

---

## 2. 你线上真实分流系统全貌（供后续开发）

> 以下信息是本次在 **WSL2** 环境里对 Windows 侧实际运行状态的实时勘探结果（2026-08-17）。

### 2.1 当前运行状态（实测）

- **本机 PAC 服务在 8765 端口运行**：`pythonw.exe`，PID **30572**
  - 命令：`"C:\Program Files\Python312\pythonw.exe" C:\Users\62003\.hermes\serve_pac.py`
- **Windows 代理设置（当前生效）**：
  - `AutoConfigURL = http://127.0.0.1:8765/proxy.pac` ✅（PAC 已启用）
  - `ProxyEnable = 0`（已关闭手动代理）
  - `ProxyServer = 10.10.10.19:8080`（残留值仍在，但 ProxyEnable=0 所以不生效）
- **自启计划任务**：`PACServer`（状态 Ready，Logon 触发）→ `pythonw.exe serve_pac.py`
  - 注意：还有一个同名 `Proxy` 计划任务，但那是系统自带的 `acproxy.dll` 任务，与本服务无关，别误删。

### 2.2 线上真实的 PAC 产物

- 文件：`C:\proxy\proxy.pac`（约 125 KB，最后修改 2026-08-17）
- 生成器：`genpac 3.0.1`，PAC 代理指向 **`PROXY 10.10.10.19:8080`**
- 数据源：GFWList（在线 `raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt`）
- 自定义规则（`C:\proxy\user-rules.txt`，实时内容）：
  ```
  ||mrds66.com
  ||91cg1.com
  ||fuzzysoulfate-college-web-music.hf.space/
  ||jcomic.net
  ||18comic.vip
  ```

### 2.3 线上服务的脚本清单（`.hermes` 目录）

| 文件 | 作用 |
| --- | --- |
| `serve_pac.py` | **真正的 PAC HTTP 服务**（stdlib http.server，端口 8765，读 `C:\proxy\proxy.pac`） |
| `setup_pac_autostart.ps1` | 创建 `PACServer` 计划任务（登录自启，带 3 次重启容错） |
| `start_pac_server.bat` | 手动启动服务：`pythonw serve_pac.py` |
| `switch_to_pac.ps1` | 切到 PAC 模式（写 AutoConfigURL、关 ProxyEnable、清 ProxyServer） |
| `check_proxy.ps1` | 诊断：打印注册表代理设置、用户级 HTTP_PROXY 环境变量、genpac 安装情况 |
| `remove_proxy_env.ps1` | 删除用户级 HTTP_PROXY/HTTPS_PROXY/NO_PROXY（此前破坏鸣潮启动器的元凶） |
| `rollback_env.ps1` | 环境变量回滚脚本 |
| `serve_pac.py.bak` | 旧版备份（读的是 `~isolated-proxy-test.pac`，已废弃） |

### 2.4 线上真实的"代理"与规则生成方式

`C:\proxy\proxy.pac` 由 genpac 生成，核心等价命令大致是：

```powershell
genpac --format pac `
  --pac-proxy "PROXY 10.10.10.19:8080" `
  --gfwlist-url "https://raw.githubusercontent.com/gfwlist/gfwlist/master/gfwlist.txt" `
  --user-rule-from "C:\proxy\user-rules.txt" `
  --output "C:\proxy\proxy.pac"
```

> 注意：GUI 仓库里的 `Build-Pac.ps1` 产出去 `dist\proxy.pac`；线上真实产出去 `C:\proxy\proxy.pac`。两者必须统一（见下）。

---

## 3. 对 GUI 的处置建议（承接第 1 点结论）

### 3.1 放弃平行实现，重心迁移到"控制真实服务"

建议后续 GUI 改造为 **你的真实服务的"控制面板"**，而不是自带一套服务：

1. **服务层**：复用 `serve_pac.py`（或在其上小改），不要再用 `src/pac_server.py` 另起炉灶。
2. **工作目录**：统一到 `C:\proxy\`，PAC 产物、PID、日志、user-rules 全放这里。
3. **自启**：对接现有 `PACServer` 计划任务；GUI 显示并管理该任务状态。
4. **备份/恢复**：这部分 GUI 做得很完善，保留并接入真实服务流程。

### 3.2 关于"识别当前服务"功能（你的第 2 点）

这是**正确且必要**的方向，因为当前系统存在**多套并存的服务/脚本**，GUI 必须先摸清"现在到底谁在跑"。识别逻辑建议：

- **端口探测**：`127.0.0.1:8765/proxy.pac` 与 `/healthz` 是否响应、返回的 PAC 内容里 `PROXY` 指向哪个地址。
- **进程识别**：查 8765 监听进程（`Get-NetTCPConnection` → `OwningProcess` → 命令行），判断是不是 `serve_pac.py`。
- **PID 文件**：`C:\proxy\pac-server.pid` 与 `serve_pac.py`（注意现存 pid 文件已过期，需按命令行二次校验）。
- **注册表状态**：`AutoConfigURL`/`ProxyEnable`/`ProxyServer`/`ProxyOverride`/`AutoDetect`。
- **自启任务**：`PACServer`（真实）vs `WindowsSplitPAC`（GUI 自己建的）是否存在、状态如何。
- **规则文件**：`C:\proxy\user-rules.txt` 与 GUI `rules\user-rules.txt` 差异对比。

> 详见 `FEATURE-RECOGNIZE-CURRENT-SERVICE.md` 中的实现草案。

---

## 4. 结论一句话

**保留 GUI 仓库作为参考实现（备份/恢复/测试/双语 UI 值得借鉴），但后续开发以你真实的 `serve_pac.py` + `C:\proxy\` 工作流为目标，把 GUI 重构成"真实服务的控制面板"，并先实现"识别当前服务"能力。**
