# 对标成熟分流软件测试方案（BENCHMARK vs MATURE PROXY CLIENTS）

> 目标：让本产品（WindowsSplitPAC）的**各项数据与市面成熟分流软件（Clash Verge Rev / mihomo、v2rayN、sing-box 等）对标**，
> 每项测试**方法严谨、可复现、同机同网同口径**。
> 本文只定方法；**对标对象的数值必须在同一 VM/真机上实测采集，禁止编造**。本产品各项先自测，留“对标待采”列。

---

## 0. 测试原则
- 同一台干净 Windows VM、同一网络、同一时段；
- 每个指标重复 **≥3 次**，取**中位数**；
- 每个指标写明：测量工具、测量起点/终点、进程集合、是否含 DNS/PAC 网络开销；
- 任何“通过标准”先定义，再下结论；
- 每一步先用文档记录，再执行（“做一步搜一步”）。

---

## 1. 对标对象与本产品

| 项目 | 本产品 | 对标对象 |
| --- | --- | --- |
| 核心 | PAC 本地服务（Python stdlib） | Clash Verge Rev（mihomo Go 内核）、v2rayN、sing-box |
| GUI | Rust/egui | Tauri/Web（Clash Verge）等 |
| 分流模型 | 域名规则 + GFWList（PAC） | 规则→策略组→节点（mihomo） |
| 授权 | MIT | 各有不同 |

---

## 2. 测试维度与严谨方法

### T1 首启/上手
| 指标 | 方法 | 通过标准 |
| --- | --- | --- |
| 从安装到“可分流”步骤数 | 记录：安装/解压→启动→配置→启用，最小人工步骤 | 明确对比，本产品 ≤3 步 |
| 是否需要管理员/驱动/TUN | 安装和运行时的 UAC、驱动、服务模式记录 | 本产品免管理员（除自启计划任务需管理员时有 HKCU Run 兜底） |
| 是否需要订阅/节点 | 检查默认配置是否开箱即用 | 本产品无需订阅 |

### T2 启动时间
| 指标 | 方法 |
| --- | --- |
| 冷启动到服务就绪 | `Measure-Command { Start-Process ... }` + 轮询 `/healthz` 200 时间戳差 |
| GUI 到可交互 | 启动 exe 到窗口出现（视觉/自动化），或日志时间戳 |

脚本：`Measure-Startup.ps1`（待补，VM 阶段实现）

### T3 常驻资源
| 指标 | 方法 |
| --- | --- |
| 内存（工作集 MB） | `Get-Process -Name <exe> | Select WorkingSet64`，空闲 5 分钟后采样 |
| CPU（空闲/分流） | `Get-Counter "\Process(<exe>)\% Processor Time"`，10s 采样 |
| 进程数 | 本产品期望 1 个 GUI + 1 个 python 服务；Clash 为多进程 |
| 安装体积 | 文件夹大小 / 安装包大小 |

脚本：`Measure-Resources.ps1`（待补）

### T4 分流正确性（核心）
| 用例 | 期望 |
| --- | --- |
| `www.google.com` | PROXY |
| `baidu.com` | DIRECT |
| `coolinet.net` / `www.coolinet.net` | PROXY（实测 www 稳定，裸主域可能上游抖动） |
| 自定义规则命中 | 与 `user-rules.txt` 一致 |

现有工具：`scripts/Test-PacDomain.ps1`（PAC 判定）、`scripts/Test-Site.ps1`（**真连** HTTP 状态）。

### T5 规则应用生效耗时
| 步骤 | 测量 |
| --- | --- |
| 添加规则→保存 | 本地计时（GUI 日志/秒表） |
| PAC 重新生成 | `Build-Pac.ps1` 耗时（genpac，含 GFWList 网络时间） |
| 浏览器生效 | 保存应用后 Edge 自动重启完成→访问目标站可打开的时间点（VM 自动化） |

### T6 新机 GFWList
- 已有专项：`scripts/Test-GfwList.ps1`（空目录生成 PAC，断言 GFWList 与自定义规则都在）。
- 通过标准：`google.com` / `youtube.com` 与 `coolinet.net` / `twitch.tv` 均在生成 PAC 中。

### T7 自启可靠性
- 计划任务（需管理员）→ 失败回退 `HKCU\...\Run`（免管理员）。
- 测试：非管理员账号下启用自启，确认 Run 项写入；重启 VM 后服务自动起。

### T8 稳定性
- 24h 连续运行：
  - 内存曲线不单调上涨（无泄漏）；
  - 无 `AppHangTransient` / `APPCRASH`（查 WER/事件日志）；
  - PAC 服务 `healthz` 始终 200。

### T9 安全/权限
- 进程不请求管理员（除自启任务）、不写系统目录、不装驱动；
- 数据仅本机（规则/PAC 不外传）。

### T10 功能矩阵（对比性）
| 能力 | 本产品 | Clash Verge Rev |
| --- | --- | --- |
| 订阅/多节点 | ❌（设计上不做） | ✅ |
| 自动选择节点/测速 | ❌ | ✅ |
| TUN/游戏/UDP | ❌ | ✅ |
| 系统代理/PAC | ✅ | ✅ |
| 规则编辑 GUI | ✅（弹窗/三桶/高手） | ✅ |
| 诊断 | ✅ | ✅ |

> 本产品定位“轻量 PAC 一键工具”，不追求 TUN/多节点；表格价值是**明确边界**，避免对标错对象。

---

## 3. 现成 E2E 脚本清单
| 脚本 | 用途 |
| --- | --- |
| `Test-All.ps1` | 一键全量（PS 语法、core 单测、编译、线上只读、Apply 干跑） |
| `Test-Isolated.ps1` | 隔离端口+临时目录端到端，不碰注册表/C:\proxy |
| `Test-GfwList.ps1` | 新机 GFWList 生成验证 |
| `Test-PacDomain.ps1` | PAC 判定 |
| `Test-Site.ps1` | **真连**可达性（HTTP 状态/报错） |
| `Restart-Browser.ps1` | 方法 E：应用后重启 Edge |

---

## 4. 待补（VM 阶段）
- `Measure-Startup.ps1`
- `Measure-Resources.ps1`
- VM 自动化采集脚本（对 Clash Verge Rev 与本产品同机同法）