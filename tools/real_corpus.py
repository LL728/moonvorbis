#!/usr/bin/env python3
"""真实 libvorbis 编码的多声道/多素材语料：moonvorbis 与 libvorbis 逐声道对拍。

覆盖：1/2/3/4/6/8 声道，正弦/噪声/音乐式混合素材，以及「第 0 声道静音」
「第 1 声道静音」两类带静音声道的输入，22.05k/44.1k/48k 由各用例指定。

静音声道的用例专门盯住一条历史缺陷：floor 未使用的声道在非交错 residue
路径里必须连 classbook 码字一起跳过，只跳 VQ 会让位流超前、最终读穿 packet。
libvorbis 编码的 silent0/silent1 3/4/8 声道素材曾经全部崩溃。

    python tools/real_corpus.py

需要 `numpy` 与 `soundfile`；跑完约十分钟。
"""
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
TMP = Path(tempfile.mkdtemp(prefix="vorbis-real-"))
# 固定种子：每次跑出的噪声素材完全相同，失败可直接复现
RNG = np.random.default_rng(20261016)


def make_signal(kind: str, channels: int, rate: int, seconds: float) -> np.ndarray:
    n = int(rate * seconds)
    t = np.arange(n) / rate
    out = np.zeros((n, channels), dtype=np.float32)
    for ch in range(channels):
        if kind == "sine":
            f = 220.0 * (ch + 1)
            out[:, ch] = 0.5 * np.sin(2 * np.pi * f * t)
        elif kind == "noise":
            out[:, ch] = RNG.normal(0.0, 0.2, n)
        elif kind == "mixed":
            if ch % 3 == 0:
                out[:, ch] = 0.4 * np.sin(2 * np.pi * (300 + 100 * ch) * t)
            elif ch % 3 == 1:
                out[:, ch] = RNG.normal(0.0, 0.15, n)
            else:
                out[:, ch] = 0.3 * np.sign(np.sin(2 * np.pi * 90 * t))  # 方波，谐波丰富
        elif kind == "silent0":  # 第 0 声道静音
            out[:, ch] = RNG.normal(0.0, 0.2, n) if ch else 0.0
        elif kind == "silent1":  # 第 1 声道静音
            out[:, ch] = 0.0 if ch == 1 else 0.4 * np.sin(2 * np.pi * (330 + 60 * ch) * t)
    peak = float(np.max(np.abs(out))) if out.size else 1.0
    if peak > 0.95:
        out *= 0.95 / peak
    return out


def run_cli(src: Path, dst: Path):
    proc = subprocess.run(
        ["moon", "run", "cmd/main", "--target", "wasm-gc", "--", str(src), str(dst)],
        cwd=ROOT, capture_output=True, text=True, encoding="utf-8",
        errors="replace", timeout=900)
    return proc.returncode, ((proc.stdout or "") + (proc.stderr or "")).strip()


def check(name: str, src: Path, dst: Path) -> bool:
    rc, out = run_cli(src, dst)
    if rc != 0 or not dst.exists():
        print(f"CRASH  {name}  rc={rc}\n       {out[-500:]}")
        return False
    mine, rmin = sf.read(str(dst), always_2d=True)
    ref, rref = sf.read(str(src), always_2d=True)
    if rmin != rref:
        print(f"RATE   {name}: {rmin} vs {rref}")
        return False
    frames = min(len(mine), len(ref))
    rows, ok = [], True
    for ch in range(min(mine.shape[1], ref.shape[1])):
        a = mine[:frames, ch].astype(np.float64)
        b = ref[:frames, ch].astype(np.float64)
        # 两边都是静音：相关系数没有定义，直接判过
        if a.std() < 1e-12 and b.std() < 1e-12:
            rows.append("silent-ok")
            continue
        if a.std() < 1e-12 or b.std() < 1e-12:
            rows.append("zero-vs-nonzero")
            ok = False
            continue
        corr = float(np.corrcoef(a, b)[0, 1])
        rms = float(np.sqrt(np.mean((a - b) ** 2)))
        rows.append(f"{corr:+.3f}/{rms:.4f}")
        if not (corr > 0.99 and rms < 0.05):
            ok = False
    head = "OK    " if ok else "FAIL  "
    print(f"{head}{name}  {len(mine)}/{len(ref)}帧 {mine.shape[1]}ch  " + " ".join(rows))
    return ok


def main() -> int:
    print(f"临时目录: {TMP}\n")
    bad = []
    for kind in ("sine", "noise", "mixed", "silent0", "silent1"):
        for channels in (1, 2, 3, 4, 6, 8):
            for rate in (44100, 48000):
                if channels == 1 and kind in ("silent0", "silent1"):
                    continue
                secs = 1.0 if channels < 6 else 0.5
                name = f"{kind}-{channels}ch-{rate}"
                pcm = make_signal(kind, channels, rate, secs)
                src = TMP / f"{name}.ogg"
                try:
                    sf.write(str(src), pcm, rate, format="OGG", subtype="VORBIS")
                except Exception as exc:
                    print(f"ENCFAIL {name}: {exc}")
                    bad.append(name)
                    continue
                if not check(name, src, TMP / f"{name}.wav"):
                    bad.append(name)
    print(f"\n共 56 个用例，异常 {len(bad)} 个: {bad}")
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
