# 功能设计：识别当前服务（RECOGNIZE CURRENT SERVICE）

> 目标：让 GUI 打开时能**精确判断当前 Windows 上"PAC 分流到底是谁在跑、处于什么状态"**，避免与真实服务脱节。

## 为什么必须做
当前系统存在**多套并行脚本与服务**：
- 真实服务：计划任务 `PACServer` + `serve_pac.py`（`C:\proxy\`）
- GUI 自己的实现：`Start-PacServer.ps1`（`.runtime\`、`WindowsSplitPAC` 任务）
- 多个历史调试 PAC 文件（`C:\proxy\_*.pac`）、过期 pid 文件

若不做识别，GUI 会"自说自话"地误报或误操作。

## 识别数据源（按优先级）

### A. 端口 + 进程（最权威）
```powershell
# 1) 谁在监听 8765
Get-NetTCPConnection -LocalPort 8765 -State Listen |
  Select LocalAddress, LocalPort, OwningProcess

# 2) 该进程命令行（判断是否 serve_pac.py 以及 PAC 路径）
Get-CimInstance Win32_Process -Filter "ProcessId=<pid>" | Select CommandLine
```
判定：
- 响应 `http://127.0.0.1:8765/proxy.pac` 且 200 → 服务在跑
- 命令行含 `serve_pac.py` → 是"你的真实服务"
- 命令行含 `pac_server.py` → 是"GUI 平行服务"
- 命令行是别的 python → 未知/第三方，勿动

### B. PID 文件（辅助，易过期）
- `C:\proxy\pac-server.pid` 存在 → 记录曾启动 PID，但**必须与 A 交叉验证**（已知现存 pid 28940 已过期）。

### C. 注册表（Windows 是否真的在用 PAC）
```powershell
$s = Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
# AutoConfigURL, ProxyEnable, ProxyServer, ProxyOverride, AutoDetect
```
- `AutoConfigURL=http://127.0.0.1:8765/proxy.pac` → Windows 正用本 PAC
- `AutoConfigURL` 指向别处 → Windows 正在用其他 PAC（需告警）

### D. 自启计划任务
```powershell
Get-ScheduledTask PACServer      # 真实服务自启
Get-ScheduledTask WindowsSplitPAC # GUI 自己建的自启（若存在说明 GUI 被用过）
```

### E. 规则文件对比
- `C:\proxy\user-rules.txt`（线上真实规则） vs `rules\user-rules.txt`（仓库默认）
- 不一致时提示并提供"同步到线上"按钮

## 输出：服务状态对象（JSON）
```json
{
  "server_running": true,
  "server_kind": "real_serve_pac | gui_pac_server | unknown | none",
  "pid": 30572,
  "pid_file_matches": false,
  "port": 8765,
  "pac_url": "http://127.0.0.1:8765/proxy.pac",
  "pac_proxy": "PROXY 10.10.10.19:8080",
  "auto_config_url": "http://127.0.0.1:8765/proxy.pac",
  "proxy_enable": 0,
  "windows_using_our_pac": true,
  "autostart_task": {"name":"PACServer","exists":true,"state":"Ready"},
  "rule_file_diff": {"online_rules": 5, "gui_rules": 0, "in_sync": false}
}
```

## GUI 展示
- 四个状态卡片扩展：PAC 服务 / Windows 设置 / 恢复保障 / 开机自启，旁边加一行**"当前由真实服务(serve_pac.py)驱动"**或警告。
- 若检测到"另一套服务也在 8765"或"pid 文件过期"，用红色警示并给出"刷新/接管"动作。

## 建议实现位置
- 新增 `scripts/Get-ServiceIdentity.ps1`（在现有 `Get-WindowsPacStatus.ps1` 基础上扩展端口/进程/任务识别）。
- Rust 侧 `lib.rs` 扩展 `SplitTestResult` 为更完整的 `ServiceIdentity` 结构。
- 复用现有 `refresh_status()` 的调用点。
