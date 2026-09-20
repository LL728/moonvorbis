#!/usr/bin/env python3
"""扫一遍 granule position 的裁剪行为。

Vorbis 按块编码，最后一个 packet 往往解出超过原始长度的样本，必须按 OGG 页头的
granule position 裁掉。真实文件只能验证「某个具体长度」，说不清裁剪量本身对不对；
这里用 tools/vorbisgen.py 造流，让 packet 数与裁剪量各自独立变化，再看
moonvorbis 与 libvorbis 输出的帧数是否都落在预期值上。

    python tools/granule_sweep.py

需要 `numpy` 与 `soundfile`。
"""

import os
import subprocess
import sys
import tempfile
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

import soundfile as sf

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
BLOCK = 64

PACKET_COUNTS = (2, 4, 7)
TRIMS = (0, 1, 5, 17)


def decode(ogg: Path, wav: Path) -> None:
    subprocess.run(
        ["moon", "run", "cmd/main", "--target", "wasm-gc", "--", str(ogg), str(wav)],
        check=True, capture_output=True, encoding="utf-8", errors="replace",
        cwd=ROOT,
    )


def main() -> int:
    tmp = Path(tempfile.gettempdir())
    ogg, wav = tmp / "granule_sweep.ogg", tmp / "granule_sweep.wav"

    print(f"{'packets':>7} {'trim':>5} {'期望':>6} {'moonvorbis':>11} {'libvorbis':>10}")
    failures = 0
    for packets in PACKET_COUNTS:
        for trim in TRIMS:
            # 第 k 个音频 packet 之后产出 (k-1) 个半块，末页再减掉 trim。
            want = (packets - 1) * (BLOCK // 2) - trim
            subprocess.run(
                [sys.executable, str(HERE / "vorbisgen.py"), str(ogg),
                 "--packets", str(packets), "--trim", str(trim)],
                check=True, capture_output=True, cwd=ROOT,
            )
            decode(ogg, wav)
            got = sf.info(wav).frames
            ref = sf.info(ogg).frames
            ok = got == want == ref
            failures += 0 if ok else 1
            print(f"{packets:>7} {trim:>5} {want:>6} {got:>11} {ref:>10}"
                  f"  {'OK' if ok else '不一致'}")

    print("\n全部通过" if failures == 0 else f"\n{failures} 处不一致")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
