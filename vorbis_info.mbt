// vorbis_info.mbt
//
// Vorbis Identification header（每个 Vorbis 流的第一个 packet）解析。
//
// 固定 30 字节，包含解码必需的基础参数：声道数、采样率、以及两个 block size。
// block size 是 2 的幂（64~8192），决定后续 floor/residue 解码时的频域窗口长度。

///|
/// Vorbis 流的基础信息。
pub struct VorbisInfo {
  channels : Int
  sample_rate : Int
  blocksize0 : Int
  blocksize1 : Int
}

///|
/// 解析 Identification header packet，返回流基础信息。
///
/// 失败返回错误描述（magic 不符 / 版本不支持 / block size 非法 / 缺 framing 标志 / 数据截断）。
pub fn VorbisInfo::parse(packet : Bytes) -> Result[VorbisInfo, String] {
  if packet.length() < 30 {
    return Err("truncated Vorbis identification header")
  }
  // magic: \x01 "vorbis"
  if packet.unsafe_get(0) != b'\x01' ||
    packet.unsafe_get(1) != b'v' ||
    packet.unsafe_get(2) != b'o' ||
    packet.unsafe_get(3) != b'r' ||
    packet.unsafe_get(4) != b'b' ||
    packet.unsafe_get(5) != b'i' ||
    packet.unsafe_get(6) != b's' {
    return Err("not a Vorbis identification header")
  }

  let br = BitReader::new(packet)
  br.skip(7 * 8) // 跳过 7 字节 magic
  let version = br.read_bits(32)
  if version != 0 {
    return Err("unsupported Vorbis version")
  }
  let channels = br.read_bits(8)
  let sample_rate = br.read_bits(32)
  // bitrate 字段（3 × 32 位）暂时跳过，后续如有需要再读取
  br.skip(32 * 3)
  let bsize0 = br.read_bits(4)
  let bsize1 = br.read_bits(4)
  if bsize0 < 6 || bsize0 > 13 || bsize1 < 6 || bsize1 > 13 || bsize0 > bsize1 {
    return Err("invalid blocksize")
  }
  let framing = br.read_bit()
  if framing != 1 {
    return Err("missing framing flag")
  }

  Ok({
    channels,
    sample_rate,
    blocksize0: 1 << bsize0,
    blocksize1: 1 << bsize1,
  })
}
