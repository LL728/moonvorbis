#!/usr/bin/env python3
"""用生成的素材扫 floor 0。

floor 0 比 floor 1 更早被淘汰，libvorbis 自 1.0 起就不再产生它，stb_vorbis
干脆直接拒收（`VORBIS_feature_not_supported`）——也就是说这条通路没有任何
真实文件走过。这里让 tools/vorbisgen.py 写出带真实 LSP 系数的流，交给
moonvorbis 与 libvorbis 各解一遍：

    两边都接受，且解出的 PCM 一致  →  通路读对了

覆盖点：奇数阶与偶数阶走的是包络多项式的两个不同分支，都要走到；单声道与
多声道；不同采样率与 Bark 频带数；以及幅度为 0（标志位为 1 但本帧没有 floor
数据）这个 floor 0 特有的情形。

    python tools/floor0_sweep.py

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

# (阶数, 声道数, delta 的幂次, ampdb, 采样率, Bark 频带数, 幅度原始值)
#
# 阶数决定走包络多项式的哪个分支：偶数阶 p、q 各自成对，奇数阶要单独补一项。
# delta 逐个调过——floor 0 的包络在 LSP 系数之间会掉到接近零，增益随之飙高，
# 幅度不压下来就会超出 16 位量程，两边被钳之后再比就失去意义。阶数越高、
# 尖峰越陡，能用的 delta 越小。
CASES = [
    (2, 1, -13, 5, 44100, 64, -1),
    (3, 1, -22, 5, 44100, 64, -1),
    (4, 1, -14, 5, 44100, 64, -1),
    (5, 1, -12, 5, 44100, 64, -1),
    (4, 2, -14, 5, 44100, 64, -1),
    (3, 2, -22, 5, 44100, 64, -1),
    (4, 1, -9, 1, 44100, 64, -1),
    (4, 1, -11, 3, 22050, 32, -1),
    # 幅度为 0：标志位为 1，但本帧没有 floor 数据，声道应当静音
    (4, 1, -14, 5, 44100, 64, 0),
]


def generate(ogg: Path, case) -> None:
    order, channels, dexp, ampdb, rate, barkmap, amp_raw = case
    subprocess.run(
        [sys.executable, str(HERE / "vorbisgen.py"), str(ogg), "--active",
         "--floor", "0", "--order", str(order), "--channels", str(channels),
         "--delta-exp", str(dexp), "--ampdb", str(ampdb), "--rate", str(rate),
         "--bark-map-size", str(barkmap), "--amp-raw", str(amp_raw)],
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
    ogg, wav = tmp / "floor0_sweep.ogg", tmp / "floor0_sweep.wav"

    failures = 0
    for case in CASES:
        order, channels, dexp, ampdb, rate, barkmap, amp_raw = case
        label = f"order {order} 阶 / {channels}ch / {rate}Hz / bark {barkmap}"
        if ampdb != 5:
            label += f" / ampdb {ampdb}"
        if amp_raw == 0:
            label += " / 幅度 0"
        generate(ogg, case)
        err = decode(ogg, wav)
        if err:
            print(f"{label:<46} moonvorbis 失败：{err}")
            failures += 1
            continue
        try:
            ref, got = read(ogg), read(wav)
        except Exception as e:
            print(f"{label:<46} 读取失败：{e}")
            failures += 1
            continue
        if ref.shape != got.shape:
            print(f"{label:<46} 形状不符 {ref.shape} vs {got.shape}")
            failures += 1
            continue
        n = min(len(ref), len(got))
        peak = float(np.abs(ref).max())

        if amp_raw == 0:
            # 这一组期望的是「解出来是静音」，两边都得是零
            ok = peak == 0.0 and float(np.abs(got).max()) == 0.0
            failures += 0 if ok else 1
            print(f"{label:<46} 参考峰值 {peak:.4f}  "
                  f"{'OK（两边皆静音）' if ok else '不一致'}")
            continue

        if peak == 0.0:
            print(f"{label:<46} 参考输出是静音——素材没激励到通路")
            failures += 1
            continue
        if peak > 1.0:
            # 我的解码器输出 16 位 WAV，超出 ±1 会被钳掉，两边就没法比了。
            print(f"{label:<46} 参考峰值 {peak:.3f} 超出量程，素材幅度要调小")
            failures += 1
            continue

        corr = float(np.corrcoef(ref[:n, 0], got[:n, 0])[0, 1])
        for c in range(ref.shape[1]):
            corr = min(corr, float(np.corrcoef(ref[:n, c], got[:n, c])[0, 1]))
        ok = corr > 0.99
        failures += 0 if ok else 1
        print(f"{label:<46} 峰值 {peak:.4f}  corr {corr:.6f}"
              f"  {'OK' if ok else '不一致'}")

    print("\n全部通过" if failures == 0 else f"\n{failures} 处不一致")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
