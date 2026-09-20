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
/// lookup type 1 的 lookup values 数量：最大的 `r` 使 `r^dim <= entries`（即 floor(entries^(1/dim))）。
/// 用整数运算避免浮点误差。
fn lookup1_values(entries : Int, dim : Int) -> Int {
  let mut r = 0
  while pow_int(r + 1, dim) <= entries {
    r += 1
  }
  r
}

///|
/// Vorbis 专用的 32 位浮点解包：1 位符号 + 10 位指数 + 21 位尾数。
/// 值为 `mantissa * 2^(exponent - 788)`，与 IEEE 754 不同，不能按位重解释。
fn float32_unpack(x : UInt) -> Float {
  let mantissa = (x & 0x1fffffU).reinterpret_as_int()
  let sign = (x & 0x80000000U) != 0U
  let exp = ((x & 0x7fe00000U) >> 21).reinterpret_as_int()
  let res = if sign {
    Float::from_int(0 - mantissa)
  } else {
    Float::from_int(mantissa)
  }
  @math.scalbnf(res, exp - 788)
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
  multiplicands_f : Array[Float]
  huffman : HuffmanTable
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
    // ordered codebook：码长按游程编码，每次游程后 current_length 递增 1
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
      current_length += 1
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
  let multiplicands_f : Array[Float] = []
  if lookup_type != 0 {
    if lookup_type != 1 && lookup_type != 2 {
      return Err("reserved codebook lookup type")
    }
    min_value = float32_unpack(br.read_bits(32).reinterpret_as_uint())
    delta_value = float32_unpack(br.read_bits(32).reinterpret_as_uint())
    value_bits = br.read_bits(4) + 1
    sequence_flag = br.read_bits(1)
    if sequence_flag == 1 {
      // lattice 编码暂不支持
      return Err("lattice codebook not yet supported")
    }
    // 原始 lookup value 数量：type 1 是 r，type 2 是 entries*dim
    let n_raw = if lookup_type == 1 {
      lookup1_values(entries, dimensions)
    } else {
      entries * dimensions
    }
    let raw_f : Array[Float] = []
    for _ in 0..<n_raw {
      let v = br.read_bits(value_bits)
      multiplicands.push(v)
      raw_f.push(Float::from_int(v) * delta_value + min_value)
    }
    if lookup_type == 1 {
      // type 1：把 r 个原始值按 base-r unvectorize 展开成 entries*dim 个
      for j in 0..<entries {
        let mut div = 1
        for k in 0..<dimensions {
          let off = j / div % n_raw
          multiplicands_f.push(raw_f[off])
          if k + 1 < dimensions {
            div = div * n_raw
          }
        }
      }
    } else {
      // type 2：直接是 entries*dim
      for v in raw_f {
        multiplicands_f.push(v)
      }
    }
  }

  let huffman = match HuffmanTable::build(lengths) {
    Ok(h) => h
    Err(e) => return Err(e)
  }

  Ok({
    dimensions,
    entries,
    lengths,
    lookup_type,
    min_value,
    delta_value,
    value_bits,
    sequence_flag,
    multiplicands,
    multiplicands_f,
    huffman,
  })
}

///|
/// 标量解码一个码字，返回 entry 索引。
pub fn Codebook::decode_scalar(
  self : Codebook,
  br : BitReader,
) -> Result[Int, String] {
  self.huffman.decode(br)
}

///|
/// VQ 解码：解码一个 entry，把 lookup 值累加到 target[offset..offset+len]。
pub fn Codebook::decode_vq(
  self : Codebook,
  br : BitReader,
  target : Array[Float],
  offset : Int,
  len : Int,
) -> Result[Unit, String] {
  if self.lookup_type == 0 {
    return Err("codebook has no lookup table")
  }
  let z = match self.decode_scalar(br) {
    Ok(z) => z
    Err(e) => return Err(e)
  }
  let n = if len > self.dimensions { self.dimensions } else { len }
  let base = z * self.dimensions
  for i in 0..<n {
    target[offset + i] = target[offset + i] + self.multiplicands_f[base + i]
  }
  Ok(())
}

///|
/// 同 decode_vq，但分量之间隔着 step 个位置摆放，用于 residue type 0 的交织写法。
pub fn Codebook::decode_vq_step(
  self : Codebook,
  br : BitReader,
  target : Array[Float],
  offset : Int,
  len : Int,
  step : Int,
) -> Result[Unit, String] {
  if self.lookup_type == 0 {
    return Err("codebook has no lookup table")
  }
  let z = match self.decode_scalar(br) {
    Ok(z) => z
    Err(e) => return Err(e)
  }
  let n = if len > self.dimensions { self.dimensions } else { len }
  let base = z * self.dimensions
  for i in 0..<n {
    let at = offset + i * step
    if at >= 0 && at < target.length() {
      target[at] = target[at] + self.multiplicands_f[base + i]
    }
  }
  Ok(())
}
