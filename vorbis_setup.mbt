// vorbis_setup.mbt
//
// Vorbis setup header（第三个、也是最后一个 header）的整体解析。
//
// 把此前实现的所有配置解析器串起来：codebook、time transform、floor、
// residue、mapping、mode，并以 framing bit 收尾。

///|
/// 完整的 setup 配置。
pub struct VorbisSetup {
  codebooks : Array[Codebook]
  floors : Array[Floor1]
  residues : Array[Residue]
  mappings : Array[Mapping]
  modes : Array[Mode]
}

///|
/// 解析 setup header packet，返回完整配置。
///
/// `channels` 是流的声道数（来自 identification header），供 mapping 解析使用。
/// 目前仅支持 floor1（floor0 返回错误）。
pub fn VorbisSetup::parse(packet : Bytes, channels : Int) -> Result[VorbisSetup, String] {
  if packet.length() < 7 {
    return Err("truncated setup header")
  }
  // magic: \x05 "vorbis"
  if packet.unsafe_get(0) != b'\x05' ||
    packet.unsafe_get(1) != b'v' ||
    packet.unsafe_get(2) != b'o' ||
    packet.unsafe_get(3) != b'r' ||
    packet.unsafe_get(4) != b'b' ||
    packet.unsafe_get(5) != b'i' ||
    packet.unsafe_get(6) != b's' {
    return Err("not a Vorbis setup header")
  }

  let br = BitReader::new(packet)
  br.skip(7 * 8)

  // codebooks
  let codebook_count = br.read_bits(8) + 1
  let codebooks : Array[Codebook] = []
  for _ in 0..<codebook_count {
    match Codebook::parse(br) {
      Ok(cb) => codebooks.push(cb)
      Err(e) => return Err(e)
    }
  }

  // time domain transforms（仅支持全 0 类型）
  let time_count = br.read_bits(6) + 1
  for _ in 0..<time_count {
    if br.read_bits(16) != 0 {
      return Err("nonzero time domain transform")
    }
  }

  // floors（仅支持 floor1）
  let floor_count = br.read_bits(6) + 1
  let floors : Array[Floor1] = []
  for _ in 0..<floor_count {
    let floor_type = br.read_bits(16)
    if floor_type == 0 {
      return Err("floor0 not yet supported")
    }
    if floor_type != 1 {
      return Err("invalid floor type")
    }
    match Floor1::parse(br) {
      Ok(f) => floors.push(f)
      Err(e) => return Err(e)
    }
  }

  // residues
  let residue_count = br.read_bits(6) + 1
  let residues : Array[Residue] = []
  for _ in 0..<residue_count {
    match Residue::parse(br) {
      Ok(r) => residues.push(r)
      Err(e) => return Err(e)
    }
  }

  // mappings
  let mapping_count = br.read_bits(6) + 1
  let mappings : Array[Mapping] = []
  for _ in 0..<mapping_count {
    if br.read_bits(16) != 0 {
      return Err("invalid mapping type")
    }
    match Mapping::parse(br, channels) {
      Ok(m) => mappings.push(m)
      Err(e) => return Err(e)
    }
  }

  // modes
  let modes = match parse_modes(br) {
    Ok(m) => m
    Err(e) => return Err(e)
  }

  // framing bit
  if br.read_bit() != 1 {
    return Err("missing setup framing flag")
  }

  Ok({ codebooks, floors, residues, mappings, modes })
}
