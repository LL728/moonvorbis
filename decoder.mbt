// decoder.mbt
//
// Vorbis 解码主循环：读 mode、解 floor/residue、IMDCT、加窗重叠，输出 PCM。

///|
/// 有状态的解码器。
pub struct Decoder {
  info : VorbisInfo
  setup : VorbisSetup
  window0 : Array[Float]
  window1 : Array[Float]
  previous_window : Array[Float]
  mut previous_length : Int
}

///|
/// 构造解码器，预计算两个 block size 的 window。
pub fn Decoder::new(info : VorbisInfo, setup : VorbisSetup) -> Decoder {
  let window0 = compute_window(info.blocksize0 >> 1)
  let window1 = compute_window(info.blocksize1 >> 1)
  let previous_window : Array[Float] = []
  for _ in 0..<(info.blocksize1 >> 1) {
    previous_window.push(0)
  }
  { info, setup, window0, window1, previous_window, previous_length: 0, }
}

///|
/// 解码一个音频 packet，返回 PCM 样本（可能为空，如首帧）。
/// 目前仅支持单声道、无耦合、无长短块切换。
pub fn Decoder::decode_packet(
  self : Decoder,
  br : BitReader,
) -> Result[Array[Float], String] {
  // 音频 packet 的第一个 bit 是 packet type（0 = audio，1 = header）
  if br.read_bits(1) != 0 {
    return Err("not an audio packet")
  }
  let mode_number = br.read_bits(ilog(self.setup.modes.length() - 1))
  let mode = self.setup.modes[mode_number]
  let blockflag = mode.blockflag
  let n = if blockflag == 1 {
    self.info.blocksize1
  } else {
    self.info.blocksize0
  }
  let n2 = n >> 1
  let prev = if blockflag == 1 { br.read_bits(1) } else { 0 }
  let next = if blockflag == 1 { br.read_bits(1) } else { 0 }

  // window 边界：长短块切换时，sin 窗口区域按小块的尺寸收窄
  let left_start = if blockflag == 1 && prev == 0 {
    (n - self.info.blocksize0) >> 2
  } else {
    0
  }
  let right_start = if blockflag == 1 && next == 0 {
    (3 * n - self.info.blocksize0) >> 2
  } else {
    n2
  }
  let right_end = if blockflag == 1 && next == 0 {
    (3 * n + self.info.blocksize0) >> 2
  } else {
    n
  }

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

  // residue（target 长度取 n，容纳 type 2 的 2*n2 个系数）
  let residue_idx = mapping.residue[0]
  let residue = self.setup.residues[residue_idx]
  let residue_buf : Array[Float] = []
  for _ in 0..<n {
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

  // IMDCT：前 n2 个频域系数原地变换为 n 个时域样本
  inverse_mdct(residue_buf, n)
  let buf = residue_buf

  // 加窗 + 重叠相加：overlap 长度由前一帧决定，window 取对应块尺寸的窗
  let pn = self.previous_length
  if pn > 0 {
    let w = if pn == self.info.blocksize0 >> 1 {
      self.window0
    } else {
      self.window1
    }
    for j in 0..<pn {
      buf[left_start + j] = buf[left_start + j] * w[j] +
        self.previous_window[j] * w[pn - 1 - j]
    }
  }
  // 保存右 overlap 区域到 previous_window
  let prev_len = right_end - right_start
  for j in 0..<prev_len {
    self.previous_window[j] = buf[right_start + j]
  }
  let had_previous = pn > 0
  self.previous_length = prev_len

  if !had_previous {
    return Ok([])
  }
  // 输出 [left_start, right_start) 之间的样本
  let out : Array[Float] = []
  for j in left_start..<right_start {
    out.push(buf[j])
  }
  Ok(out)
}
