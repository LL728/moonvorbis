// floor1.mbt
//
// Vorbis floor1 setup 解析（第一阶段）。
//
// floor 表示每个声道频域系数的"包络"曲线。floor1 是两种 floor 类型之一，
// 通过 codebook 解码出曲线上的关键点，再由 X 坐标列表插值得到完整包络。
// 本阶段解析 setup header 中的 floor1 配置；实际曲线解码在音频 packet 阶段。

///|
/// floor1 的配置。
///
/// * `partition_class_list` : 每个 partition 所属的 class；
/// * `class_dimensions` / `class_subclasses` : 每个 class 的结构；
/// * `class_masterbooks` / `subclass_books` : 解码用的 codebook 索引，`-1` 表示无；
/// * `x_list` : floor 曲线的 X 坐标（前两项固定为 0 和 `2^rangebits`）。
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
}

///|
/// 从 `br` 的当前位置解析一个 floor1 配置。
pub fn Floor1::parse(br : BitReader) -> Result[Floor1, String] {
  let partitions = br.read_bits(5)

  // partition → class 映射，同时求最大 class 号
  let partition_class_list : Array[Int] = []
  let mut max_class = -1
  for _ in 0..<partitions {
    let c = br.read_bits(4)
    partition_class_list.push(c)
    if c > max_class {
      max_class = c
    }
  }

  // 每个 class 的配置
  let class_dimensions : Array[Int] = []
  let class_subclasses : Array[Int] = []
  let class_masterbooks : Array[Int] = []
  let subclass_books : Array[Array[Int]] = []
  for _ in 0..<(max_class + 1) {
    let dim = br.read_bits(3) + 1
    class_dimensions.push(dim)
    let subclasses = br.read_bits(2)
    class_subclasses.push(subclasses)
    // 仅当 subclasses > 0 时才有 masterbook
    let masterbook = if subclasses != 0 { br.read_bits(8) } else { -1 }
    class_masterbooks.push(masterbook)
    let books : Array[Int] = []
    for _ in 0..<(1 << subclasses) {
      // read 8 bits - 1，0 减 1 得 -1 表示"无 codebook"
      books.push(br.read_bits(8) - 1)
    }
    subclass_books.push(books)
  }

  let multiplier = br.read_bits(2) + 1
  let rangebits = br.read_bits(4)

  // X 坐标列表：前两项固定，其余由各 partition 的 class 维度决定
  let x_list : Array[Int] = [0, 1 << rangebits]
  for i in 0..<partitions {
    let c = partition_class_list[i]
    for _ in 0..<class_dimensions[c] {
      x_list.push(br.read_bits(rangebits))
    }
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
    },
  )
}
