// Whitebox tests for decoder.mbt.
// 端到端参考由 Python 完整实现同一逻辑生成（单声道，block=64，n2=32）。

///|
/// 两个音频 packet：首帧无输出，第二帧输出 32 个 PCM 样本。
test "decoder 端到端" {
  let ident = b"\x01\x76\x6f\x72\x62\x69\x73\x00\x00\x00\x00\x01" +
    b"\x40\x1f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x66\x01"
  let info = match VorbisInfo::parse(ident) {
    Ok(i) => i
    Err(e) => @test.fail(e)
  }
  let setup_bytes = b"\x05\x76\x6f\x72\x62\x69\x73\x01\x42\x43\x56\x01" +
    b"\x00\x01\x00\x00\x00\x10\x1a\xb2\x12\x00\x08\x00" +
    b"\x00\x00\x08\x00\x00\x00\x00\x00\x00\xe0\xcf\x50" +
    b"\x06\x00\x00\x80\x00\x00\x80\x01\x01\x00\x00\x00" +
    b"\x00\x20\x00\x00\x01\x00\x00\x00\x40\x04\x00\x00" +
    b"\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x20"
  let setup = match VorbisSetup::parse(setup_bytes, 1) {
    Ok(s) => s
    Err(e) => @test.fail(e)
  }
  let decoder = Decoder::new(info, setup)
  let out1 = match decoder.decode_packet(BitReader::new(b"\x01\x00\x00\x00\x00")) {
    Ok(o) => o
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(out1.length(), 0)
  let out2 = match decoder.decode_packet(BitReader::new(b"\x01\x00\x00\x00\x00")) {
    Ok(o) => o
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(out2.length(), 32)
  // MoonBit 自研 cosf/sinf 与 numpy 参考有少量 ULP 差异，IMDCT 累加后放大，用容差 16 比较
  let exp = [0x3577F381U, 0xB55FCA0CU, 0x358AE271U, 0xB584A442U, 0xB76D7E76U, 0xB5442132U]
  let idx = [0, 1, 2, 3, 16, 31]
  for k in 0..<6 {
    let actual = out2[idx[k]].reinterpret_as_uint()
    let expected = exp[k]
    let diff = if actual > expected { actual - expected } else { expected - actual }
    @test.assert_eq(diff <= 16, true)
  }
}
