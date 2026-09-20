// wav.mbt
//
// 16-bit PCM WAV 序列化：把解码出的 Float PCM（约 [-1,1]）写成标准 WAV 文件字节。
// 纯函数，不涉及文件 I/O，CLI 与 WASM demo 共用。

///|
/// 把多声道 Float PCM 序列化为 16-bit PCM WAV 字节（样本按声道交错）。
/// 样本超出 [-1,1] 时截断，再四舍五入到 16 位有符号整数。
pub fn wav_encode_pcm16(pcm : Array[Array[Float]], sample_rate : Int) -> Bytes {
  let channels = pcm.length()
  let frames = if channels == 0 { 0 } else { pcm[0].length() }
  let data_size = frames * channels * 2
  let buf = @buffer.Buffer()
  // RIFF 头
  buf.write_bytes(b"RIFF")
  buf.write_uint_le((36 + data_size).reinterpret_as_uint())
  buf.write_bytes(b"WAVE")
  // fmt chunk
  buf.write_bytes(b"fmt ")
  buf.write_uint_le(16U)
  buf.write_uint16_le((1).to_uint16()) // PCM
  buf.write_uint16_le(channels.to_uint16())
  buf.write_uint_le(sample_rate.reinterpret_as_uint())
  buf.write_uint_le((sample_rate * channels * 2).reinterpret_as_uint()) // 字节率
  buf.write_uint16_le((channels * 2).to_uint16()) // block align
  buf.write_uint16_le((16).to_uint16()) // 位深
  // data chunk
  buf.write_bytes(b"data")
  buf.write_uint_le(data_size.reinterpret_as_uint())
  for f in 0..<frames {
    for ch in 0..<channels {
      let s = pcm[ch][f]
      let c = s.clamp(min=-1.0, max=1.0)
      let v = (c * 32767.0).round().to_int()
      buf.write_int16_le(Int16::from_int(v))
    }
  }
  buf.to_bytes()
}
