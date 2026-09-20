// floor0.mbt
//
// Vorbis floor 0：用 LSP（线谱对）系数描述频谱包络。
//
// floor 1 用一组关键点插值出包络，floor 0 则每帧给出 order 个 LSP 系数和一个
// 幅度，再按 Bark 刻度把系数映射到线性频点上求值，得到逐样本的增益曲线。
// 两者都只是「给出一条曲线，由 residue 乘上去」，区别在曲线的表示方式。

///|
/// floor0 的配置。
pub struct Floor0 {
  order : Int
  rate : Int
  bark_map_size : Int
  amplitude_bits : Int
  amplitude_offset : Int
  books : Array[Int]
}

///|
/// 线性频率到 Bark 频带的换算。
///
/// 常数按单精度取值再提升为双精度：参考实现里这些字面量都是 `f` 后缀的
/// float，参与运算时被提升到 double，用双精度的字面量会引入偏差。
fn to_bark(x : Double) -> Double {
  let a : Float = 0.00074
  let b : Float = 0.0000000185
  let c : Float = 0.0001
  let scale1 : Float = 13.1
  let scale2 : Float = 2.24
  scale1.to_double() * @math.atan(a.to_double() * x) +
  scale2.to_double() * @math.atan(x * x * b.to_double()) +
  c.to_double() * x
}

///|
/// 解析 floor0 配置。
///
/// `codebooks` 用于校验 book 编号，并要求被引用的码本带 lookup table
/// （maptype != 0）且维度大于 0——否则取不出 LSP 系数。
pub fn Floor0::parse(
  br : BitReader,
  codebooks : Array[Codebook],
) -> Result[Floor0, String] {
  let order = br.read_bits(8)
  let rate = br.read_bits(16)
  let bark_map_size = br.read_bits(16)
  let amplitude_bits = br.read_bits(6)
  let amplitude_offset = br.read_bits(8)
  let book_count = br.read_bits(4) + 1

  if order < 1 {
    return Err("floor0 order is zero")
  }
  if rate < 1 {
    return Err("floor0 rate is zero")
  }
  if bark_map_size < 1 {
    return Err("floor0 bark map size is zero")
  }

  let books : Array[Int] = []
  for _ in 0..<book_count {
    let number = br.read_bits(8)
    if number >= codebooks.length() {
      return Err("floor0 book index out of range")
    }
    if codebooks[number].lookup_type == 0 {
      return Err("floor0 book has no lookup table")
    }
    if codebooks[number].dimensions < 1 {
      return Err("floor0 book dimensions is zero")
    }
    books.push(number)
  }

  Ok({ order, rate, bark_map_size, amplitude_bits, amplitude_offset, books, })
}

///|
/// 解析一帧的 floor0 数据，返回 `order` 个 LSP 系数外加末尾的幅度。
///
/// 幅度为 0、book 号越界或比特流耗尽时返回 `None`——这几种情况在参考实现里
/// 都表示「本帧无 floor 数据」，对应声道按静音处理，而不是解码失败。
pub fn Floor0::decode(
  self : Floor0,
  br : BitReader,
  codebooks : Array[Codebook],
) -> Result[Array[Float]?, String] {
  if br.remaining_bits() < self.amplitude_bits {
    return Ok(None)
  }
  let amplitude_raw = br.read_bits(self.amplitude_bits)
  if amplitude_raw <= 0 {
    return Ok(None)
  }
  let max_value = (1 << self.amplitude_bits) - 1
  let amplitude = Float::from_int(amplitude_raw) /
    Float::from_int(max_value) *
    Float::from_int(self.amplitude_offset)

  let book_bits = ilog(self.books.length())
  if br.remaining_bits() < book_bits {
    return Ok(None)
  }
  let book_number = br.read_bits(book_bits)
  if book_number < 0 || book_number >= self.books.length() {
    return Ok(None)
  }
  let book = codebooks[self.books[book_number]]

  let lsp : Array[Float] = []
  for _ in 0..<self.order {
    lsp.push(0)
  }
  match book.decode_vq_set(br, lsp, 0, self.order) {
    Ok(_) => ()
    // 码字读尽同样按「本帧无 floor 数据」处理
    Err(_) => return Ok(None)
  }

  // 码本按维度分块给出系数：每一块都加上前一块最后一个值，累加量逐块传递。
  let mut j = 0
  let mut last : Float = 0.0
  while j < self.order {
    let mut k = 0
    while j < self.order && k < book.dimensions {
      lsp[j] = lsp[j] + last
      j += 1
      k += 1
    }
    last = lsp[j - 1]
  }

  lsp.push(amplitude)
  Ok(Some(lsp))
}

///|
/// 第二阶段：把 LSP 系数还原成完整增益曲线（长度 `n2`）。
///
/// 先按 Bark 刻度算出每个线性频点落在哪个频带，再对每个频带求一次
/// 分母多项式的值，同一频带内的样本共用这个结果。
///
/// 参考实现里多项式在单精度下计算，而取整频带、取余弦、最后取指数这几步
/// 都走了双精度——频带下标是取整来的，差一点就换一个频带，所以这里逐处
/// 按同样的精度处理，不统一成一种。
pub fn Floor0::synthesize(
  self : Floor0,
  memo : Array[Float],
  n2 : Int,
) -> Array[Float] {
  let order = self.order
  let bark_map_size = self.bark_map_size
  let pi : Double = 3.141592653589793
  let half_rate : Float = Float::from_int(self.rate) / 2.0

  // 频带映射：线性频点 j 对应的 Bark 频带下标。取值非负，截断即向下取整。
  let scale : Float = Float::from_double(
    Double::from_int(bark_map_size) / to_bark(half_rate.to_double()),
  )
  let band_map : Array[Int] = []
  for j in 0..<n2 {
    let linear : Float = half_rate / Float::from_int(n2) * Float::from_int(j)
    let mut band = (to_bark(linear.to_double()) * scale.to_double())
      .floor()
      .to_int()
    if band >= bark_map_size {
      band = bark_map_size - 1
    }
    band_map.push(band)
  }

  let lsp : Array[Float] = []
  for i in 0..<order {
    lsp.push(Float::from_double(2.0 * @math.cos(memo[i].to_double())))
  }
  let amplitude = memo[order]
  let amplitude_offset = self.amplitude_offset
  let wdel : Float = Float::from_double(pi / Double::from_int(bark_map_size))

  let curve : Array[Float] = []
  for _ in 0..<n2 {
    curve.push(0)
  }

  let mut i = 0
  while i < n2 {
    let band = band_map[i]
    let w : Float = Float::from_double(
      2.0 * @math.cos((wdel * Float::from_int(band)).to_double()),
    )
    let mut p : Float = 0.5
    let mut q : Float = 0.5
    let mut j = 1
    while j < order {
      q = q * (w - lsp[j - 1])
      p = p * (w - lsp[j])
      j += 2
    }
    if j == order {
      // 奇数阶：落单的最后一个系数单独乘一次
      q = q * (w - lsp[j - 1])
      p = p * (p * (4.0 - w * w))
      q = q * q
    } else {
      // 偶数阶：p、q 各自成对
      p = p * (p * (2.0 - w))
      q = q * (q * (2.0 + w))
    }
    let gain = Float::from_double(
      @math.exp(
        (
          amplitude.to_double() / (p + q).to_double().sqrt() -
          Double::from_int(amplitude_offset)
        ) *
        0.11512925,
      ),
    )

    curve[i] = gain
    i += 1
    while i < n2 && band_map[i] == band {
      curve[i] = gain
      i += 1
    }
  }
  curve
}
