// vorbis_comment.mbt
//
// Vorbis Comment header（每个 Vorbis 流的第二个 packet）解析。
// 包含 vendor 字符串与若干 "KEY=value" 形式的元数据（如 TITLE、ARTIST）。

///|
/// Vorbis comment 元数据。
pub struct VorbisComment {
  vendor : String
  comments : Array[String]
}

///|
/// 解析 Comment header packet，返回 vendor 与 comment 列表。
///
/// 字符串按 UTF-8 解码（`@utf8.decode_lossy`），无效字节替换为 U+FFFD，
/// 与 Vorbis comment 的 UTF-8 编码约定相符。
pub fn VorbisComment::parse(packet : Bytes) -> Result[VorbisComment, String] {
  if packet.length() < 11 {
    return Err("truncated Vorbis comment header")
  }
  // magic: \x03 "vorbis"
  if packet.unsafe_get(0) != b'\x03' ||
    packet.unsafe_get(1) != b'v' ||
    packet.unsafe_get(2) != b'o' ||
    packet.unsafe_get(3) != b'r' ||
    packet.unsafe_get(4) != b'b' ||
    packet.unsafe_get(5) != b'i' ||
    packet.unsafe_get(6) != b's' {
    return Err("not a Vorbis comment header")
  }

  let mut pos = 7
  // vendor 字符串
  let vendor_len = packet.unsafe_read_uint32_le(pos).reinterpret_as_int()
  pos += 4
  if vendor_len < 0 || packet.length() < pos + vendor_len {
    return Err("truncated vendor string")
  }
  let vendor = @utf8.decode_lossy(packet.exact_view(start=pos, end=pos + vendor_len))
  pos += vendor_len

  // comment 数量
  if packet.length() < pos + 4 {
    return Err("truncated comment count")
  }
  let n_comments = packet.unsafe_read_uint32_le(pos).reinterpret_as_int()
  pos += 4
  if n_comments < 0 {
    return Err("invalid comment count")
  }

  // 逐个 comment：4 字节长度 + UTF-8 字符串
  let comments : Array[String] = []
  for _ in 0..<n_comments {
    if packet.length() < pos + 4 {
      return Err("truncated comment length")
    }
    let len = packet.unsafe_read_uint32_le(pos).reinterpret_as_int()
    pos += 4
    if len < 0 || packet.length() < pos + len {
      return Err("truncated comment string")
    }
    comments.push(@utf8.decode_lossy(packet.exact_view(start=pos, end=pos + len)))
    pos += len
  }

  Ok({ vendor, comments })
}
