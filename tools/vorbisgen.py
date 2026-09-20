#!/usr/bin/env python3
"""生成 Vorbis 测试流，用于验证 moonvorbis 在缺少现成素材时的那部分能力。

libvorbis 自 1.0 起只用 floor 1 和 residue type 1/2，官方也不存在覆盖全部
规范的测试向量，所以 floor 0、residue type 0、sequence_p 码本这些分支拿不到
真实文件。这个脚本按规范自己拼出比特流，再由两个独立实现去解同一份数据：

    生成器 --写--> OGG/Vorbis --+--> moonvorbis --> PCM A
                                |
                                +--> libsndfile/libvorbis --> PCM B

两边一致才说明规范读对了。若生成的流 libvorbis 直接拒收，那也是立刻可见的
信号——比写完了无从验证强。

用法:
    python tools/vorbisgen.py out.ogg               # 默认：floor 1 + residue 2
    python tools/vorbisgen.py out.ogg --residue 0   # 换 residue 类型
    python tools/vorbisgen.py out.ogg --floor 0     # 换 floor 类型
"""

import argparse
import struct
import sys
from pathlib import Path

if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")


class BitWriter:
    """LSB-first 位写入器，与 Vorbis 的位序一致（与 bitreader.mbt 互为逆）。"""

    def __init__(self):
        self.buf = bytearray()
        self.acc = 0
        self.nbits = 0

    def write(self, value: int, bits: int) -> None:
        """写入 bits 位，低位在前。"""
        value &= (1 << bits) - 1
        self.acc |= value << self.nbits
        self.nbits += bits
        while self.nbits >= 8:
            self.buf.append(self.acc & 0xFF)
            self.acc >>= 8
            self.nbits -= 8

    def write_bytes(self, data: bytes) -> None:
        for b in data:
            self.write(b, 8)

    def flush(self) -> bytes:
        """补零到字节边界并返回完整字节串。"""
        if self.nbits > 0:
            self.buf.append(self.acc & 0xFF)
            self.acc = 0
            self.nbits = 0
        return bytes(self.buf)


# OGG 的 CRC-32：多项式 0x04C11DB7，不反转、无初值、无结尾异或
def _crc_table() -> list[int]:
    table = []
    for i in range(256):
        r = i << 24
        for _ in range(8):
            r = ((r << 1) ^ 0x04C11DB7) & 0xFFFFFFFF if r & 0x80000000 else (r << 1) & 0xFFFFFFFF
        table.append(r)
    return table


_CRC_TABLE = _crc_table()


def ogg_crc(data: bytes) -> int:
    crc = 0
    for b in data:
        crc = ((crc << 8) & 0xFFFFFFFF) ^ _CRC_TABLE[((crc >> 24) & 0xFF) ^ b]
    return crc


def make_page(serial: int, seq: int, header_type: int, granule: int,
              packets: list[bytes]) -> bytes:
    """把若干 packet 拼成一个 OGG 页。每个 packet 用 segment table 描述长度。"""
    segtable = bytearray()
    body = bytearray()
    for pkt in packets:
        n = len(pkt)
        # 长度是 255 的整数倍时，需要一个 0 长度的 segment 来收尾
        while n >= 255:
            segtable.append(255)
            n -= 255
        segtable.append(n)
        body += pkt

    if len(segtable) > 255:
        raise ValueError("packet 过多，单页放不下")

    header = bytearray()
    header += b"OggS"
    header.append(0)                                   # version
    header.append(header_type)
    header += struct.pack("<q", granule)
    header += struct.pack("<I", serial)
    header += struct.pack("<I", seq)
    header += b"\x00\x00\x00\x00"                      # CRC 占位
    header.append(len(segtable))
    header += segtable
    page = bytes(header) + bytes(body)

    crc = ogg_crc(page)
    return page[:22] + struct.pack("<I", crc) + page[26:]


def ident_header(channels: int, sample_rate: int, bs0_exp: int, bs1_exp: int) -> bytes:
    b = BitWriter()
    b.write(0x01, 8)
    b.write_bytes(b"vorbis")
    b.write(0, 32)                                  # version
    b.write(channels, 8)
    b.write(sample_rate, 32)
    b.write(0, 32)                                  # bitrate max
    b.write(0, 32)                                  # bitrate nominal
    b.write(0, 32)                                  # bitrate min
    b.write(bs0_exp, 4)                             # blocksize_0 是 2 的幂次
    b.write(bs1_exp, 4)
    b.write(1, 1)                                   # framing
    return b.flush()


def comment_header(vendor: str = "moonvorbis-vorbisgen") -> bytes:
    b = BitWriter()
    b.write(0x03, 8)
    b.write_bytes(b"vorbis")
    raw = vendor.encode("utf-8")
    b.write(len(raw), 32)
    b.write_bytes(raw)
    b.write(0, 32)                                  # 无 comment
    b.write(1, 1)                                   # framing
    return b.flush()


def make_setup(residue_type: int, floor_type: int,
               partition_size: int = 128, dim: int = 1) -> bytes:
    """构造 setup header。

    最小可用配置：2 个 codebook（一个当 classbook，一个当 residue 的 VQ 书）、
    1 个 floor、1 个 residue、1 个 mapping、1 个 mode。
    """
    b = BitWriter()
    b.write(0x05, 8)
    b.write_bytes(b"vorbis")

    # ---- codebook ----
    b.write(1, 8)  # codebook 数量 - 1 = 1，即 2 个

    # codebook 0：classbook。dimensions=1, entries=2, unordered, 非 sparse,
    # 码长 [1,1]（完备 Huffman），lookup_type=0（不做 VQ）
    _write_codebook(b, dimensions=1, lengths=[1, 1], lookup_type=0)

    # codebook 1：residue 的 VQ 书，也兼作 floor1 的 subclass 书（两者都只是
    # 取码字号）。lookup_type=2，multiplicands 取各维不同的非零值，这样 residue
    # 落在哪个位置才看得出来——全 0 的话通路写错了输出也一样。
    # delta 取 2 的负幂，乘出来的残差是精确值；幅度也压得够小，免得 IMDCT
    # 之后超出 16 位 WAV 的范围——削波会让两边「看起来不一致」，白白误判。
    mults = [(i % 3) + 1 for i in range(2 * dim)]
    _write_codebook(
        b, dimensions=dim, lengths=[1, 1], lookup_type=2,
        min_value=0.0, delta_value=2.0 ** -7, value_bits=2, sequence_flag=0,
        multiplicands=mults,
    )

    # ---- time domain transform ----
    b.write(0, 6)  # time count - 1 = 0，即 1 个
    b.write(0, 16)  # time type 必须为 0

    # ---- floor ----
    b.write(0, 6)  # floor count - 1 = 0，即 1 个
    if floor_type == 1:
        _write_floor1(b)
    else:
        _write_floor0(b)

    # ---- residue ----
    b.write(0, 6)  # residue count - 1 = 0，即 1 个
    _write_residue(b, residue_type, partition_size=partition_size)

    # ---- mapping ----
    # 字段顺序：type(16) → submaps flag(1) → coupling flag(1) → reserved(2)
    # → [submaps>1 时每声道的 mux] → 每 submap 的 time/floor/residue(各 8 位)。
    # 末尾没有 reserved，别多写。
    b.write(0, 6)   # mapping count - 1 = 0，即 1 个
    b.write(0, 16)  # mapping type 0
    b.write(0, 1)   # submaps flag = 0 → submaps = 1
    b.write(0, 1)   # coupling flag = 0 → 不读 coupling
    b.write(0, 2)   # reserved
    b.write(0, 8)   # submap 的 time config
    b.write(0, 8)   # submap 用的 floor 号
    b.write(0, 8)   # submap 用的 residue 号

    # ---- mode ----
    b.write(0, 6)   # mode count - 1 = 0，即 1 个
    b.write(0, 1)   # blockflag = 0 → 用 blocksize_0
    b.write(0, 16)  # window type
    b.write(0, 16)  # transform type
    b.write(0, 8)   # 该 mode 用的 mapping 号

    b.write(1, 1)   # framing
    return b.flush()


def _write_codebook(b: BitWriter, dimensions: int, lengths: list[int],
                    lookup_type: int, min_value: float = 0.0,
                    delta_value: float = 0.0, value_bits: int = 1,
                    sequence_flag: int = 0,
                    multiplicands: list[int] | None = None) -> None:
    b.write(0x564342, 24)          # sync
    b.write(dimensions, 16)
    b.write(len(lengths), 24)      # entries
    b.write(0, 1)                  # ordered = 0
    b.write(0, 1)                  # sparse = 0
    for L in lengths:
        b.write(L - 1, 5)
    b.write(lookup_type, 4)
    if lookup_type != 0:
        b.write(_float32_pack(min_value), 32)
        b.write(_float32_pack(delta_value), 32)
        b.write(value_bits - 1, 4)
        b.write(sequence_flag, 1)
        for m in multiplicands or []:
            b.write(m, value_bits)


def _float32_pack(value: float) -> int:
    """Vorbis 专用 32 位浮点打包。

    解出来的值是 `mantissa * 2^(exp - 788)`，其中 mantissa 就是 21 位字段的
    整数值，**不带隐含的前导 1**。所以要把尾数顶到 [2^20, 2^21) 才不丢精度；
    若按 IEEE 那样只存小数部分，像 0.25 这种正好落在 2 的整数次幂上的值会编成
    0，解出来也真的是 0——生成器静默地把整段残差抹平。
    """
    if value == 0.0:
        return 0
    sign = 0x80000000 if value < 0 else 0
    m = abs(float(value))
    exp = 788
    while m < (1 << 20):
        m *= 2.0
        exp -= 1
    while m >= (1 << 21):
        m /= 2.0
        exp += 1
    return sign | ((exp & 0x7FF) << 21) | (int(round(m)) & 0x1FFFFF)


def _write_floor1(b: BitWriter) -> None:
    """floor 1 的最小配置。

    注意 class 的数量不是显式字段：读方对 class 的循环次数是「partition class
    列表的最大值 + 1」，partitions=0 时一个 class 都不会读。所以想有 1 个 class
    就必须让 partitions >= 1 并在列表里写上它。
    """
    b.write(1, 16)   # floor type 1
    b.write(1, 5)    # partitions = 1
    b.write(0, 4)    # partition class list[0] = 0 → max_class = 0，读 1 个 class
    b.write(0, 3)    # class 0 dimensions - 1 = 0 → dimensions = 1
    b.write(0, 2)    # class 0 subclasses = 0
    b.write(2, 8)    # class 0 的 subclass book 号：读方会 -1，故写 book+1 = 2
    b.write(3, 2)    # multiplier - 1 = 3 → multiplier = 4
    b.write(4, 4)    # rangebits = 4，X 初值为 0 与 1<<4 = 16
    # X 列表：前两个固定，之后 partitions × class_dimensions 个
    b.write(8, 4)    # class 0 的 1 个 X 值


def _write_floor0(b: BitWriter) -> None:
    """floor 0 的配置。order 等字段按规范顺序写入。"""
    b.write(0, 16)   # floor type 0
    b.write(0, 8)    # order
    b.write(0, 16)   # rate
    b.write(0, 16)   # bark_map_size
    b.write(0, 6)    # amplitude_bits
    b.write(0, 8)    # amplitude_offset
    b.write(0, 4)    # number_of_books - 1 = 0 → 1 本书
    b.write(0, 8)    # book list[0]


def _write_residue(b: BitWriter, residue_type: int, begin: int = 0,
                   end: int = 1 << 20, partition_size: int = 128) -> None:
    """end 写得足够大，让读方按自己的块长钳到 actual_size，省得两边对不齐。"""
    b.write(residue_type, 16)
    b.write(begin, 24)
    b.write(end, 24)
    b.write(partition_size - 1, 24)
    b.write(0, 6)    # classifications - 1 = 0 → 1 个
    b.write(0, 8)    # classbook 号
    # cascade：1 个 classification，低位 3 bit，无高位
    b.write(1, 3)    # low bits = 1 → 第 0 个 pass 有书
    b.write(0, 1)    # bitflag = 0，不读高位
    b.write(1, 8)    # pass 0 用的 codebook 号（即 codebook 1）


def floor1_packet(b: BitWriter) -> None:
    """写一个「floor 已使用」的 floor1 packet。

    multiplier=4 → range = 64，故前两个 Y 各占 ilog(64)-1 = 6 位。取 60 让 floor
    曲线接近满幅——曲线若为 0，residue 乘上去就什么都不剩，通路的对错看不出来。
    X 列表是 [0, 16, 8]，排序后为 [0, 8, 16]，于是第三个点的邻居是前两个点，
    pred 落在它们之间；写 1 让 step2_flag 置位，曲线才真正被画出来。
    """
    b.write(1, 1)    # nonzero
    b.write(60, 6)   # finalY[0]
    b.write(60, 6)   # finalY[1]
    b.write(1, 1)    # subclass book 1 的码字 1 → val = 1 ≠ 0


def residue_payload(b: BitWriter, channels: int, residue_type: int,
                    part_read: int, partition_size: int, dim: int) -> None:
    """写 residue 数据。

    cascade 只给 classification 0 配了 pass 0 的书，所以每个 partition 的
    classbook 码字固定写 0。type 2 多声道走交错路径，classbook 每 partition 只读
    一个；type 0/1 走通用路径，**每个声道各读一个**——位流长度因此不同。
    """
    def vq_codewords():
        k = 0
        while k < partition_size:
            b.write(1, 1)   # VQ 码字 1
            k += dim

    for _ in range(part_read):
        if residue_type == 2 and channels > 1:
            b.write(0, 1)                       # classbook：每 partition 一个
            vq_codewords()                      # 交错路径按 part_size 分完为止
        else:
            for _ in range(channels):
                b.write(0, 1)                   # classbook：每声道一个
            for _ in range(channels):
                vq_codewords()


def build(sample_rate: int, channels: int, residue_type: int,
          floor_type: int, n_audio_packets: int = 4, trim: int = 0,
          active: bool = False, partition_size: int = 128,
          dim: int = 1, blocksize_exp: int = 0) -> bytes:
    """拼出完整的 OGG 流。

    active=False 时音频 packet 只带「floor 未使用」位，内容为静音——用来验证
    容器与头部；active=True 时写入真实的 floor 与 residue 数据，残差通路才会被
    走到。
    """
    serial = 0x12345678
    if blocksize_exp == 0:
        blocksize_exp = 8 if active else 6
    bs_exp = blocksize_exp

    pages = []
    pages.append(make_page(serial, 0, 0x02, 0,
                           [ident_header(channels, sample_rate, bs_exp, bs_exp)]))
    pages.append(make_page(serial, 1, 0x00, 0,
                           [comment_header(),
                            make_setup(residue_type, floor_type,
                                       partition_size, dim)]))

    # 音频 packet：首 bit 是 packet type（0 = audio），其后是 mode 号（只有 1 个
    # mode，占 0 位），再往后才是各声道的数据。mode 的 blockflag=0，所以不必写
    # prev/next 窗标志。
    pkt = BitWriter()
    pkt.write(0, 1)   # packet type
    if not active:
        for _ in range(channels):
            pkt.write(0, 1)
    else:
        for _ in range(channels):
            floor1_packet(pkt)
        # 解 residue 时传进去的是 n2 = 块长的一半；type 2 的系数每声道两份，
        # 读方据此再把 actual_size 翻倍，partition 数也跟着翻倍。
        n_res = (1 << bs_exp) // 2
        actual_size = n_res * 2 if residue_type == 2 else n_res
        part_read = actual_size // partition_size
        residue_payload(pkt, channels, residue_type, part_read,
                        partition_size, dim)
    audio = pkt.flush()

    # granule position 是「到该页为止已产出的 PCM 帧数」。Vorbis 的第一个音频
    # packet 不产出样本（它是重叠相加的前导），所以第 k 个 packet 之后是
    # (k-1) × blocksize/2 帧。
    # trim 把末页 granule 调小，制造「最后一个块只用到一部分」的情形——真实文件
    # 几乎总是这样，也正是 granule 裁剪真正起作用的场合。
    block = 1 << bs_exp
    seq = 2
    for k in range(n_audio_packets):
        granule = k * (block // 2)
        if k == n_audio_packets - 1:
            granule -= trim
        pages.append(make_page(serial, seq, 0x00, granule, [audio]))
        seq += 1

    # 末页置 EOS
    last = bytearray(pages[-1])
    last[5] |= 0x04
    last[22:26] = b"\x00\x00\x00\x00"
    last[22:26] = struct.pack("<I", ogg_crc(bytes(last)))
    pages[-1] = bytes(last)

    return b"".join(pages)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("out", help="输出的 .ogg 路径")
    ap.add_argument("--residue", type=int, default=2, choices=[0, 1, 2],
                    help="residue 类型（默认 2）")
    ap.add_argument("--floor", type=int, default=1, choices=[0, 1],
                    help="floor 类型（默认 1）")
    ap.add_argument("--rate", type=int, default=44100)
    ap.add_argument("--channels", type=int, default=1)
    ap.add_argument("--packets", type=int, default=4, help="音频 packet 数")
    ap.add_argument("--trim", type=int, default=0,
                    help="末页 granule 减去的样本数，用于验证尾部裁剪")
    ap.add_argument("--active", action="store_true",
                    help="写入真实 floor 与 residue 数据，而不是静音")
    ap.add_argument("--partition-size", type=int, default=128)
    ap.add_argument("--dim", type=int, default=1, help="residue VQ 书的维度")
    ap.add_argument("--blocksize-exp", type=int, default=0,
                    help="块长 2 的幂次（0 表示按 active 自动选）")
    args = ap.parse_args()

    data = build(args.rate, args.channels, args.residue, args.floor,
                 args.packets, args.trim, args.active,
                 args.partition_size, args.dim, args.blocksize_exp)
    Path(args.out).write_bytes(data)
    print(f"已写入 {args.out}：{len(data)} 字节，"
          f"floor {args.floor}，residue {args.residue}，"
          f"{args.channels} 声道 {args.rate} Hz"
          f"{'，含数据' if args.active else '，静音'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
