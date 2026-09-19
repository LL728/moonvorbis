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
