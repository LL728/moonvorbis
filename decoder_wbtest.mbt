// Whitebox tests for decoder.mbt.
// 端到端场景：单声道 block=64（n2=32），floor flag=0（无 floor/residue），PCM 全零。

///|
/// 两个音频 packet：首帧无输出，第二帧输出 32 个全零 PCM 样本。
test "decoder 端到端" {
  let ident = b"\x01\x76\x6f\x72\x62\x69\x73\x00\x00\x00\x00\x01" +
    b"\x40\x1f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x66\x01"
  let info = match VorbisInfo::parse(ident) {
    Ok(i) => i
    Err(e) => @test.fail(e)
  }
  let setup_bytes = b"\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01" +
    b"\x00\x02\x00\x00\x00\x00\x00\x00\x00\x10\x00\x10" +
    b"\x00\x04\x10\x01\x01\x00\x00\x00\x00\x10\x00\x80" +
    b"\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x00\x04"
  let setup = match VorbisSetup::parse(setup_bytes, 1) {
    Ok(s) => s
    Err(e) => @test.fail(e)
  }
  let decoder = Decoder::new(info, setup)
  // 音频 packet：packet type=0、mode_number=0（0 bit）、floor flag=0
  let out1 = match decoder.decode_packet(BitReader::new(b"\x00")) {
    Ok(o) => o
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(out1.length(), 0)
  let out2 = match decoder.decode_packet(BitReader::new(b"\x00")) {
    Ok(o) => o
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(out2.length(), 32)
  for s in out2 {
    @test.assert_eq(s.reinterpret_as_uint(), 0x00000000U)
  }
}
