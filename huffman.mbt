// huffman.mbt
//
// Vorbis codebook 的 Huffman 解码表：从码长构建码字，并按码字匹配解码。

/// 32 位位反转。
fn bit_reverse(x : UInt) -> UInt {
  let mut r = 0U
  let mut v = x
  for _ in 0..<32 {
    r = (r << 1) | (v & 1U)
    v = v >> 1
  }
  r
}

/// 从码长数组计算每个 entry 的码字（Vorbis canonical Huffman，码字已 bit_reverse）。
/// 码长 <= 0 的 entry 视为 hole，码字保持 0。
fn compute_codewords(lengths : Array[Int]) -> Result[Array[UInt], String] {
  let n = lengths.length()
  let codewords : Array[UInt] = []
  for _ in 0..<n {
    codewords.push(0U)
  }
  // 找第一个有码长的 entry
  let mut k = 0
  while k < n && lengths[k] <= 0 {
    k += 1
  }
  if k == n {
    return Ok(codewords)
  }
  // available[i]：长度为 i 的可用码字（左对齐到 32 位）
  let available : Array[UInt] = []
  for _ in 0..<32 {
    available.push(0U)
  }
  codewords[k] = 0U
  for i in 1..=lengths[k] {
    available[i] = 1U << (32 - i)
  }
  for i in (k + 1)..<n {
    let z = lengths[i]
    if z <= 0 {
      continue
    }
    let mut zz = z
    while zz > 0 && available[zz] == 0U {
      zz -= 1
    }
    if zz == 0 {
      return Err("invalid codebook lengths")
    }
    let res = available[zz]
    available[zz] = 0U
    codewords[i] = bit_reverse(res)
    let mut y = z
    while y > zz {
      available[y] = res + (1U << (32 - y))
      y -= 1
    }
  }
  Ok(codewords)
}

///|
/// 可复用的 Huffman 解码表。
///
/// 字段均为排序后（按码字值升序）的码字、码长与对应 entry 索引。
pub struct HuffmanTable {
  codewords : Array[UInt]
  lengths : Array[Int]
  symbols : Array[Int]
}

/// 由码长数组构建解码表。
pub fn HuffmanTable::build(lengths : Array[Int]) -> Result[HuffmanTable, String] {
  let codewords = match compute_codewords(lengths) {
    Ok(c) => c
    Err(e) => return Err(e)
  }
  let table_codewords : Array[UInt] = []
  let table_lengths : Array[Int] = []
  let table_symbols : Array[Int] = []
  for i in 0..<lengths.length() {
    if lengths[i] > 0 {
      table_codewords.push(codewords[i])
      table_lengths.push(lengths[i])
      table_symbols.push(i)
    }
  }
  Ok({ codewords: table_codewords, lengths: table_lengths, symbols: table_symbols })
}

/// 逐位读取并匹配码字，返回对应 entry 索引；未匹配返回错误。
pub fn HuffmanTable::decode(self : HuffmanTable, br : BitReader) -> Result[Int, String] {
  let mut acc : UInt = 0U
  for n in 0..<32 {
    acc = acc | (br.read_bit().reinterpret_as_uint() << n)
    for i in 0..<self.codewords.length() {
      if self.lengths[i] == n + 1 && self.codewords[i] == acc {
        return Ok(self.symbols[i])
      }
    }
  }
  Err("invalid huffman code")
}
