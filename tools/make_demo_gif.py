#!/usr/bin/env python3
"""把 demo/record.html 的一段流程录成 GIF，供 README 内嵌。

页面按 `?t=<毫秒>` 把流程画到某一刻，因此每一帧都是一次独立的无头截图，
不需要屏幕录制，结果可复现。解码是真的：页面确实加载 wasm、确实解了
demo/sample.ogg，波形与元信息都来自解码结果。

用法：
    python -m http.server 8000          # 在仓库根目录起服务
    python tools/make_demo_gif.py

需要 Pillow 与 Edge（或 Chrome）。
"""

import argparse
import os
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

from PIL import Image

sys.stdout.reconfigure(encoding="utf-8")

ROOT = Path(__file__).resolve().parent.parent

EDGE_CANDIDATES = [
    r"C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe",
    r"C:\Program Files\Microsoft\Edge\Application\msedge.exe",
    "/usr/bin/microsoft-edge",
    "/usr/bin/google-chrome",
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
]

# (时刻毫秒, 本帧显示时长毫秒)。时刻按 record.js 里的时间线取。
FRAMES = [
    (0, 700),  # 正在加载解码器…
    (700, 700),
    (1500, 700),  # 解码器已就绪
    (2200, 700),
    (2600, 400),  # 选中 sample.ogg，开始解码
    (2900, 400),
    (3200, 400),
    (3500, 300),
    (3800, 700),  # 解码完成，波形出现
    (4100, 300),  # 播放头扫过
    (4500, 280),
    (4900, 280),
    (5300, 280),
    (5700, 280),
    (6100, 280),
    (6500, 280),
    (6900, 280),
    (7300, 280),
    (7700, 280),
    (8100, 280),
    (8300, 500),
]


def find_browser(explicit):
    if explicit:
        return explicit
    for path in EDGE_CANDIDATES:
        if os.path.exists(path):
            return path
    found = shutil.which("msedge") or shutil.which("chrome")
    if found:
        return found
    raise SystemExit("找不到 Edge / Chrome，请用 --browser 指定可执行文件路径")


def shoot(browser, url, out_path, profile_dir, width, height, budget, timeout):
    """抓一帧，成功返回 True。每次都用独立的 user-data-dir，否则连续的实例
    会互相锁住。"""
    if os.path.exists(out_path):
        os.remove(out_path)
    cmd = [
        browser,
        "--headless=new",
        "--disable-gpu",
        "--no-sandbox",
        "--hide-scrollbars",
        "--no-first-run",
        "--no-default-browser-check",
        "--disable-extensions",
        "--disable-dev-shm-usage",
        f"--user-data-dir={profile_dir}",
        f"--window-size={width},{height}",
        f"--virtual-time-budget={budget}",
        f"--screenshot={out_path}",
        url,
    ]
    try:
        subprocess.run(
            cmd,
            timeout=timeout,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return False
    return os.path.exists(out_path) and os.path.getsize(out_path) > 0


def content_box(paths, fallback):
    """所有帧非白像素范围的并集，外加一点留白——各帧高度不同，必须统一裁。"""
    left, top, right, bottom = None, None, None, None
    for path in paths:
        # 缩略后再找边界，够用且快得多
        small = Image.open(path).convert("L").resize((180, 195))
        mask = small.point(lambda v: 255 if v < 250 else 0)
        box = mask.getbbox()
        if box is None:
            continue
        sx = Image.open(path).width / 180
        sy = Image.open(path).height / 195
        box = (
            int(box[0] * sx),
            int(box[1] * sy),
            int(box[2] * sx),
            int(box[3] * sy),
        )
        left = box[0] if left is None else min(left, box[0])
        top = box[1] if top is None else min(top, box[1])
        right = box[2] if right is None else max(right, box[2])
        bottom = box[3] if bottom is None else max(bottom, box[3])
    if left is None:
        return fallback
    pad = 16
    return (max(0, left - pad), max(0, top - pad), right + pad, bottom + pad)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--base", default="http://127.0.0.1:8000/demo/record.html")
    ap.add_argument("--out", default=str(ROOT / "demo" / "demo.gif"))
    ap.add_argument("--browser", default=None)
    ap.add_argument("--width", type=int, default=720)
    ap.add_argument("--height", type=int, default=780)
    ap.add_argument("--budget", type=int, default=8000, help="虚拟时间预算（毫秒）")
    ap.add_argument("--timeout", type=int, default=90, help="单帧截图超时（秒）")
    ap.add_argument("--retries", type=int, default=2, help="单帧截图失败后的重试次数")
    ap.add_argument("--scale", type=int, default=560, help="输出宽度（像素）")
    ap.add_argument("--colors", type=int, default=64)
    args = ap.parse_args()

    browser = find_browser(args.browser)
    print(f"浏览器：{browser}")

    tmp = Path(tempfile.mkdtemp(prefix="moonvorbis-gif-"))
    shots = []
    for index, (t, _) in enumerate(FRAMES):
        path = tmp / f"f{index:03d}.png"
        url = f"{args.base}?t={t}"
        # 无头浏览器偶发卡住不出图，重试时换一个 profile 目录——上一次
        # 那个可能还留着锁
        for attempt in range(args.retries + 1):
            ok = shoot(
                browser,
                url,
                path,
                tmp / f"profile{index:03d}-{attempt}",
                args.width,
                args.height,
                args.budget,
                args.timeout,
            )
            if ok:
                break
            print(f"    第 {attempt + 1} 次截图没出图，重试", flush=True)
        else:
            raise SystemExit(f"截图反复失败：t={t}ms")
        shots.append(path)
        print(f"  帧 {index + 1}/{len(FRAMES)}  t={t}ms", flush=True)

    box = content_box(shots, (0, 0, args.width, args.height))
    print(f"裁剪区域：{box}")

    scale = args.scale / (box[2] - box[0])
    size = (args.scale, round((box[3] - box[1]) * scale))

    crops = [Image.open(p).convert("RGB").crop(box).resize(size, Image.LANCZOS)
             for p in shots]

    # 共用一套调色板，否则每帧各调各的，帧与帧之间的底色会抖
    strip = Image.new("RGB", (size[0], size[1] * len(crops)))
    for i, im in enumerate(crops):
        strip.paste(im, (0, i * size[1]))
    palette = strip.quantize(colors=args.colors, method=Image.MEDIANCUT)

    frames = [im.quantize(palette=palette, dither=Image.FLOYDSTEINBERG)
              for im in crops]

    out = Path(args.out)
    frames[0].save(
        out,
        save_all=True,
        append_images=frames[1:],
        duration=[d for _, d in FRAMES],
        loop=0,
        optimize=True,
        disposal=1,
    )
    total = sum(d for _, d in FRAMES) / 1000
    print(f"写入 {out}（{out.stat().st_size / 1024:.0f} KB，"
          f"{len(frames)} 帧，{total:.1f} 秒，{size[0]}×{size[1]}）")
    shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    main()
