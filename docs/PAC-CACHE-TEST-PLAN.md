# PAC 新规则不生效 / Edge 缓存问题 —— 候选方案测试文档

> 目标：解决「添加新规则（如 coolinet.net）后，Edge 仍走旧 PAC / 不生效 / ERR_TIMED_OUT」。
> 方法：每个候选方案开独立分支 → E2E/脚本验证 → **不行就回退**。
> 当前基线：仓库 `62a94bc`，注册表 `AutoConfigURL=http://127.0.0.1:8765/proxy.pac`（干净固定）。

---

## 0. 已确认事实（2026-09-01 真机实测）

| 项 | 结果 |
| --- | --- |
| 规则 `\|coolinet.net` 已写入 `user-rules.txt` 和 `proxy.pac` | ✅ |
| PAC 对 `coolinet.net` / `www.coolinet.net` 判定 | ✅ `PROXY 10.10.10.19:8080` |
| **`www.coolinet.net` 经代理实测** | ✅ 稳定 HTTP 200 |
| **`coolinet.net`（裸主域）经代理实测** | ⚠️ **3 次中 2 次超时、1 次 200（不稳定）** |
| 代理控制组 `www.google.com` | ✅ 200 |
| PAC 服务器响应头 `Cache-Control: no-cache, no-store, must-revalidate` | ✅ 已存在 |
| Edge 进程数 | 当时 32 个（旧 PAC 被内存缓存） |
| WER 记录 | `AppHangTransient` 旧版 UI 卡死（非崩溃） |

**结论分层**：
1. Edge/Chromium 对 PAC 有内存缓存（最多 12h），只会在「全进程重启 / 手动 net-internals Re-apply / 网络变化 / 代理配置变化」时重读；
2. 即使缓存刷新，`coolinet.net` 裸主域经当前代理**本身不稳定**，可能随时 `ERR_TIMED_OUT`；
3. 服务器 Cache-Control 头**已经存在**，对 Chromium 内存缓存无效。

---

## 1. 候选方案清单

| # | 方案 | 依据 | 改动面 | 通过标准 |
| --- | --- | --- | --- | --- |
| A | **固定 PAC 地址 + WinINet 通知**（39 SETTINGS_CHANGED / 37 REFRESH / 95 PROXY_SETTINGS_CHANGED）+ 重写同值注册表 | [StackOverflow 使用 InternetSetOption](https://stackoverflow.com/questions/6174982/how-to-use-internetsetoption) | 脚本 | 保持地址固定；通知后 Edge 无需重启即可加载新规则 |
| B | **PAC URL 加 `?v=` 缓存破坏** | Chromium 官方：代理设置变化触发重读；[Chromium Proxy doc](https://chromium.googlesource.com/chromium/src/+/HEAD/net/docs/proxy.md) | 脚本+注册表 | 新规则立即生效；代价是“脚本地址”变长（用户不接受，已回退） |
| C | **服务器 Cache-Control 头** | 常见建议；[Argon 缓存行为](https://argonsys.com/microsoft-cloud/library/managing-pac-script-configuration-in-microsoft-edge/) | 服务器 | 已有该头；实测对 Edge 内存缓存无效（保持现状即可） |
| D | **Edge 策略 `WinHttpProxyResolverEnabled=1`** | [Microsoft Learn 官方策略](https://learn.microsoft.com/en-us/deployedge/microsoft-edge-policies/winhttpproxyresolverenabled)；Argon Scenario 2B | HKLM 策略 + 重启 Edge | 改为 Windows(WinHTTP) 拉取/执行 PAC，可能改变缓存行为；验证新规则是否更快生效 |
| E | **手动/脚本打开 `edge://net-internals/#proxy` Re-apply** | [Super User](https://superuser.com/questions/343445/how-to-force-chrome-to-reload-proxy-configuration-file) | 辅助脚本/GUI | 用户点一次 Re-apply 即生效（社区公认，非自动化） |
| F | **更新 `Connections\DefaultConnectionSettings` 二进制块** | [StackOverflow 格式说明](https://stackoverflow.com/questions/4283027/whats-the-format-of-the-defaultconnectionsettings-value-in-the-windows-registry) | 脚本（复杂） | 让 Windows UI/Chromium 感知“真实设置变更”，即使地址不变 |
| G | **彻底重启 Edge / taskkill 所有 msedge.exe** | Argon Scenario 2A | 用户动作 | 100% 生效（最可靠，用户体验差） |
| H | **规避裸主域抖动：访问/添加 `www.`** | 本次实测 | 用户/规则 | 用 `www.coolinet.net` 稳定访问（绕过上游代理对裸主域不稳） |

---

## 2. 测试记录（分支 → 结果 → 处置）

| # | 分支 | 结果 | 处置 |
| --- | --- | --- | --- |
| C | （基线，无分支） | 头已存在；Edge 仍缓存 | 不采用（已在基线） |
| B | `test/proxy-refresh-notify` 之前的 `cache-bust`（已回退） | 能强制重读，但污染“脚本地址” | 回退（用户不接受） |
| A | `test/proxy-refresh-notify`（已回退） | 脚本可执行、地址固定；但无法单独解决裸主域抖动；无法在本环境证明 Edge 行为 | 回退 |
| D | `test/policy-winhttp-resolver`（已回退） | 写 HKLM 需要管理员，当前会话被拒（UnauthorizedAccess），无法在本环境 E2E；需提权后在 Edge 重启验证 | 回退（待提权再测） |
| E | `test/helper-open-netinternals`（已回退） | 语法通过；能打开 Re-apply 页面，但属人工操作，不能自动修复 | 回退（可作未来 GUI 辅助按钮） |
| F | 待测（复杂度高） | — | — |

---

## 3. 下一步执行顺序

1. **D：WinHttpProxyResolverEnabled 策略**
   - 分支：`test/policy-winhttp-resolver`
   - 脚本：写 `HKLM\Software\Policies\Microsoft\Edge\UseWinHttpProxyResolver=1`
   - 测试：尝试写入（需管理员）；若无法写入或 Edge 无感 → 回退
2. **E：net-internals 辅助脚本**
   - 分支：`test/helper-open-netinternals`
   - 脚本：`Start-Process msedge "edge://net-internals/#proxy"`
   - 测试：语法/可执行；该方案本质是“人工一步”，不作为自动修复 → 验证后视情况回退
3. **F：DefaultConnectionSettings**（可选，复杂度高）
   - 若 D/E 都不行再考虑

---

## 4. 结论与建议（持续更新）
- 软件侧：规则/PAC/代理链路已证明正常；
- 浏览器侧：Edge 内存缓存是“新规则不生效”的主因；
- 额外发现：`coolinet.net` 裸主域经代理不稳定，建议用 `www.coolinet.net` 或向代理商核实。