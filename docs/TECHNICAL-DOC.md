# Windows Split PAC —— 真实服务技术文档（开发用）

> 本文档以 **2026-08-17 在 WSL2 中对用户 Windows 侧的实际勘探结果** 为准，描述线上真实运行的 PAC 分流系统，作为后续开发依据。

---

## 0. 环境说明（重要）

- **开发主机**：用户 Windows 机器，当前通过 **WSL2 (Ubuntu-24.04)** 使用 DSH harness 开发。仓库克隆在 WSL 下 `/home/dsh/Test/windows-split-pac`。
- **目标运行平台**：PAC 分流最终运行在 **Windows**（改动注册表、跑 PowerShell、起 Python 服务），GUI 是 **Rust + egui** 原生 Windows 程序。
- **WSL ↔ Windows 互通**：可以从 WSL 调 `powershell.exe`/`cmd.exe`（interop）执行 Windows 命令，用于探测/管理真实服务。
- **网络代理**：本机所有外网流量走 `http://10.10.10.19:8080`；PAC 的上游代理也正是 `PROXY 10.10.10.19:8080`。

### 目录映射
| WSL 侧路径 | Windows 侧路径 |
| --- | --- |
| `/mnt/c/proxy/` | `C:\proxy\`（线上工作目录） |
| `/mnt/c/Users/62003/.hermes/` | `C:\Users\62003\.hermes\`（服务脚本 + 运维脚本） |
| `/home/dsh/Test/windows-split-pac` | WSL 内仓库（开发用） |

---

## 1. 线上真实服务架构

```
┌─ Windows ──────────────────────────────────────────────┐
│                                                       │
│  计划任务 PACServer (Logon 触发)                       │
│      │ pythonw.exe  C:\Users\62003\.hermes\serve_pac.py│
│      ▼                                                │
│  serve_pac.py  [127.0.0.1:8765]                       │
│      │ 读                                              │
│      ▼                                                │
│  C:\proxy\proxy.pac            ← genpac 3.0.1 生成    │
│      │ (PAC: PROXY 10.10.10.19:8080)                  │
│      ▼                                                │
│  Windows 注册表                                        │
│   HKCU\...\Internet Settings                           │
│   AutoConfigURL = http://127.0.0.1:8765/proxy.pac      │
│                                                       │
└───────────────────────────────────────────────────────┘
```

### 关键文件
| 文件 | 类型 | 职责 |
| --- | --- | --- |
| `C:\Users\62003\.hermes\serve_pac.py` | Python | 在 127.0.0.1:8765 提供 `/proxy.pac`，正确 MIME `application/x-ns-proxy-autoconfig` |
| `C:\Users\62003\.hermes\setup_pac_autostart.ps1` | PS | 创建 `PACServer` 登录自启任务（pythonw） |
| `C:\Users\62003\.hermes\start_pac_server.bat` | bat | `pythonw serve_pac.py` 手动启动 |
| `C:\Users\62003\.hermes\switch_to_pac.ps1` | PS | 写 AutoConfigURL、ProxyEnable=0、清 ProxyServer |
| `C:\Users\62003\.hermes\check_proxy.ps1` | PS | 诊断代理/环境变量/genpac |
| `C:\Users\62003\.hermes\remove_proxy_env.ps1` | PS | 删用户级 HTTP_PROXY 等（防鸣潮启动器被破坏） |
| `C:\proxy\proxy.pac` | 数据 | 实际下发给浏览器的 PAC |
| `C:\proxy\user-rules.txt` | 数据 | 自定义规则（Adblock/GFWList 语法） |
| `C:\proxy\pac-server.{pid,stdout,stderr}.log` | 运行时 | 服务进程 PID 与日志（注意 Pid 文件可能过期） |

---

## 2. `serve_pac.py` 源码解读

```python
PORT = 8765
PAC_FILE = "C:\\proxy\\proxy.pac"   # 硬编码 PAC 路径

class PACHander(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/proxy.pac":
            # 读文件 → 200 + Content-Type: application/x-ns-proxy-autoconfig
            # + Cache-Control: no-cache,no-store,must-revalidate
        else:
            send_error(404)

with socketserver.ThreadingTCPServer(("127.0.0.1", PORT), PACHander) as httpd:
    httpd.daemon_threads = True
    httpd.allow_reuse_address = True
    httpd.serve_forever()
```

**特征**：
- 纯 Python 标准库，无第三方依赖。
- `allow_reuse_address=True`：重启不报端口占用。
- 无 `/healthz`（GUI 仓库的 `pac_server.py` 有，线上这个没有）。
- 硬编码 `PAC_FILE` 与 `PORT`，改动需直接编辑脚本。

---

## 3. 当前运行状态快照（2016-08-17 实测）

| 项 | 值 |
| --- | --- |
| 8765 监听进程 | PID **30572**，`pythonw.exe`，命令行指向 `serve_pac.py` |
| PAC 产物 | `C:\proxy\proxy.pac`（125 KB，genpac 3.0.1，`PROXY 10.10.10.19:8080`） |
| AutoConfigURL | `http://127.0.0.1:8765/proxy.pac` |
| ProxyEnable | 0 |
| ProxyServer | `10.10.10.19:8080`（残留，未生效） |
| 自启任务 | `PACServer` Ready（Logon 触发） |
| 自定义规则 | mrds66 / 91cg1 / hf.space 音乐站 / jcomic / 18comic |

> ⚠️ 注意：`C:\proxy\pac-server.pid` 里的 PID(28940) 已过期，真实进程是 30572。**不要只信 pid 文件，必须以端口监听者 + 命令行二次校验。**

---

## 4. 与服务兼容的改造方向（后续开发）

### 4.1 现有 GUI 仓库(参考实现)与线上体系的差异
| 环节 | GUI 仓库 | 线上真实 |
| --- | --- | --- |
| PAC 服务 | `src/pac_server.py`(可参数化、带 /healthz) | `serve_pac.py`(硬编码) |
| PAC 路径 | `dist\proxy.pac` | `C:\proxy\proxy.pac` |
| 自启任务名 | `WindowsSplitPAC` | `PACServer` |
| 备份/恢复 | 有(JSON) | 无 |
| 工作目录 | 仓库根 | `C:\proxy\` |

### 4.2 建议的整合步骤（后续）
1. **服务统一**：让 GUI 控制 `serve_pac.py`（可保留 /healthz 增强，但路径对齐 `C:\proxy`）。
2. **规则统一**：GUI 编辑 `C:\proxy\user-rules.txt` 而非 `rules\user-rules.txt`。
3. **PAC 生成统一**：输出 `C:\proxy\proxy.pac`、上游 `PROXY 10.10.10.19:8080`。
4. **自启管理**：管理 `PACServer` 任务（而非新建 `WindowsSplitPAC`）。
5. **识别当前服务**：见 `FEATURE-RECOGNIZE-CURRENT-SERVICE.md`。

### 4.3 开发注意事项
- 改动 PAC 后必须重启/刷新服务，且浏览器会缓存 PAC；关掉 `Cache-Control` 由服务端已处理。
- 生成 PAC 需要能访问 GFWList（走代理）。本机代理 `10.10.10.19:8080`。
- 修改 Windows 注册表前务必先备份（参照 GUI 的 Save/Restore 脚本）。
- `remove_proxy_env.ps1` 曾用于修复鸣潮启动器——涉及**用户级环境变量**时务必谨慎、先查再删。

---

## 5. 探测/管理命令速查（WSL → Windows）

```bash
# 查看 8765 监听进程
powershell.exe -NoProfile -Command \
  "Get-NetTCPConnection -LocalPort 8765 -State Listen | Select OwningProcess"

# 看某进程命令行
powershell.exe -NoProfile -Command \
  "Get-CimInstance Win32_Process -Filter \"ProcessId=30572\" | Select CommandLine"

# 看 PAC 计划任务
powershell.exe -NoProfile -Command "Get-ScheduledTask PACServer | Select State; (Get-ScheduledTask PACServer).Actions"

# 看注册表代理设置
powershell.exe -NoProfile -Command \
  "Get-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings' | Select AutoConfigURL,ProxyEnable,ProxyServer"
```

> 从 WSL 调用 cmd.exe 时注意 UNC 当前目录问题（可先 `cd /mnt/c`），并避免在 WSL 家目录路径下直接装中文引号给 cmd。
