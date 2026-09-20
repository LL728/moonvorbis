// mapping.mbt
//
// Vorbis mapping setup 解析。
//
// mapping 描述声道如何映射到 floor/residue 子流，以及立体声耦合（coupling）
// 的配置。解析依赖 audio_channels（来自 identification header）。

///|
/// mapping 的配置。
///
/// * `submaps` : floor/residue 子流数量；
/// * `magnitude` / `angle` : 耦合声道对（立体声时，主声道与差声道）；
/// * `mux` : 每个声道使用哪个 submap；
/// * `time_config` / `floor` / `residue` : 每个 submap 的配置索引。
pub struct Mapping {
  submaps : Int
  coupling_steps : Int
  magnitude : Array[Int]
  angle : Array[Int]
  mux : Array[Int]
  time_config : Array[Int]
  floor : Array[Int]
  residue : Array[Int]
}

///|
/// 从 `br` 的当前位置解析一个 mapping 配置。
///
/// `channels` 是流的声道数（来自 identification header）。
pub fn Mapping::parse(
  br : BitReader,
  channels : Int,
) -> Result[Mapping, String] {
  // submaps：先读 1 位 flag，置位才读 4 位 + 1，否则默认 1
  let submaps = if br.read_bits(1) == 1 { br.read_bits(4) + 1 } else { 1 }

  // coupling：先读 1 位 flag，置位才读 8 位 + 1 与各声道对
  let mut coupling_steps = 0
  let magnitude : Array[Int] = []
  let angle : Array[Int] = []
  if br.read_bits(1) == 1 {
    coupling_steps = br.read_bits(8) + 1
    for _ in 0..<coupling_steps {
      let mag = br.read_bits(ilog(channels - 1))
      let ang = br.read_bits(ilog(channels - 1))
      if mag == ang {
        return Err("coupling magnitude equals angle")
      }
      magnitude.push(mag)
      angle.push(ang)
    }
  }

  // reserved 2 位必须为 0
  let reserved = br.read_bits(2)
  if reserved != 0 {
    return Err("mapping reserved field nonzero")
  }

  let mux : Array[Int] = []
  if submaps > 1 {
    for _ in 0..<channels {
      let m = br.read_bits(4)
      if m >= submaps {
        return Err("mux exceeds submaps")
      }
      mux.push(m)
    }
  }

  // 每个 submap 的 floor/residue/time 配置索引
  let time_config : Array[Int] = []
  let floor : Array[Int] = []
  let residue : Array[Int] = []
  for _ in 0..<submaps {
    time_config.push(br.read_bits(8))
    floor.push(br.read_bits(8))
    residue.push(br.read_bits(8))
  }

  Ok({
    submaps,
    coupling_steps,
    magnitude,
    angle,
    mux,
    time_config,
    floor,
    residue,
  })
}
