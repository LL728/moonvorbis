// codebook.mbt
//
// Vorbis codebook 解析（第一阶段：头部 + 码长）。
//
// codebook 是 Vorbis setup header 里最复杂的数据结构，用于 Huffman 解码与
// 向量量化（VQ）。本阶段先解析头部字段与每个 entry 的码长；
// lookup table 与 Huffman 解码表的构建放在后续阶段。

///|
/// `ilog(v)`：表示 `v` 所需的位数，即 `floor(log2(v)) + 1`（`v > 0` 时）。
/// 用于 ordered codebook 的游程长度读取。
fn ilog(v : Int) -> Int {
  let mut ret = 0
  let mut x = v
  while x > 0 {
    ret += 1
    x = x >> 1
  }
  ret
}

///|
/// 解析后的 codebook 头部（含每个 entry 的码长，hole 用 0 表示）。
pub struct Codebook {
  dimensions : Int
  entries : Int
  lengths : Array[Int]
}

///|
/// 从 `br` 的当前位置解析一个 codebook 头部。
///
/// 失败返回错误描述（sync 不符 / entry 溢出）。
pub fn Codebook::parse(br : BitReader) -> Result[Codebook, String] {
  // sync pattern 必须为 0x564342（"BCV" 的小端字节序）
  let sync = br.read_bits(24)
  if sync != 0x564342 {
    return Err("bad codebook sync")
  }
  let dimensions = br.read_bits(16)
  let entries = br.read_bits(24)
  let ordered = br.read_bits(1)
  let sparse = if ordered == 1 { 0 } else { br.read_bits(1) }

  let lengths : Array[Int] = []
  if ordered == 1 {
    // ordered codebook：码长按游程编码
    let mut current_entry = 0
    let mut current_length = br.read_bits(5) + 1
    while current_entry < entries {
      let n = br.read_bits(ilog(entries - current_entry))
      if current_entry + n > entries {
        return Err("codebook entry overflow")
      }
      for _ in 0..<n {
        lengths.push(current_length)
        current_entry += 1
      }
      if current_entry >= entries {
        break
      }
      current_length = br.read_bits(5) + 1
    }
  } else {
    // unordered codebook：每个 entry 一个码长，sparse 时可能有 hole
    for _ in 0..<entries {
      if sparse == 1 {
        if br.read_bits(1) == 1 {
          lengths.push(br.read_bits(5) + 1)
        } else {
          lengths.push(0)
        }
      } else {
        lengths.push(br.read_bits(5) + 1)
      }
    }
  }

  Ok({ dimensions, entries, lengths })
}
