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
/// 按 key 取第一个匹配的 comment 值，找不到返回 `None`。
///
/// key 按 Vorbis 规范不区分 ASCII 大小写，`"title"` 与 `"TITLE"` 等价。
/// 同一个 key 出现多次时（规范允许，例如多个 ARTIST）返回文件中靠前的那个；
/// 需要全部取值时用 `get_all`。
pub fn VorbisComment::get(self : VorbisComment, key : String) -> String? {
  for tag in self.comments {
    match split_tag(tag) {
      Some((name, value)) =>
        if name.equal_ignore_ascii_case(key) {
          return Some(value)
        }
      None => ()
    }
  }
  None
}

///|
/// 按 key 取全部匹配的 comment 值，保持它们在文件中出现的顺序。
///
/// 规范允许同一 key 重复出现（如多位 ARTIST），这里不做去重也不做合并。
pub fn VorbisComment::get_all(
  self : VorbisComment,
  key : String,
) -> Array[String] {
  let out : Array[String] = []
  for tag in self.comments {
    match split_tag(tag) {
      Some((name, value)) =>
        if name.equal_ignore_ascii_case(key) {
          out.push(value)
        }
      None => ()
    }
  }
  out
}

///|
/// 把 `"KEY=value"` 按第一个 `=` 拆成 key 与 value。
///
/// 规范要求 key 由 ASCII 可打印字符组成且不含 `=`，因此按 code unit 扫 `=` 是安全的：
/// `=` 是 ASCII，切分点必定落在码元边界上，不会切开代理对。
/// 整条 comment 不含 `=` 时返回 `None`（规范不允许，但畸形流里可能出现）。
fn split_tag(tag : String) -> (String, String)? {
  match tag.find("=") {
    Some(i) => Some((tag[:i].to_owned(), tag[i + 1:].to_owned()))
    None => None
  }
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
  let vendor = @utf8.decode_lossy(
    packet.exact_view(start=pos, end=pos + vendor_len),
  )
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
    comments.push(
      @utf8.decode_lossy(packet.exact_view(start=pos, end=pos + len)),
    )
    pos += len
  }

  Ok({ vendor, comments, })
}
