// Whitebox tests for vorbis_info.mbt.
// 测试向量由 Python 按 Vorbis I 规范构造。

///|
/// 立体声 44.1kHz，block size 256 / 2048（指数 8 / 11）。
test "解析 ident：立体声 44.1k" {
  let packet = b"\x01\x76\x6f\x72\x62\x69\x73\x00\x00\x00\x00\x02\x44\xac\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb8\x01"
  match VorbisInfo::parse(packet) {
    Ok(info) => {
      @test.assert_eq(info.channels, 2)
      @test.assert_eq(info.sample_rate, 44100)
      @test.assert_eq(info.blocksize0, 256)
      @test.assert_eq(info.blocksize1, 2048)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// 单声道 8kHz，block size 64 / 256（指数 6 / 8）。
test "解析 ident：单声道 8k" {
  let packet = b"\x01\x76\x6f\x72\x62\x69\x73\x00\x00\x00\x00\x01\x40\x1f\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x86\x01"
  match VorbisInfo::parse(packet) {
    Ok(info) => {
      @test.assert_eq(info.channels, 1)
      @test.assert_eq(info.sample_rate, 8000)
      @test.assert_eq(info.blocksize0, 64)
      @test.assert_eq(info.blocksize1, 256)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// magic 不符时应返回错误。
test "解析 ident 失败：magic 错误" {
  let packet = b"\x01xxxxxx\x00\x00\x00\x00\x02\x44\xac\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\xb8\x01"
  match VorbisInfo::parse(packet) {
    Ok(_) => @test.fail("expected magic error")
    Err(_) => ()
  }
}

///|
/// 数据截断（不足 30 字节）时应返回错误。
test "解析 ident 失败：截断" {
  match VorbisInfo::parse(b"\x01vorbis\x00") {
    Ok(_) => @test.fail("expected truncation error")
    Err(_) => ()
  }
}
