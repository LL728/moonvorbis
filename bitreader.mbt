// bitreader.mbt
//
// LSB-first 位读取器（least-significant-bit first）。
//
// Vorbis 的比特流采用 LSB-first 顺序：每个字节内最低位（bit 0）最先被读取，
// 跨字节时也是低位字节先读。这与绝大多数格式（PNG、JPEG、网络协议等）使用的
// MSB-first 顺序相反，因此不能复用常见位读取实现，必须单独实现。
//
// 这是整个 OGG/Vorbis 解码器最底层的原语，codebook、floor、residue 的解码
// 全部建立在它之上。

///|
/// LSB-first 位读取器。
///
/// * `data` : 底层字节序列（只读）
/// * `pos` : 当前读取位置，单位是位，从 0 开始计数
struct BitReader {
  data : Bytes
  mut pos : Int
}

///|
/// 用给定的字节序列构造一个从第 0 位开始读取的位读取器。
pub fn BitReader::new(data : Bytes) -> BitReader {
  { data, pos: 0, }
}

///|
/// 返回底层字节序列的总位数（`data.length() * 8`）。
pub fn BitReader::total_bits(self : BitReader) -> Int {
  self.data.length() * 8
}

///|
/// 返回当前位位置。
pub fn BitReader::tell(self : BitReader) -> Int {
  self.pos
}

///|
/// 返回剩余可读位数。
pub fn BitReader::remaining_bits(self : BitReader) -> Int {
  self.total_bits() - self.pos
}

///|
/// 将读取位置移动到 `pos` 位处（用于回退或跳跃）。
pub fn BitReader::seek(self : BitReader, pos : Int) -> Unit {
  guard! pos >= 0 && pos <= self.total_bits()
  self.pos = pos
}

///|
/// 读取 1 位，返回 0 或 1（LSB-first）。
pub fn BitReader::read_bit(self : BitReader) -> Int {
  let byte = self.data.unsafe_get(self.pos >> 3).to_int()
  let shift = self.pos & 7
  self.pos += 1
  (byte >> shift) & 1
}

///|
/// 连续读取 `n` 位（LSB-first，`0 <= n <= 32`），返回无符号整数结果。
///
/// 读取到的第 1 位进入结果的 bit 0（最低位），第 2 位进入 bit 1，依此类推。
pub fn BitReader::read_bits(self : BitReader, n : Int) -> Int {
  guard! n >= 0 && n <= 32
  let mut result = 0
  for i in 0..<n {
    result = result | (self.read_bit() << i)
  }
  result
}

///|
/// 跳过 `n` 位。
pub fn BitReader::skip(self : BitReader, n : Int) -> Unit {
  guard! n >= 0
  self.pos += n
}

///|
/// 将读取位置对齐到下一个字节边界。
///
/// 若当前位置恰好落在字节边界上则不做任何事；否则向前跳过当前字节内
/// 剩余的位数（即 `8 - (pos mod 8)`）。
pub fn BitReader::byte_align(self : BitReader) -> Unit {
  let rem = self.pos & 7
  if rem != 0 {
    self.pos += 8 - rem
  }
}
