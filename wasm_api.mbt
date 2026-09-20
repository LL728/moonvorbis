// wasm_api.mbt
//
// 供浏览器 WASM demo 调用的导出接口：base64 OGG → base64 WAV。
// 用 base64 字符串跨 JS 边界，避免直接操作线性内存。

///|
/// 解码 base64 编码的 OGG 数据，返回 base64 编码的 16-bit PCM WAV。
/// 解码失败返回空字符串，调用方据此判断是否成功。
pub fn decode_ogg_base64(ogg_b64 : String) -> String {
  try {
    let ogg = @base64.decode(ogg_b64)
    let stream = match decode_ogg(ogg) {
      Ok(s) => s
      Err(_) => return ""
    }
    if !stream.is_ready() {
      return ""
    }
    let wav = wav_encode_pcm16(stream.pcm(), stream.sample_rate())
    @base64.encode(wav)
  } catch {
    _ => ""
  }
}
