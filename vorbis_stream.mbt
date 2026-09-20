// vorbis_stream.mbt
//
// 高层解码编排：把 OGG 页流解析成 Vorbis 头并解码音频，产出 PCM。
// 对上层（CLI / WASM demo）暴露一个与 bit/floor/residue 无关的简洁接口。

///|
/// 从 OGG 页流解码 Vorbis 音频的状态机。
/// 依次消费 identification / comment / setup 三个 header packet，之后的 packet 视为音频帧。
pub struct VorbisStream {
  assembler : PacketAssembler
  mut header_state : Int
  mut info : VorbisInfo?
  mut comment : VorbisComment?
  mut setup : VorbisSetup?
  mut decoder : Decoder?
  pcm : Array[Array[Float]]
  // 已见到的最大 granule position，即流中合法的 PCM 帧总数。-1 表示未见到。
  mut last_granule : Int64
}

///|
/// 新建空流，初始等待 identification header。
pub fn VorbisStream::new() -> VorbisStream {
  {
    assembler: PacketAssembler::new(),
    header_state: 0,
    info: None,
    comment: None,
    setup: None,
    decoder: None,
    pcm: [],
    last_granule: -1L,
  }
}

///|
/// 喂入一个 OGG 页，按当前状态解析 header 或解码音频 packet。
pub fn VorbisStream::push_page(
  self : VorbisStream,
  page : OggPage,
) -> Result[Unit, String] {
  // granule position 记录该页结束时流中的合法 PCM 帧总数；-1 表示该页没有
  // 结束任何 packet。取最大值而非「最后见到的一个」，避免非单调的异常流把
  // 已经解出的样本裁掉。
  if page.granule_position >= 0L && page.granule_position > self.last_granule {
    self.last_granule = page.granule_position
  }
  let packets = self.assembler.push_page(page)
  for packet in packets {
    match self.header_state {
      0 =>
        match VorbisInfo::parse(packet) {
          Ok(i) => {
            self.info = Some(i)
            self.header_state = 1
          }
          Err(e) => return Err(e)
        }
      1 =>
        match VorbisComment::parse(packet) {
          Ok(c) => {
            self.comment = Some(c)
            self.header_state = 2
          }
          Err(e) => return Err(e)
        }
      2 =>
        match self.info {
          Some(i) =>
            match VorbisSetup::parse(packet, i.channels) {
              Ok(s) => {
                self.setup = Some(s)
                self.decoder = Some(Decoder::new(i, s))
                self.header_state = 3
              }
              Err(e) => return Err(e)
            }
          None => return Err("setup header before identification")
        }
      _ =>
        match self.decoder {
          Some(d) =>
            match d.decode_packet(BitReader::new(packet)) {
              Ok(out) =>
                for ch in 0..<out.length() {
                  if self.pcm.length() <= ch {
                    self.pcm.push([])
                  }
                  for s in out[ch] {
                    self.pcm[ch].push(s)
                  }
                }
              Err(e) => return Err(e)
            }
          None => return Err("audio packet before setup")
        }
    }
  }
  Ok(())
}

///|
/// 三个 header 是否已全部解析完成。
pub fn VorbisStream::is_ready(self : VorbisStream) -> Bool {
  self.header_state >= 3
}

///|
/// 采样率（header 解析完成后可用，否则返回 0）。
pub fn VorbisStream::sample_rate(self : VorbisStream) -> Int {
  match self.info {
    Some(i) => i.sample_rate
    None => 0
  }
}

///|
/// 声道数。
pub fn VorbisStream::channels(self : VorbisStream) -> Int {
  match self.info {
    Some(i) => i.channels
    None => 0
  }
}

///|
/// 累计解码出的 PCM 样本（每声道一个 Float 数组，约 [-1,1]）。
pub fn VorbisStream::pcm(self : VorbisStream) -> Array[Array[Float]] {
  self.pcm
}

///|
/// 已见到的最大 granule position，即合法的 PCM 帧总数；尚未见到时返回 -1。
pub fn VorbisStream::granule_position(self : VorbisStream) -> Int64 {
  self.last_granule
}

///|
/// 把 PCM 裁剪到 granule position 指定的长度。
///
/// Vorbis 按块编码，最后一个 packet 往往解出超过原始长度的样本（编码器补的
/// 尾巴）。granule position 才是权威的帧数，多出来的部分必须丢掉。
/// 增量喂页的调用方应在流结束后自行调用一次；`decode_ogg` 已经代为调用。
pub fn VorbisStream::trim_to_granule(self : VorbisStream) -> Unit {
  if self.last_granule < 0L {
    return
  }
  for ch in 0..<self.pcm.length() {
    let cur = self.pcm[ch].length()
    // 先和当前长度比较再转换，避免 granule 超出 Int 范围时转换溢出
    let limit = if self.last_granule > Int64::from_int(cur) {
      cur
    } else {
      self.last_granule.to_int()
    }
    if limit < cur {
      let trimmed : Array[Float] = []
      for i in 0..<limit {
        trimmed.push(self.pcm[ch][i])
      }
      self.pcm[ch] = trimmed
    }
  }
}

///|
/// 一次性解码整个 OGG 文件字节，返回流（含 PCM 与头信息）。便捷封装。
pub fn decode_ogg(data : Bytes) -> Result[VorbisStream, String] {
  let stream = VorbisStream::new()
  let mut offset = 0
  while offset < data.length() {
    match OggPage::parse(data, offset) {
      Ok(page) => {
        match stream.push_page(page) {
          Ok(_) => ()
          Err(e) => return Err(e)
        }
        offset += page.total_size()
      }
      Err(e) => return Err(e)
    }
  }
  stream.trim_to_granule()
  Ok(stream)
}
