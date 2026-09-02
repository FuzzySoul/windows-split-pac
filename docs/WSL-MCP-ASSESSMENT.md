# 调研结论：WSL 相关 MCP 是否值得安装

## 一句话结论
**在你当前这套环境里，为 WSL"额外装一个 MCP"收益很低——因为 DSH 本来就运行在 WSL2 内部，已经拥有完整的 Linux shell + 通过 `powershell.exe`/`cmd.exe` 直连 Windows 的能力。与其装一个新的"WSL MCP"，不如直接用现有的 shell 能力（或按需接入一个 Windows 管理类 MCP）。**

---

## 1. 关键背景：我们已经在 WSL 里了
- 本 harness 运行在 `Ubuntu-24.04`（WSL2），当前 shell 就是 WSL 的 bash。
- 已能直接：
  - 执行任意 Linux 命令（`bash` 工具）
  - 调 `powershell.exe`/`cmd.exe` 执行 Windows 命令、查询注册表、进程、计划任务（本会话已用此探测真实 PAC 服务）
  - 读写 `/mnt/c/...`（Windows 文件系统）
- 也就是说：**"WSL shell MCP"能提供的能力（在 WSL 里跑命令、读写文件），这里原生就有，不需要再装一个 MCP。**

## 2. 市面上 WSL 相关 MCP 盘点（调研结果）
| 项目 | 定位 | 对本项目价值 |
| --- | --- | --- |
| `WSLShellMCP` / `mcp-wsl-shell` / `T-Nosaka/wslexec` | 在 WSL 里执行 shell 命令 | **低**——原生 bash 已覆盖 |
| `webconsulting/mcp-server-wsl-filesystem` | 从 Windows 访问 WSL 文件系统 / 反之 | **低**——`/mnt/c` / `\\wsl.localhost` 已覆盖 |
| `wsl-mcp` / `riparino` | 精简 WSL 命令 MCP | 低 |
| `WSLSnapit-MCP` | WSL 内截图/剪贴板 | 本机已有视觉插件，低 |
| `mcp-server-wslc` / 各种容器桥 | 容器化 | 低 |
| `windowsserver` / `windows-mcp-server`（96 工具，含注册表/服务/进程/计划任务） | **Windows 本地管理：注册表、服务、进程、计划任务、网络、PowerShell** | **中高**——若接入，agent 可更规范地管理 PAC 服务/计划任务/注册表，而不用手拼 powershell.exe 命令 |

## 3. 建议
### 3.1 推荐做法：不装 WSL MCP，直接用现有能力 + 沉淀脚本
- 本项目的 PAC 服务是 **Windows 侧**的。最有价值的是把常用 Windows 管理动作**固化成可复用脚本**（本会话已写 `docs/TECHNICAL-DOC.md` 里的 PowerShell 速查），agent 直接调用，比引入 MCP 更轻、更可控。

### 3.2 若确实想用一个 MCP（可选）
- 选 **Windows 管理类**而非"WSL shell 类"，例如带注册表/服务/计划任务/PowerShell 能力的 Windows MCP（如 `AhmedLaminou/windows-mcp-server`）。这样能规范化管理：8765 服务、`PACServer` 计划任务、`HKCU\...\Internet Settings` 注册表。
- 注意：**DSH 的 MCP 通过 cordis 插件/配置接入**（非简单的 `claude mcp add`），接入需要按 DSH 插件机制配置，且 MCP `env` 需带代理变量（见 AGENTS.md）。

### 3.3 明确的"不装"判断
针对"提高 WSL 开发效率"本身——**不需要**。WSL 开发效率已由原生 shell + 文件工具提供；再叠加一个 WSL shell MCP 只是重复冗余。

---

## 4. 落地建议（务实）
优先做三件事，比装 MCP 更提升效率：
1. **沉淀 `scripts/` 运维脚本**：把"启动/停止/识别 PAC 服务、查注册表、管计划任务"封装成固定 PS 脚本，agent 与 GUI 共用。
2. **接入真实服务**：按 `ANALYSIS-GUI-vs-LIVE-SCRIPT.md`，让 GUI 控制 `serve_pac.py`，而非平行实现。
3. **（可选）如接入 MCP**：选 Windows 管理 MCP，用 **stdin/stdio 走 DSH 插件机制**配置，并在 env 注入代理。
