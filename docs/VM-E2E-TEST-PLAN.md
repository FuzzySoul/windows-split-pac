# VM E2E 测试计划（Windows 干净虚拟机）

> 目标：在**干净 Windows 虚拟机**上按“对标方案”跑通全部 E2E，验证新机也能用、GFWList 内置、自启可靠、应用规则后自动重启 Edge 生效。
> 原则：先做文档步骤，再执行；每步记录结果；失败回滚快照重来。

---

## 1. 前提环境
- Windows 10/11 干净 VM（建议 2C4G，启用快照）
- 网络可达（抓取 GFWList 需外网/代理）
- 准备好 `F:\WindowsSplitPAC-Verify`（已是最新 main，含 exe/脚本）

## 2. 预备步骤
1. 从快照创建干净 VM；
2. 把 `F:\WindowsSplitPAC-Verify` 复制到 VM，例如 `G:\Code\WindowsSplitPAC-Verify`；
3. 安装 Python 3 + genpac（GUI 生成 PAC 需要）：
   ```powershell
   pip install -r G:\Code\WindowsSplitPAC-Verify\requirements.txt
   ```
4. （可选）安装 Rust 用于源码测试；使用 exe 则不需要。

## 3. 自动测试脚本（按顺序执行）
```powershell
# 1) 一键全量（PS 语法 / core 单测 / 编译 / 线上只读 / Apply 干跑）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-All.ps1 -SkipLive   # VM 无线上服务可加 -SkipLive

# 2) 隔离端口端到端（不碰注册表/线上）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-Isolated.ps1

# 3) 新机 GFWList（空目录生成，断言 GFWList+自定义规则）
powershell -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-GfwList.ps1
```

## 4. GUI 手动/半自动流程（核心验收）
1. 双击 `双击打开GUI.cmd`；
2. 顶部填上游代理（如 `10.10.10.19:8080`），勾选/不勾自启取决于测试计划；
3. 点「启用智能分流」→ 等待成功（应用后会自动重启 Edge）；
4. 在“规则管理”弹窗，对 `www.coolinet.net` 点「测试」→ 预期显示“实测可打开 200”；
5. 通过“添加规则”粘贴一个网址 → 保存并应用 → 自动重启 Edge；
6. 访问该网址，确认生效；
7. 若测“新机无管理员”：用标准用户登录，重复步骤 3，自启应回退到 HKCU Run 且不报错。

## 5. 指标采集（对标用）
> 在 VM 中同时安装 Clash Verge Rev 与本产品，同一网络同一时间采集：
- 启动时间：轮询 readiness（本产品 `/healthz`；Clash 用其 API/端口）
- 内存/CPU：`Get-Process` / `Get-Counter` 采样 5 分钟
- 生成/生效耗时：脚本计时
- 24h 稳定性：内存曲线、WER 事件、healthz
（采集脚本 `Measure-Startup.ps1` / `Measure-Resources.ps1` 为待补项，按 `docs/BENCHMARK-VS-MATURE-PROXY.md` 方法实现）

## 6. 通过标准汇总
| 项 | 标准 |
| --- | --- |
| Test-All | 全部 PASS |
| Test-Isolated | PASS |
| Test-GfwList | PASS（google/youtube + coolinet/twitch 均在 PAC） |
| 启用智能分流 | 无“No generated PAC file”错误 |
| 自动重启 Edge | 重启后新规则可访问 |
| 非管理员自启 | 计划任务失败→HKCU Run 成功，无报错 |
| 稳定性 | 24h 无崩溃/无健康率下降 |

## 7. 失败回退
- 任一步失败：记录输出与截图 → 修复 → 重新打快照 → 重跑整条链路，直到全部 PASS。