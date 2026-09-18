// codebook.mbt
//
// Vorbis codebook 解析。
//
// codebook 是 Vorbis setup header 里最复杂的数据结构，用于 Huffman 解码与
// 向量量化（VQ）。包含：头部字段、每个 entry 的码长、以及可选的 lookup table。

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
/// 整数幂 `base^exp`。
fn pow_int(base : Int, exp : Int) -> Int {
  let mut result = 1
  for _ in 0..<exp {
    result = result * base
  }
  result
}

///|
/// lookup type 1 的 lookup values 数量：`round(entries^(1/dim))`。
/// 用整数运算求 `r` 使得 `r^dim` 最接近 `entries`，避免浮点误差。
fn lookup1_values(entries : Int, dim : Int) -> Int {
  let mut r = 1
  while pow_int(r, dim) <= entries {
    r += 1
  }
  let lo = pow_int(r - 1, dim)
  let hi = pow_int(r, dim)
  if entries - lo < hi - entries {
    r - 1
  } else {
    r
  }
}

///|
/// 解析后的 codebook（含码长与 lookup table）。
///
/// 字段含义：
/// * `lengths` : 每个 entry 的码长，hole（sparse 中未使用）用 0 表示；
/// * `lookup_type` : 0（无 lookup）、1 或 2；
/// * `multiplicands` : lookup table 的量化值（lookup type > 0 时非空）。
pub struct Codebook {
  dimensions : Int
  entries : Int
  lengths : Array[Int]
  lookup_type : Int
  min_value : Float
  delta_value : Float
  value_bits : Int
  sequence_flag : Int
  multiplicands : Array[Int]
}

///|
/// 从 `br` 的当前位置解析一个 codebook。
///
/// 失败返回错误描述（sync 不符 / entry 溢出 / 不支持的 lookup 类型或 lattice 编码）。
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

  // lookup table
  let lookup_type = br.read_bits(4)
  let mut min_value : Float = 0
  let mut delta_value : Float = 0
  let mut value_bits = 0
  let mut sequence_flag = 0
  let multiplicands : Array[Int] = []
  if lookup_type != 0 {
    if lookup_type != 1 && lookup_type != 2 {
      return Err("reserved codebook lookup type")
    }
    min_value = Float::reinterpret_from_uint(br.read_bits(32).reinterpret_as_uint())
    delta_value = Float::reinterpret_from_uint(br.read_bits(32).reinterpret_as_uint())
    value_bits = br.read_bits(4) + 1
    sequence_flag = br.read_bits(1)
    let n_values = if lookup_type == 1 {
      lookup1_values(entries, dimensions)
    } else {
      entries * dimensions
    }
    if sequence_flag == 1 {
      // lattice 编码暂不支持
      return Err("lattice codebook not yet supported")
    }
    for _ in 0..<n_values {
      multiplicands.push(br.read_bits(value_bits))
    }
  }

  Ok(
    {
      dimensions,
      entries,
      lengths,
      lookup_type,
      min_value,
      delta_value,
      value_bits,
      sequence_flag,
      multiplicands,
    },
  )
}
