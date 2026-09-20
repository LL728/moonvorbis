// decoder.mbt
//
// Vorbis 解码主循环：读 mode、解 floor/residue、反耦合、IMDCT、加窗重叠，输出 PCM。

///|
/// 有状态的解码器。
pub struct Decoder {
  info : VorbisInfo
  setup : VorbisSetup
  window0 : Array[Float]
  window1 : Array[Float]
  previous_window : Array[Array[Float]]
  previous_length : Array[Int]
}

///|
/// 构造解码器，预计算两个 block size 的 window，并按声道数分配重叠缓冲。
pub fn Decoder::new(info : VorbisInfo, setup : VorbisSetup) -> Decoder {
  let window0 = compute_window(info.blocksize0 >> 1)
  let window1 = compute_window(info.blocksize1 >> 1)
  let previous_window : Array[Array[Float]] = []
  let previous_length : Array[Int] = []
  for _ in 0..<info.channels {
    let w : Array[Float] = []
    for _ in 0..<(info.blocksize1 >> 1) {
      w.push(0)
    }
    previous_window.push(w)
    previous_length.push(0)
  }
  { info, setup, window0, window1, previous_window, previous_length, }
}

///|
/// 解码一个音频 packet，返回每声道的 PCM 样本（首帧为空）。
pub fn Decoder::decode_packet(
  self : Decoder,
  br : BitReader,
) -> Result[Array[Array[Float]], String] {
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
  let channels = self.info.channels

  // floor 解码：每声道读 1 位标志，解码得到 finalY 并合成曲线
  let floor_curves : Array[Array[Float]] = []
  let has_floor : Array[Int] = []
  for ch in 0..<channels {
    let mux = if mapping.submaps > 1 { mapping.mux[ch] } else { 0 }
    let floor = self.setup.floors[mapping.floor[mux]]
    let f = br.read_bits(1)
    has_floor.push(f)
    if f == 1 {
      let final_y = match floor.decode(br, self.setup.codebooks) {
        Ok(y) => y
        Err(e) => return Err(e)
      }
      floor_curves.push(floor.synthesize(final_y, n2))
    } else {
      floor_curves.push([])
    }
  }

  // 每声道系数缓冲（长度 n，容纳 type 2 的 2*n2 个系数）
  let channel_buffers : Array[Array[Float]] = []
  for _ in 0..<channels {
    let buf : Array[Float] = []
    for _ in 0..<n {
      buf.push(0)
    }
    channel_buffers.push(buf)
  }

  // residue 解码：每个 submap 收集其声道，若全为 floor=0 则跳过
  for s in 0..<mapping.submaps {
    let mut any_floor = false
    for ch in 0..<channels {
      let mux = if mapping.submaps > 1 { mapping.mux[ch] } else { 0 }
      if mux == s && has_floor[ch] == 1 {
        any_floor = true
      }
    }
    if any_floor {
      let residue = self.setup.residues[mapping.residue[s]]
      let sub_targets : Array[Array[Float]] = []
      for ch in 0..<channels {
        let mux = if mapping.submaps > 1 { mapping.mux[ch] } else { 0 }
        if mux == s {
          sub_targets.push(channel_buffers[ch])
        }
      }
      match residue.decode(br, self.setup.codebooks, sub_targets, n2) {
        Ok(_) => ()
        Err(e) => return Err(e)
      }
    }
  }

  // 反耦合：从最后一对耦合逆序还原 magnitude/angle 为左右声道
  for i in 0..<mapping.coupling_steps {
    let idx = mapping.coupling_steps - 1 - i
    let m = channel_buffers[mapping.magnitude[idx]]
    let a = channel_buffers[mapping.angle[idx]]
    for j in 0..<n2 {
      let m2 = m[j]
      let a2 = a[j]
      if m2 > 0 {
        if a2 > 0 {
          m[j] = m2
          a[j] = m2 - a2
        } else {
          a[j] = m2
          m[j] = m2 + a2
        }
      } else if a2 > 0 {
        m[j] = m2
        a[j] = m2 + a2
      } else {
        a[j] = m2
        m[j] = m2 - a2
      }
    }
  }

  // floor 曲线应用：residue × floor（floor=0 的声道清零）
  for ch in 0..<channels {
    if has_floor[ch] == 1 {
      for j in 0..<n2 {
        channel_buffers[ch][j] = channel_buffers[ch][j] * floor_curves[ch][j]
      }
    } else {
      for j in 0..<n2 {
        channel_buffers[ch][j] = 0
      }
    }
  }

  // IMDCT：每声道前 n2 个频域系数原地变换为 n 个时域样本
  for ch in 0..<channels {
    inverse_mdct(channel_buffers[ch], n)
  }

  // 加窗 + 重叠相加：每声道独立
  let had_previous = if channels > 0 {
    self.previous_length[0] > 0
  } else {
    false
  }
  let out : Array[Array[Float]] = []
  for ch in 0..<channels {
    let buf = channel_buffers[ch]
    let pn = self.previous_length[ch]
    if pn > 0 {
      let w = if pn == self.info.blocksize0 >> 1 {
        self.window0
      } else {
        self.window1
      }
      for j in 0..<pn {
        buf[left_start + j] = buf[left_start + j] * w[j] +
          self.previous_window[ch][j] * w[pn - 1 - j]
      }
    }
    let prev_len = right_end - right_start
    for j in 0..<prev_len {
      self.previous_window[ch][j] = buf[right_start + j]
    }
    self.previous_length[ch] = prev_len
    if had_previous {
      let ch_out : Array[Float] = []
      for j in left_start..<right_start {
        ch_out.push(buf[j])
      }
      out.push(ch_out)
    }
  }
  if !had_previous {
    Ok([])
  } else {
    Ok(out)
  }
}
