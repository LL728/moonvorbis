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
  pcm : Array[Float]
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
  }
}

///|
/// 喂入一个 OGG 页，按当前状态解析 header 或解码音频 packet。
pub fn VorbisStream::push_page(
  self : VorbisStream,
  page : OggPage,
) -> Result[Unit, String] {
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
                for s in out {
                  self.pcm.push(s)
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
/// 累计解码出的 PCM 样本（单声道 Float，约 [-1,1]）。
pub fn VorbisStream::pcm(self : VorbisStream) -> Array[Float] {
  self.pcm
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
  Ok(stream)
}
