// Whitebox tests for vorbis_setup.mbt.
// 测试向量由 Python 生成：最小但完整的 setup header（各配置 1 个）。

///|
/// 解析完整 setup header：1 codebook、1 floor1、1 residue、1 mapping、1 mode。
test "setup header 整体解析" {
  let packet = b"\x05\x76\x6f\x72\x62\x69\x73\x00\x42\x43\x56\x01" +
    b"\x00\x02\x00\x00\x00\x00\x00\x00\x00\x10\x00\x10" +
    b"\x00\x04\x10\x01\x01\x00\x00\x00\x00\x40\x00\x80" +
    b"\x03\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00" +
    b"\x00\x00\x00\x00\x00\x04"
  match VorbisSetup::parse(packet, 1) {
    Ok(setup) => {
      @test.assert_eq(setup.codebooks.length(), 1)
      @test.assert_eq(setup.floors.length(), 1)
      @test.assert_eq(setup.residues.length(), 1)
      @test.assert_eq(setup.mappings.length(), 1)
      @test.assert_eq(setup.modes.length(), 1)
      // 抽查各组成部分的关键字段
      @test.assert_eq(setup.codebooks[0].entries, 2)
      match setup.floors[0] {
        Floor::Type1(f) => @test.assert_eq(f.partitions, 1)
        Floor::Type0(_) => @test.fail("expected floor1")
      }
      @test.assert_eq(setup.residues[0].residue_type, 2)
      @test.assert_eq(setup.mappings[0].submaps, 1)
      @test.assert_eq(setup.modes[0].mapping, 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// magic 不符时应返回错误。
test "setup header 解析失败：magic 错误" {
  match VorbisSetup::parse(b"\x05xxxxxx\x00", 1) {
    Ok(_) => @test.fail("expected magic error")
    Err(_) => ()
  }
}
