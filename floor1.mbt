// floor1.mbt
//
// Vorbis floor1 setup 解析与 decode 预计算。

/// floor1 的配置与预计算数据。
pub struct Floor1 {
  partitions : Int
  partition_class_list : Array[Int]
  class_dimensions : Array[Int]
  class_subclasses : Array[Int]
  class_masterbooks : Array[Int]
  subclass_books : Array[Array[Int]]
  multiplier : Int
  rangebits : Int
  x_list : Array[Int]
  sorted_order : Array[Int]
  neighbors : Array[Array[Int]]
}

/// 绝对值。
fn iabs(x : Int) -> Int {
  if x < 0 {
    -x
  } else {
    x
  }
}

/// 线性插值预测：在 (x0,y0)-(x1,y1) 线段上取 x 处的 y。
fn predict_point(x : Int, x0 : Int, x1 : Int, y0 : Int, y1 : Int) -> Int {
  let dy = y1 - y0
  let adx = x1 - x0
  let err = iabs(dy) * (x - x0)
  let off = err / adx
  if dy < 0 {
    y0 - off
  } else {
    y0 + off
  }
}

/// 按 x_list 的值对索引 [0..n) 做升序稳定排序（插入排序，n 很小）。
fn sort_indices(x_list : Array[Int]) -> Array[Int] {
  let n = x_list.length()
  let indices : Array[Int] = []
  for i in 0..<n {
    indices.push(i)
  }
  for i in 1..<n {
    let key = indices[i]
    let key_x = x_list[key]
    let mut j = i - 1
    while j >= 0 && x_list[indices[j]] > key_x {
      indices[j + 1] = indices[j]
      j -= 1
    }
    indices[j + 1] = key
  }
  indices
}

/// 求 key point `n` 在 x_list 中的左右最近邻居索引（比它小/大的最近者）。
fn neighbors_of(x_list : Array[Int], n : Int) -> Array[Int] {
  let mut low = -1
  let mut high = 65536
  let mut low_idx = 0
  let mut high_idx = 0
  for i in 0..<n {
    if x_list[i] > low && x_list[i] < x_list[n] {
      low = x_list[i]
      low_idx = i
    }
    if x_list[i] < high && x_list[i] > x_list[n] {
      high = x_list[i]
      high_idx = i
    }
  }
  [low_idx, high_idx]
}

/// 从 `br` 的当前位置解析一个 floor1 配置，并预计算 sorted_order 与 neighbors。
pub fn Floor1::parse(br : BitReader) -> Result[Floor1, String] {
  let partitions = br.read_bits(5)

  let partition_class_list : Array[Int] = []
  let mut max_class = -1
  for _ in 0..<partitions {
    let c = br.read_bits(4)
    partition_class_list.push(c)
    if c > max_class {
      max_class = c
    }
  }

  let class_dimensions : Array[Int] = []
  let class_subclasses : Array[Int] = []
  let class_masterbooks : Array[Int] = []
  let subclass_books : Array[Array[Int]] = []
  for _ in 0..<(max_class + 1) {
    let dim = br.read_bits(3) + 1
    class_dimensions.push(dim)
    let subclasses = br.read_bits(2)
    class_subclasses.push(subclasses)
    let masterbook = if subclasses != 0 { br.read_bits(8) } else { -1 }
    class_masterbooks.push(masterbook)
    let books : Array[Int] = []
    for _ in 0..<(1 << subclasses) {
      books.push(br.read_bits(8) - 1)
    }
    subclass_books.push(books)
  }

  let multiplier = br.read_bits(2) + 1
  let rangebits = br.read_bits(4)

  let x_list : Array[Int] = [0, 1 << rangebits]
  for i in 0..<partitions {
    let c = partition_class_list[i]
    for _ in 0..<class_dimensions[c] {
      x_list.push(br.read_bits(rangebits))
    }
  }

  // 预计算 sorted_order 与 neighbors
  let sorted_order = sort_indices(x_list)
  let values = x_list.length()
  let neighbors : Array[Array[Int]] = []
  for j in 0..<values {
    neighbors.push(neighbors_of(x_list, j))
  }

  Ok(
    {
      partitions,
      partition_class_list,
      class_dimensions,
      class_subclasses,
      class_masterbooks,
      subclass_books,
      multiplier,
      rangebits,
      x_list,
      sorted_order,
      neighbors,
    },
  )
}

/// floor1 第一阶段：读 amplitude 与 codebook 值，计算各关键点的 Y 值（finalY）。
pub fn Floor1::decode(self : Floor1, br : BitReader, codebooks : Array[Codebook]) -> Result[Array[Int], String] {
  let range_list = [256, 128, 86, 64]
  let range = range_list[self.multiplier - 1]
  let amp_bits = ilog(range) - 1

  let final_y : Array[Int] = []
  final_y.push(br.read_bits(amp_bits))
  final_y.push(br.read_bits(amp_bits))

  for j in 0..<self.partitions {
    let pclass = self.partition_class_list[j]
    let cdim = self.class_dimensions[pclass]
    let cbits = self.class_subclasses[pclass]
    let csub = (1 << cbits) - 1
    let mut cval = 0
    if cbits > 0 {
      let masterbook = self.class_masterbooks[pclass]
      match codebooks[masterbook].decode_scalar(br) {
        Ok(v) => cval = v
        Err(e) => return Err(e)
      }
    }
    for _ in 0..<cdim {
      let book = self.subclass_books[pclass][cval & csub]
      cval = cval >> cbits
      if book >= 0 {
        match codebooks[book].decode_scalar(br) {
          Ok(v) => final_y.push(v)
          Err(e) => return Err(e)
        }
      } else {
        final_y.push(0)
      }
    }
  }

  // 用邻居插值校正各关键点
  for j in 2..<self.x_list.length() {
    let low = self.neighbors[j][0]
    let high = self.neighbors[j][1]
    let pred = predict_point(
      self.x_list[j],
      self.x_list[low],
      self.x_list[high],
      final_y[low],
      final_y[high],
    )
    let val = final_y[j]
    let highroom = range - pred
    let lowroom = pred
    let room = if highroom < lowroom { highroom * 2 } else { lowroom * 2 }
    if val != 0 {
      if val >= room {
        if highroom > lowroom {
          final_y[j] = val - lowroom + pred
        } else {
          final_y[j] = pred - val + highroom - 1
        }
      } else if (val & 1) != 0 {
        final_y[j] = pred - ((val + 1) >> 1)
      } else {
        final_y[j] = pred + (val >> 1)
      }
    } else {
      final_y[j] = pred
    }
  }

  Ok(final_y)
}

/// dB 值到线性幅度的转换表（Vorbis 规范规定，256 项）。
let inverse_db_table : Array[Float] = [
  1.0649863e-07, 1.1341951e-07, 1.2079015e-07, 1.2863978e-07, 1.3699951e-07, 1.4590251e-07,
  1.5538408e-07, 1.6548181e-07, 1.7623575e-07, 1.8768855e-07, 1.9988561e-07, 2.1287530e-07,
  2.2670913e-07, 2.4144197e-07, 2.5713223e-07, 2.7384213e-07, 2.9163793e-07, 3.1059021e-07,
  3.3077411e-07, 3.5226968e-07, 3.7516214e-07, 3.9954229e-07, 4.2550680e-07, 4.5315863e-07,
  4.8260743e-07, 5.1396998e-07, 5.4737065e-07, 5.8294187e-07, 6.2082472e-07, 6.6116941e-07,
  7.0413592e-07, 7.4989464e-07, 7.9862701e-07, 8.5052630e-07, 9.0579828e-07, 9.6466216e-07,
  1.0273513e-06, 1.0941144e-06, 1.1652161e-06, 1.2409384e-06, 1.3215816e-06, 1.4074654e-06,
  1.4989305e-06, 1.5963394e-06, 1.7000785e-06, 1.8105592e-06, 1.9282195e-06, 2.0535261e-06,
  2.1869758e-06, 2.3290978e-06, 2.4804557e-06, 2.6416497e-06, 2.8133190e-06, 2.9961443e-06,
  3.1908506e-06, 3.3982101e-06, 3.6190449e-06, 3.8542308e-06, 4.1047004e-06, 4.3714470e-06,
  4.6555282e-06, 4.9580707e-06, 5.2802740e-06, 5.6234160e-06, 5.9888572e-06, 6.3780469e-06,
  6.7925283e-06, 7.2339451e-06, 7.7040476e-06, 8.2047000e-06, 8.7378876e-06, 9.3057248e-06,
  9.9104632e-06, 1.0554501e-05, 1.1240392e-05, 1.1970856e-05, 1.2748789e-05, 1.3577278e-05,
  1.4459606e-05, 1.5399272e-05, 1.6400004e-05, 1.7465768e-05, 1.8600792e-05, 1.9809576e-05,
  2.1096914e-05, 2.2467911e-05, 2.3928002e-05, 2.5482978e-05, 2.7139006e-05, 2.8902651e-05,
  3.0780908e-05, 3.2781225e-05, 3.4911534e-05, 3.7180282e-05, 3.9596466e-05, 4.2169667e-05,
  4.4910090e-05, 4.7828601e-05, 5.0936773e-05, 5.4246931e-05, 5.7772202e-05, 6.1526565e-05,
  6.5524908e-05, 6.9783085e-05, 7.4317983e-05, 7.9147585e-05, 8.4291040e-05, 8.9768747e-05,
  9.5602426e-05, 0.00010181521, 0.00010843174, 0.00011547824, 0.00012298267, 0.00013097477,
  0.00013948625, 0.00014855085, 0.00015820453, 0.00016848555, 0.00017943469, 0.00019109536,
  0.00020351382, 0.00021673929, 0.00023082423, 0.00024582449, 0.00026179955, 0.00027881276,
  0.00029693158, 0.00031622787, 0.00033677814, 0.00035866388, 0.00038197188, 0.00040679456,
  0.00043323036, 0.00046138411, 0.00049136745, 0.00052329927, 0.00055730621, 0.00059352311,
  0.00063209358, 0.00067317058, 0.00071691700, 0.00076350630, 0.00081312324, 0.00086596457,
  0.00092223983, 0.00098217216, 0.0010459992, 0.0011139742, 0.0011863665, 0.0012634633,
  0.0013455702, 0.0014330129, 0.0015261382, 0.0016253153, 0.0017309374, 0.0018434235,
  0.0019632195, 0.0020908006, 0.0022266726, 0.0023713743, 0.0025254795, 0.0026895994,
  0.0028643847, 0.0030505286, 0.0032487691, 0.0034598925, 0.0036847358, 0.0039241906,
  0.0041792066, 0.0044507950, 0.0047400328, 0.0050480668, 0.0053761186, 0.0057254891,
  0.0060975636, 0.0064938176, 0.0069158225, 0.0073652516, 0.0078438871, 0.0083536271,
  0.0088964928, 0.009474637, 0.010090352, 0.010746080, 0.011444421, 0.012188144,
  0.012980198, 0.013823725, 0.014722068, 0.015678791, 0.016697687, 0.017782797,
  0.018938423, 0.020169149, 0.021479854, 0.022875735, 0.024362330, 0.025945531,
  0.027631618, 0.029427276, 0.031339626, 0.033376252, 0.035545228, 0.037855157,
  0.040315199, 0.042935108, 0.045725273, 0.048696758, 0.051861348, 0.055231591,
  0.058820850, 0.062643361, 0.066714279, 0.071049749, 0.075666962, 0.080584227,
  0.085821044, 0.091398179, 0.097337747, 0.10366330, 0.11039993, 0.11757434,
  0.12521498, 0.13335215, 0.14201813, 0.15124727, 0.16107617, 0.17154380,
  0.18269168, 0.19456402, 0.20720788, 0.22067342, 0.23501402, 0.25028656,
  0.26655159, 0.28387361, 0.30232132, 0.32196786, 0.34289114, 0.36517414,
  0.38890521, 0.41417847, 0.44109412, 0.46975890, 0.50028648, 0.53279791,
  0.56742212, 0.60429640, 0.64356699, 0.68538959, 0.72993007, 0.77736504,
  0.82788260, 0.88168307, 0.9389798, 1.0,
]

/// Bresenham 线性插值，把 [x0,y0] 到 [x1,y1] 的线段累乘到 output 上（Y 经 inverse_db_table 转换）。
fn draw_line(output : Array[Float], x0 : Int, y0 : Int, x1 : Int, y1 : Int, n : Int) -> Unit {
  let dy = y1 - y0
  let adx = x1 - x0
  let ady = iabs(dy)
  let base = dy / adx
  let sy = if dy < 0 { base - 1 } else { base + 1 }
  let ady2 = ady - iabs(base) * adx
  let x1c = if x1 > n { n } else { x1 }
  let mut x = x0
  let mut y = y0
  let mut err = 0
  if x < x1c {
    output[x] = output[x] * inverse_db_table[y & 255]
    x += 1
    while x < x1c {
      err += ady2
      if err >= adx {
        err -= adx
        y += sy
      } else {
        y += base
      }
      output[x] = output[x] * inverse_db_table[y & 255]
      x += 1
    }
  }
}

/// floor1 第二阶段：把 finalY 关键点插值成完整 floor 曲线（长度 n2）。
pub fn Floor1::synthesize(self : Floor1, final_y : Array[Int], n2 : Int) -> Array[Float] {
  let output : Array[Float] = []
  for _ in 0..<n2 {
    output.push(1)
  }
  let mut lx = 0
  let mut ly = final_y[0] * self.multiplier
  for q in 1..<self.x_list.length() {
    let j = self.sorted_order[q]
    if final_y[j] >= 0 {
      let hy = final_y[j] * self.multiplier
      let hx = self.x_list[j]
      if lx != hx {
        draw_line(output, lx, ly, hx, hy, n2)
      }
      lx = hx
      ly = hy
    }
  }
  if lx < n2 {
    let mut j = lx
    while j < n2 {
      output[j] = output[j] * inverse_db_table[ly & 255]
      j += 1
    }
  }
  output
}
