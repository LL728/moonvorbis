// residue.mbt
//
// Vorbis residue setup 解析。
//
// residue 是 floor 与最终频域系数之间的残差，用 codebook 对系数分区编码。
// 三种类型：type 0（interleaved，≤8 通道）、type 1（interleaved，≤256 通道）、
// type 2（non-interleaved）。本阶段解析 setup 配置，实际解码在音频 packet 阶段。

///|
/// residue 的配置。
///
/// * `begin` / `end` : 作用的系数范围（end 是开区间上限）；
/// * `partition_size` : 每个 partition 的系数数量；
/// * `classifications` / `classbook` : 分区分类与对应 codebook；
/// * `cascade` : 每个 classification 的残差级联编码描述。
pub struct Residue {
  residue_type : Int
  begin : Int
  end : Int
  partition_size : Int
  classifications : Int
  classbook : Int
  cascade : Array[Int]
  residue_books : Array[Array[Int]]
}

///|
/// 从 `br` 的当前位置解析一个 residue 配置。
pub fn Residue::parse(br : BitReader) -> Result[Residue, String] {
  let residue_type = br.read_bits(16)
  if residue_type > 2 {
    return Err("invalid residue type")
  }
  let begin = br.read_bits(24)
  let end = br.read_bits(24)
  let partition_size = br.read_bits(24) + 1
  let classifications = br.read_bits(6) + 1
  let classbook = br.read_bits(8)

  // 每个 classification 的级联编码
  let cascade : Array[Int] = []
  for _ in 0..<classifications {
    let low_bits = br.read_bits(3)
    let bitflag = br.read_bits(1)
    let high_bits = if bitflag == 1 { br.read_bits(5) } else { 0 }
    cascade.push(high_bits * 8 + low_bits)
  }

  // 每个 classification 每个 pass 的 codebook 索引（cascade bit 为 1 时读 8 位，否则 -1）
  let residue_books : Array[Array[Int]] = []
  for j in 0..<classifications {
    let books : Array[Int] = []
    for k in 0..<8 {
      if (cascade[j] & (1 << k)) != 0 {
        books.push(br.read_bits(8))
      } else {
        books.push(-1)
      }
    }
    residue_books.push(books)
  }

  Ok(
    {
      residue_type,
      begin,
      end,
      partition_size,
      classifications,
      classbook,
      cascade,
      residue_books,
    },
  )
}
