#!/usr/bin/env python3
"""Generate docs/ARCHITECTURE-LIVE-SERVICE.svg — architecture diagram of the
REAL running PAC service, from live probe data (read-only) collected 2026-08-19.
Regenerate with:  python3 scripts/gen-architecture-svg.py
"""

W = 1280
H = 1060


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def rect(x, y, w, h, fill, stroke, sw=1.5, dash=None, rx=8):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    return (f'<rect x="{x}" y="{y}" width="{w}" height="{h}" rx="{rx}" '
            f'fill="{fill}" stroke="{stroke}" stroke-width="{sw}"{d}/>')


def text(x, y, lines, color="#111827", size=13, anchor="middle", weight="normal",
         line_h=18, bold_first=False):
    out = [f'<text x="{x}" y="{y}" font-family="Microsoft YaHei,PingFang SC,sans-serif" '
           f'font-size="{size}" fill="{color}" text-anchor="{anchor}">']
    for i, ln in enumerate(lines):
        wgt = weight if not (bold_first and i == 0) else "bold"
        out.append(f'  <tspan x="{x}" dy="{line_h if i else 0}" font-weight="{wgt}">{esc(ln)}</tspan>')
    out.append('</text>')
    return "\n".join(out)


def label(mx, my, txt, color="#374151", size=12):
    return (f'<text x="{mx}" y="{my}" font-family="Microsoft YaHei,PingFang SC,sans-serif" '
            f'font-size="{size}" fill="{color}" text-anchor="middle">{esc(txt)}</text>')


def arrow(x1, y1, x2, y2, color="#475569", sw=1.8, dash=None, marker=True):
    d = f' stroke-dasharray="{dash}"' if dash else ''
    m = '' if not marker else ' marker-end="url(#arr)"'
    return (f'<line x1="{x1}" y1="{y1}" x2="{x2}" y2="{y2}" stroke="{color}" '
            f'stroke-width="{sw}"{d}{m}/>')


def poly(points, color="#475569", sw=1.8, dash=None, marker=True):
    ps = " ".join(f"{x},{y}" for x, y in points)
    d = f' stroke-dasharray="{dash}"' if dash else ''
    m = '' if not marker else ' marker-end="url(#arr)"'
    return f'<polyline points="{ps}" fill="none" stroke="{color}" stroke-width="{sw}"{d}{m}/>'


def band(x, y, title, color):
    return (f'<text x="{x}" y="{y}" font-family="Microsoft YaHei,PingFang SC,sans-serif" '
            f'font-size="14" fill="{color}" font-weight="bold">{esc(title)}</text>')


# palette
C_LINE = "#2F9E63"   # real service
C_GEN = "#3B82F6"    # generator
C_DATA = "#E6A817"   # data / rules (amber)
C_EX = "#9AA5B1"     # external
C_ERR = "#D64545"
C_PARA = "#94A3B8"   # parallel / optional

parts = []
parts.append(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" '
             f'viewBox="0 0 {W} {H}" font-family="Microsoft YaHei,PingFang SC,sans-serif">')
parts.append('''<defs>
<marker id="arr" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
  <path d="M0,0 L10,5 L0,10 Z" fill="#475569"/>
</marker>
<marker id="arr2" viewBox="0 0 10 10" refX="9" refY="5" markerWidth="7" markerHeight="7" orient="auto-start-reverse">
  <path d="M0,0 L10,5 L0,10 Z" fill="#D64545"/>
</marker>
</defs>''')
parts.append(f'<rect x="0" y="0" width="{W}" height="{H}" fill="#FFFFFF"/>')



# ---------- Band 1 : startup ----------
parts.append(band(24, 92, "① 启动 / 自启（控制面）", "#1F6FEB"))
# S1 login
parts.append(rect(40, 104, 150, 74, "#EFF6FF", "#1F6FEB"))
parts.append(text(115, 128, ["Windows", "登录"], "#1F2937", 14, "middle", "normal", 22))
# S2 task
parts.append(rect(240, 104, 250, 74, "#FFF7E6", "#E6A817"))
parts.append(text(365, 126, ["计划任务 PACServer", "(登录触发 · 失败自动重试×3)"], "#1F2937", 13, "middle", "normal", 21))
# S3 serve_pac process
parts.append(rect(530, 104, 270, 74, "#E9F7EF", "#2F9E63", sw=2))
parts.append(text(665, 124, ["pythonw.exe"], "#1F2937", 13, "middle"))
parts.append(text(665, 148, ["serve_pac.py  (PID 8808)"], "#125A37", 13, "middle", "bold"))
# S4 manual bat
parts.append(rect(850, 104, 210, 74, "#F8FAFC", "#C4CBD4", dash="6 4"))
parts.append(text(955, 126, ["start_pac_server.bat", "(手动启动 · 可选)"], "#6B7280", 12, "middle", "normal", 20))
# arrows
parts.append(arrow(190, 141, 236, 141))
parts.append(arrow(490, 141, 526, 141))
parts.append(label(390, 133, "启动", "#2F9E63", 12))
parts.append(arrow(850, 124, 806, 124, "#9AA5B1", dash="5 4"))

# ---------- Band 2 : service & data ----------
parts.append(band(24, 288, "② 服务与数据（127.0.0.1:8765）", "#1F6FEB"))
# C1 serve_pac
parts.append(rect(40, 300, 260, 116, "#E9F7EF", "#2F9E63", sw=2))
parts.append(text(170, 324, ["serve_pac.py", "127.0.0.1:8765", "ThreadingTCPServer · daemon", "只提供 /proxy.pac · 无 /healthz"], "#1F2937", 13, "middle", "normal", 21))
# D1 proxy.pac (amber, has issue)
parts.append(rect(360, 300, 280, 116, "#FEF3C7", "#E6A817", sw=2))
parts.append(text(500, 324, ["C:\\proxy\\proxy.pac", "genpac 3.0.1 · 125 KB", "⚠ 只烧入 3/5 条规则（过期快照）"], "#7A4A00", 13, "middle", "normal", 21))
# G1 genpac
parts.append(rect(700, 300, 300, 116, "#E0F2FE", "#3B82F6", sw=2))
parts.append(text(850, 324, ["genpac 3.0.1（PAC 生成器）", "输出 = C:\\proxy\\proxy.pac", "No 自动化 → 改完规则必须手工重跑"], "#1E40AF", 13, "middle", "normal", 21))
# RT1 runtime artifacts red
parts.append(rect(1040, 300, 200, 116, "#FDEBEB", "#D64545", sw=2, dash="6 4"))
parts.append(text(1140, 324, ["运行时产物 / C:\\proxy\\", "pac-server.pid = 28940", "⚠ 过期：实际监听 PID 8808", "stdout / stderr.log"], "#A33A3A", 12, "middle", "normal", 20))
# arrows C1->D1, D1<-G1
parts.append(arrow(300, 355, 356, 355))
parts.append(label(330, 345, "读取", "#374151", 11))
parts.append(arrow(700, 355, 644, 355))
# -- genpac inputs (one panel, one arrow into genpac) --
parts.append(rect(700, 446, 300, 148, "#F1F5F9", "#94A3B8", sw=1.2))
parts.append(rect(700, 446, 300, 26, "#E2E8F0", "#94A3B8", sw=1.2, rx=6))
parts.append(text(850, 463, ["genpac 输入"], "#334155", 12, "middle", "bold"))
parts.append(text(850, 493, ["① GFWList 在线源（raw.githubusercontent.com）"], "#334155", 12, "middle"))
parts.append(text(850, 521, ["② C:\\proxy\\user-rules.txt · 5 条"], "#7A4A00", 12, "middle", "bold"))
parts.append(text(850, 540, ["   fuzzysoulfate… / jcomic.net / 18comic.vip"], "#7A4A00", 10, "middle"))
parts.append(text(850, 570, ["③ 上游代理参数  PROXY 10.10.10.19:8080"], "#334155", 12, "middle"))
parts.append(arrow(850, 442, 850, 420))
parts.append(label(858, 434, "输入", "#6B7280", 11))

# ---------- Band 3 : consumer chain ----------
parts.append(band(24, 662, "③ 消费链（WinINET / 系统代理）", "#1F6FEB"))
# REG
parts.append(rect(40, 676, 300, 92, "#EFF6FF", "#1F6FEB"))
parts.append(text(190, 700, ["Windows 注册表（HKCU Internet Settings）"], "#1F2937", 12, "middle", "bold"))
parts.append(text(190, 722, ["AutoConfigURL = http://127.0.0.1:8765/proxy.pac"], "#1F2937", 12, "middle"))
parts.append(text(190, 744, ["ProxyEnable=0 · ProxyServer 残留 10.10.10.19:8080"], "#6B7280", 11, "middle"))
# BR
parts.append(rect(400, 676, 230, 92, "#FAF5FF", "#9C4FA5"))
parts.append(text(515, 700, ["浏览器 / 应用", "(WinINET / 系统代理)"], "#1F2937", 13, "middle", "normal", 22))
# DEC
parts.append(rect(690, 676, 300, 92, "#FFF7E6", "#E6A817", sw=2))
parts.append(text(840, 700, ["PAC 决策  FindProxyForURL()"], "#7A4A00", 13, "middle", "bold"))
parts.append(text(840, 722, ["内网 / 本机 → DIRECT"], "#1F2937", 12, "middle"))
parts.append(text(840, 744, ["命中规则 → proxy · 未命中 → DIRECT"], "#1F2937", 12, "middle"))
# arrows
parts.append(arrow(340, 722, 396, 722))
parts.append(label(368, 713, "生效", "#374151", 11))
parts.append(arrow(630, 722, 686, 722))
parts.append(label(658, 713, "执行 PAC", "#374151", 11))
# BR -> serve_pac GET (polyline up the left side, through band2 empty space)
parts.append(poly([(515, 676), (515, 250), (170, 250), (170, 300)], marker=True))
parts.append(label(360, 242, "GET /proxy.pac（定期拉取）", "#2F9E63", 12))

# -- bottom row band 3 --
parts.append(rect(110, 810, 260, 66, "#E9F7EF", "#2F9E63", sw=2))
parts.append(text(240, 834, ["命中 → 上游 LAN 代理"], "#125A37", 13, "middle", "bold"))
parts.append(text(240, 857, ["10.10.10.19:8080"], "#125A37", 13, "middle"))
parts.append(rect(560, 810, 260, 66, "#F8FAFC", "#C4CBD4", dash="6 4"))
parts.append(text(690, 834, ["未命中 → DIRECT", "直连"], "#374151", 13, "middle", "normal", 20))
parts.append(rect(900, 810, 300, 66, "#EFF6FF", "#1F6FEB"))
parts.append(text(1050, 834, ["外网 / 被墙站点"], "#1F2937", 13, "middle", "bold"))

parts.append(arrow(370, 843, 896, 843))
parts.append(arrow(820, 843, 896, 843))

# ---------- Band 4 : ops & parallel ----------
parts.append(band(24, 908, "④ 运维脚本 与 平行参考实现", "#6B7280"))
parts.append(rect(40, 920, 560, 96, "#F0FDF4", "#18A058", sw=1.5, dash="7 5"))
parts.append(text(320, 942, [".hermes 运维脚本（控制面，不经 GUI）"], "#125A37", 12, "middle", "bold"))
parts.append(text(320, 965, ["switch_to_pac.ps1 开启 · check_proxy.ps1 诊断"], "#334155", 12, "middle"))
parts.append(text(320, 988, ["remove/rollback_env.ps1 清理代理环境变量（鸣潮）"], "#334155", 12, "middle"))
parts.append(text(320, 1008, ["setup_pac_autostart.ps1 建任务 · start_pac_server.bat 手动启"], "#334155", 12, "middle"))
parts.append(rect(660, 920, 580, 96, "#F8FAFC", "#C4CBD4", sw=1.5, dash="7 5"))
parts.append(text(950, 942, ["平行参考实现（不在主链路 · 勿当运行基线）"], "#6B7280", 12, "middle", "bold"))
parts.append(text(950, 966, ["Rust GUI(egui) + src/pac_server.py + dist\\ + WindowsSplitPAC 任务（未注册）"], "#6B7280", 11, "middle"))
parts.append(text(950, 990, ["值得借鉴：备份/恢复、双语 UI、Test-*.ps1 测试脚本"], "#6B7280", 11, "middle"))



parts.append('</svg>')

svg = "\n".join(parts)
out = "docs/ARCHITECTURE-LIVE-SERVICE.svg"
with open(out, "w", encoding="utf-8") as f:
    f.write(svg)
print(f"wrote {out} ({len(svg)} bytes)")
