#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
iOS Swift 源码静态自检（无 macOS 环境下的基本保障）：
- 检查每个 .swift 文件的花括号/圆括号平衡
- 检查协议方法与实现签名一致性（手工核对表）
- 检查 xcodegen project.yml / workflow YAML 可解析
"""
import re
import sys
from pathlib import Path

sys.stdout.reconfigure(encoding="utf-8", errors="replace")
ROOT = Path(__file__).resolve().parent
ok = True

# 1. 括号平衡（忽略字符串与注释的粗略扫描）
def strip_noise(src: str) -> str:
    out, i, n = [], 0, len(src)
    in_str = in_line = in_block = False
    while i < n:
        c = src[i]
        nxt = src[i + 1] if i + 1 < n else ""
        if in_line:
            if c == "\n":
                in_line = False
                out.append(c)
            i += 1
            continue
        if in_block:
            if c == "*" and nxt == "/":
                in_block = False
                i += 2
                continue
            i += 1
            continue
        if in_str:
            if c == "\\":
                i += 2
                continue
            if c == '"':
                in_str = False
            i += 1
            continue
        if c == "/" and nxt == "/":
            in_line = True
            i += 2
            continue
        if c == "/" and nxt == "*":
            in_block = True
            i += 2
            continue
        if c == '"':
            in_str = True
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


for f in sorted((ROOT / "Sources").glob("*.swift")):
    src = strip_noise(f.read_text("utf-8"))
    for a, b in [("{", "}"), ("(", ")"), ("[", "]")]:
        ca, cb = src.count(a), src.count(b)
        if ca != cb:
            print(f"[FAIL] {f.name}: {a}{b} 不平衡 {ca} vs {cb}")
            ok = False
    print(f"[ok] {f.name}: 括号平衡")

# 2. 关键一致性核对表（协议 <-> 实现）
checks = [
    ("ScreenCanvasView.swift", r"protocol CanvasDelegate", True),
    ("RemoteViewController.swift", r"func canvasPointerMove\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasLeftClick\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasDragStart\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasDragMove\(_ v: ScreenCanvasView, dxView", True),
    ("RemoteViewController.swift", r"func canvasDragEnd\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasTapAt\(_ v: ScreenCanvasView, at: CGPoint", True),
    ("RemoteViewController.swift", r"func canvasRightClickAt\(_ v: ScreenCanvasView, at: CGPoint\?\)", True),
    ("RemoteViewController.swift", r"func canvasTouchDragStart\(_ v: ScreenCanvasView, at: CGPoint", True),
    ("RemoteViewController.swift", r"func canvasTouchDragMove\(_ v: ScreenCanvasView, at: CGPoint", True),
    ("RemoteViewController.swift", r"func canvasTouchDragEnd\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasTwoFingerTap\(_ v: ScreenCanvasView", True),
    ("RemoteViewController.swift", r"func canvasScroll\(_ v: ScreenCanvasView, direction: Int", True),
    ("ScreenCanvasView.swift", r"func totalScale\(\) -> CGFloat", True),  # internal 可见
    ("WSClient.swift", r"didOpenWithProtocol protocol: String\?", True),
    ("WSClient.swift", r"didCloseWith closeCode: URLSessionWebSocketTask\.CloseCode", True),
]
for fname, pat, _ in checks:
    src = (ROOT / "Sources" / fname).read_text("utf-8")
    if not re.search(pat, src):
        print(f"[FAIL] {fname}: 缺少 {pat}")
        ok = False

# 3. YAML 可解析
import yaml
for yml in [ROOT / "project.yml", ROOT / ".github/workflows/build-ipa.yml"]:
    yaml_text = yml.read_text("utf-8")
    list(yaml.safe_load_all(yaml_text))
    print(f"[ok] {yml.name}: YAML 解析通过")

# 4. CI/构建配置陷阱
wf = (ROOT / ".github/workflows/build-ipa.yml").read_text("utf-8")
if re.search(r"runs-on:\s*macos-14\b", wf):
    print("[FAIL] workflow: macos-14 镜像已退役"); ok = False
else:
    print("[ok] workflow: runner 镜像未用 macos-14")
pj = (ROOT / "project.yml").read_text("utf-8")
msw = re.search(r"SWIFT_VERSION:\s*[\"']?([\d.]+)", pj)
if msw and msw.group(1) not in ("4.0", "4.2", "5.0", "6.0"):
    print(f"[FAIL] project.yml: SWIFT_VERSION {msw.group(1)} 不是合法语言模式"); ok = False
else:
    print("[ok] project.yml: SWIFT_VERSION 合法")

# 5. appendingPathComponent 带查询参数的陷阱（会把 ? 编码成 %3F）
for f in sorted((ROOT / "Sources").glob("*.swift")):
    src = f.read_text("utf-8")
    for m in re.finditer(r'appendingPathComponent\("([^"]*)"\)', src):
        if "?" in m.group(1):
            print(f"[FAIL] {f.name}: appendingPathComponent 含查询参数 -> {m.group(1)}")
            ok = False
print("[ok] appendingPathComponent 查询参数检查完成")

print("\n" + ("ALL IOS CHECKS PASSED" if ok else "CHECKS FAILED"))
sys.exit(0 if ok else 1)
