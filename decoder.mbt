// decoder.mbt
//
// Vorbis 解码主循环：读 mode、解 floor/residue、IMDCT、加窗重叠，输出 PCM。

/// 有状态的解码器。
pub struct Decoder {
  info : VorbisInfo
  setup : VorbisSetup
  window0 : Array[Float]
  window1 : Array[Float]
  previous_window : Array[Float]
  mut previous_length : Int
}

/// 构造解码器，预计算两个 block size 的 window。
pub fn Decoder::new(info : VorbisInfo, setup : VorbisSetup) -> Decoder {
  let window0 = compute_window(info.blocksize0 >> 1)
  let window1 = compute_window(info.blocksize1 >> 1)
  let previous_window : Array[Float] = []
  for _ in 0..<(info.blocksize1 >> 1) {
    previous_window.push(0)
  }
  { info, setup, window0, window1, previous_window, previous_length: 0 }
}

/// 解码一个音频 packet，返回 PCM 样本（可能为空，如首帧）。
/// 目前仅支持单声道、无耦合、无长短块切换。
pub fn Decoder::decode_packet(self : Decoder, br : BitReader) -> Result[Array[Float], String] {
  let mode_number = br.read_bits(ilog(self.setup.modes.length() - 1))
  let mode = self.setup.modes[mode_number]
  let blockflag = mode.blockflag
  let n = if blockflag == 1 { self.info.blocksize1 } else { self.info.blocksize0 }
  let n2 = n >> 1
  let _prev = if blockflag == 1 { br.read_bits(1) } else { 0 }
  let _next = if blockflag == 1 { br.read_bits(1) } else { 0 }

  let mapping = self.setup.mappings[mode.mapping]
  let floor_idx = mapping.floor[0]
  let floor = self.setup.floors[floor_idx]

  // floor：读 1 位标志决定是否解码
  let has_floor = br.read_bits(1)
  let mut floor_curve : Array[Float] = []
  if has_floor == 1 {
    let final_y = match floor.decode(br, self.setup.codebooks) {
      Ok(y) => y
      Err(e) => return Err(e)
    }
    floor_curve = floor.synthesize(final_y, n2)
  }

  // residue
  let residue_idx = mapping.residue[0]
  let residue = self.setup.residues[residue_idx]
  let residue_buf : Array[Float] = []
  for _ in 0..<n2 {
    residue_buf.push(0)
  }
  if has_floor == 1 {
    match residue.decode(br, self.setup.codebooks, residue_buf, n2) {
      Ok(_) => ()
      Err(e) => return Err(e)
    }
    for j in 0..<n2 {
      residue_buf[j] = residue_buf[j] * floor_curve[j]
    }
  }

  // IMDCT：扩展到 n 个时域样本
  let buf = residue_buf
  for _ in 0..<n2 {
    buf.push(0)
  }
  inverse_mdct(buf, n)

  // 加窗 + 重叠相加（简单情况：left=0, right=n2）
  let window = if blockflag == 1 { self.window1 } else { self.window0 }
  if self.previous_length > 0 {
    let pn = self.previous_length
    for j in 0..<pn {
      buf[j] = buf[j] * window[j] + self.previous_window[j] * window[pn - 1 - j]
    }
  }
  // 保存右半部分到 previous_window
  let prev_len = n - n2
  for j in 0..<prev_len {
    self.previous_window[j] = buf[n2 + j]
  }
  let had_previous = self.previous_length > 0
  self.previous_length = prev_len

  if !had_previous {
    return Ok([])
  }
  let out : Array[Float] = []
  for j in 0..<n2 {
    out.push(buf[j])
  }
  Ok(out)
}
