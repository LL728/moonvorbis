#!/usr/bin/env python3
"""用生成的残差数据扫 residue 的各条通路。

真实文件只会用到 residue type 2 的多声道交错路径，type 0 / type 1 的通用路径
和「type 0 与 type 1 的区别」都没有现成素材。这里让 tools/vorbisgen.py 写出
带真实 floor 与 residue 的流，再把同一份流交给 moonvorbis 与 libvorbis：

    两边都接受，且解出的 PCM 一致  →  通路读对了
    一边拒收或数值不同              →  立刻可见

注意 floor 未使用时 residue 一个比特都不读，所以素材必须带 floor 数据，否则
测的还是「什么都没走」。

    python tools/residue_sweep.py

需要 `numpy` 与 `soundfile`。
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import numpy as np
import soundfile as sf

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent

# (residue 类型, 声道数, partition_size, VQ 维度)
CASES = [
    (1, 1, 4, 2),
    (1, 2, 4, 2),
    (0, 1, 4, 2),
    (0, 2, 4, 2),
    (0, 1, 8, 4),
    (0, 2, 8, 4),
    (1, 1, 8, 4),
    (1, 2, 8, 4),
]


def generate(ogg: Path, residue: int, channels: int, ps: int, dim: int) -> None:
    subprocess.run(
        [sys.executable, str(HERE / "vorbisgen.py"), str(ogg), "--active",
         "--residue", str(residue), "--channels", str(channels),
         "--dim", str(dim), "--partition-size", str(ps)],
        check=True, capture_output=True, cwd=ROOT,
    )


def decode(ogg: Path, wav: Path) -> str:
    """返回错误信息，成功则为空串。

    CLI 失败时只打印一行「解码失败: ...」并不写输出文件，进程退出码仍是 0，
    所以这里既看输出也看文件在不在。
    """
    if wav.exists():
        wav.unlink()
    r = subprocess.run(
        ["moon", "run", "cmd/main", "--target", "wasm-gc", "--", str(ogg), str(wav)],
        capture_output=True, encoding="utf-8", errors="replace", cwd=ROOT,
    )
    out = (r.stdout + r.stderr).strip()
    if not wav.exists():
        lines = [ln for ln in out.splitlines() if ln.strip()]
        return lines[-1] if lines else "没有输出文件"
    return ""


def read(path: Path):
    data, _ = sf.read(str(path), dtype="float64", always_2d=True)
    return data


def main() -> int:
    tmp = Path(tempfile.gettempdir())
    ogg, wav = tmp / "residue_sweep.ogg", tmp / "residue_sweep.wav"

    failures = 0
    for residue, channels, ps, dim in CASES:
        label = f"type {residue} / {channels}ch / partition {ps} / dim {dim}"
        generate(ogg, residue, channels, ps, dim)
        err = decode(ogg, wav)
        if err:
            print(f"{label:<42} moonvorbis 失败：{err}")
            failures += 1
            continue
        try:
            ref, got = read(ogg), read(wav)
        except Exception as e:
            print(f"{label:<42} 读取失败：{e}")
            failures += 1
            continue
        n = min(len(ref), len(got))
        if ref.shape != got.shape:
            print(f"{label:<42} 形状不符 {ref.shape} vs {got.shape}")
            failures += 1
            continue
        peak = float(np.abs(ref).max())
        if peak == 0.0:
            print(f"{label:<42} 参考输出是静音——素材没激励到通路")
            failures += 1
            continue
        if peak > 1.0:
            # 我的解码器输出 16 位 WAV，超出 ±1 会被钳掉，两边就没法比了。
            print(f"{label:<42} 参考峰值 {peak:.3f} 超出量程，素材幅度要调小")
            failures += 1
            continue
        corr = float(np.corrcoef(ref[:n, 0], got[:n, 0])[0, 1])
        # 逐声道取最差的那个
        for c in range(ref.shape[1]):
            corr = min(corr, float(np.corrcoef(ref[:n, c], got[:n, c])[0, 1]))
        ok = corr > 0.99
        failures += 0 if ok else 1
        print(f"{label:<42} 峰值 {peak:.4f}  corr {corr:.6f}"
              f"  {'OK' if ok else '不一致'}")

    print("\n全部通过" if failures == 0 else f"\n{failures} 处不一致")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
