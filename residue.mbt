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

  Ok({
    residue_type,
    begin,
    end,
    partition_size,
    classifications,
    classbook,
    cascade,
    residue_books,
  })
}

///|
/// 解码 residue（单声道，type 1/2），把残差累加到 target。
/// `n` 是半块大小；type 2 的 actual_size 为 n*2，其余为 n。
pub fn Residue::decode(
  self : Residue,
  br : BitReader,
  codebooks : Array[Codebook],
  target : Array[Float],
  n : Int,
) -> Result[Unit, String] {
  let rtype = self.residue_type
  let classbook = codebooks[self.classbook]
  let classwords = classbook.dimensions
  let actual_size = if rtype == 2 { n * 2 } else { n }
  let limit_begin = if self.begin < actual_size {
    self.begin
  } else {
    actual_size
  }
  let limit_end = if self.end < actual_size { self.end } else { actual_size }
  let n_read = limit_end - limit_begin
  let part_read = n_read / self.partition_size

  for i in 0..<actual_size {
    target[i] = 0
  }

  // 每个 partition 的 classification；多留 classwords 个位置避免填充越界
  let classifications : Array[Int] = []
  for _ in 0..<(part_read + classwords) {
    classifications.push(0)
  }

  for pass in 0..<8 {
    let mut pcount = 0
    while pcount < part_read {
      if pass == 0 {
        let temp = match classbook.decode_scalar(br) {
          Ok(t) => t
          Err(e) => return Err(e)
        }
        let mut q = temp
        let mut k = 0
        while k < classwords {
          classifications[pcount + classwords - 1 - k] = q %
            self.classifications
          q = q / self.classifications
          k += 1
        }
      }
      let mut i = 0
      while i < classwords && pcount < part_read {
        let c = classifications[pcount]
        let b = self.residue_books[c][pass]
        if b >= 0 {
          let offset = limit_begin + pcount * self.partition_size
          let book = codebooks[b]
          if rtype == 0 {
            return Err("residue type 0 not yet supported")
          }
          let mut k = 0
          while k < self.partition_size {
            match
              book.decode_vq(br, target, offset + k, self.partition_size - k) {
              Ok(_) => ()
              Err(e) => return Err(e)
            }
            k += book.dimensions
          }
        }
        pcount += 1
        i += 1
      }
    }
  }
  Ok(())
}
