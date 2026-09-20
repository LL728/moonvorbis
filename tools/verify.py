#!/usr/bin/env python3
"""交叉验证 moonvorbis 的解码结果。

生成已知内容的正弦波 OGG，用本解码器解出 WAV，再和 libvorbis 的解码结果
逐声道比较相关系数与 RMS 误差。

判据是连续量而非「成功/失败」：一个把幅度算错 80% 的解码器同样是「跑通了」，
只有相关系数能把它和真正正确的实现区分开。

用法:
    python tools/verify.py                  # 默认单声道 440 Hz
    python tools/verify.py --stereo         # 立体声，左右不同频率
    python tools/verify.py --noise          # 宽带噪声，覆盖更多 residue 分支
"""

import argparse
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np
import soundfile as sf

# Windows 控制台默认 GBK，中文与符号会直接抛 UnicodeEncodeError
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

REPO = Path(__file__).resolve().parent.parent
SAMPLE_RATE = 44100
DURATION = 1.0


def make_signal(stereo: bool, noise: bool) -> np.ndarray:
    """生成内容完全已知的测试信号。"""
    n = int(SAMPLE_RATE * DURATION)
    t = np.arange(n) / SAMPLE_RATE
    rng = np.random.default_rng(20260920)

    def channel(freq: float) -> np.ndarray:
        if noise:
            # 噪声频谱宽，能激励到更多 residue 分区
            return rng.normal(0.0, 0.2, n).astype(np.float32)
        return (0.6 * np.sin(2 * np.pi * freq * t)).astype(np.float32)

    if stereo:
        return np.stack([channel(440.0), channel(554.0)], axis=1)
    return channel(440.0).reshape(-1, 1)


def encode_ogg(pcm: np.ndarray, path: Path) -> None:
    sf.write(str(path), pcm, SAMPLE_RATE, format="OGG", subtype="VORBIS")


def decode_with_moonvorbis(src: Path, dst: Path) -> None:
    """调用命令行解码器。解码失败会抛出，不静默继续。"""
    proc = subprocess.run(
        ["moon", "run", "cmd/main", "--target", "wasm-gc", "--", str(src), str(dst)],
        cwd=REPO,
        capture_output=True,
        text=True,
        encoding="utf-8",
        errors="replace",
    )
    if proc.returncode != 0:
        sys.exit(f"解码器返回 {proc.returncode}\n{proc.stdout}\n{proc.stderr}")
    if not dst.exists():
        sys.exit(f"解码器没有产出 {dst}\n{proc.stdout}")


def compare(mine: np.ndarray, ref: np.ndarray) -> list[tuple[float, float]]:
    """逐声道返回 (相关系数, RMS 误差)。"""
    frames = min(len(mine), len(ref))
    out = []
    for ch in range(min(mine.shape[1], ref.shape[1])):
        a = mine[:frames, ch].astype(np.float64)
        b = ref[:frames, ch].astype(np.float64)
        # 相关系数：对幅度整体缩放不敏感，能区分「形状对但幅度错」
        corr = float(np.corrcoef(a, b)[0, 1])
        # RMS 误差：对幅度敏感，能抓出相关系数抓不到的增益错误
        rms = float(np.sqrt(np.mean((a - b) ** 2)))
        out.append((corr, rms))
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--stereo", action="store_true", help="生成立体声测试信号")
    ap.add_argument("--noise", action="store_true", help="用宽带噪声代替正弦波")
    ap.add_argument("--keep", action="store_true", help="保留中间文件以便手工检查")
    args = ap.parse_args()

    pcm = make_signal(args.stereo, args.noise)
    tmp = Path(tempfile.mkdtemp(prefix="moonvorbis-verify-"))
    src, dst = tmp / "source.ogg", tmp / "decoded.wav"

    encode_ogg(pcm, src)
    decode_with_moonvorbis(src, dst)

    mine, rate_mine = sf.read(str(dst), always_2d=True)
    ref, rate_ref = sf.read(str(src), always_2d=True)
    if rate_mine != rate_ref:
        sys.exit(f"采样率不一致: 解码 {rate_mine}, 原始 {rate_ref}")

    kind = "噪声" if args.noise else "正弦波"
    shape = "立体声" if args.stereo else "单声道"
    print(f"{shape} {kind}, {rate_mine} Hz, 原始 {len(ref)} 帧, 解码 {len(mine)} 帧\n")

    result = compare(mine, ref)
    ok = True
    for ch, (corr, rms) in enumerate(result):
        # 阈值定得宽松：Vorbis 是有损的，对齐也未必逐帧严丝合缝
        good = corr > 0.99 and rms < 0.05
        ok &= good
        print(f"  声道 {ch}:  相关系数 {corr:.4f}   RMS 误差 {rms:.4f}   {'OK' if good else 'FAIL'}")

    if args.keep:
        print(f"\n中间文件保留在 {tmp}")
    return 0 if ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
