// cmd/main/main.mbt
//
// 命令行入口：读 .ogg 文件 → 解码 → 输出 16-bit PCM WAV。

///|
fn main {
  let args = @env.args()
  if args.length() < 2 {
    println("用法: moon run cmd/main -- <input.ogg> [output.wav]")
    return
  }
  let input = args[1]
  let output = if args.length() >= 3 { args[2] } else { "\{input}.wav" }
  try {
    let data = @fs.read_file_to_bytes(input)
    match @moonvorbis.decode_ogg(data) {
      Ok(stream) => {
        if !stream.is_ready() {
          println("错误: 未找到完整的 Vorbis 头")
          return
        }
        let channels = stream.channels()
        let frames = if channels > 0 { stream.pcm()[0].length() } else { 0 }
        println(
          "采样率: \{stream.sample_rate()} Hz, 声道: \{channels}, 样本: \{frames}",
        )
        let wav = @moonvorbis.wav_encode_pcm16(
          stream.pcm(),
          stream.sample_rate(),
        )
        @fs.write_bytes_to_file(output, wav)
        println("已写入: \{output}")
      }
      Err(e) => println("解码失败: \{e}")
    }
  } catch {
    @fs.IOError::IOError(msg) => println("I/O 错误: \{msg}")
  }
}
