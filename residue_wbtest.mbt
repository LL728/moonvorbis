// Whitebox tests for residue.mbt.
// 测试向量由 Python 按 Vorbis residue setup 位布局生成。

///|
/// type 2、begin=0、end=128、partition_size=8、2 个 classification、classbook=3、
/// cascade=[2, 41]（第二个含 high_bits=5）。
test "residue 解析" {
  let data = b"\x02\x00\x00\x00\x00\x80\x00\x00\x07\x00\x00\xc1\x80\x64\x01"
  let br = BitReader::new(data)
  match Residue::parse(br) {
    Ok(r) => {
      @test.assert_eq(r.residue_type, 2)
      @test.assert_eq(r.begin, 0)
      @test.assert_eq(r.end, 128)
      @test.assert_eq(r.partition_size, 8)
      @test.assert_eq(r.classifications, 2)
      @test.assert_eq(r.classbook, 3)
      @test.assert_eq(r.cascade.length(), 2)
      @test.assert_eq(r.cascade[0], 2)
      @test.assert_eq(r.cascade[1], 41)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// residue_type > 2 时应返回错误。
test "residue 解析失败：type 非法" {
  let data = b"\x03\x00\x00\x00\x00\x80\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"
  let br = BitReader::new(data)
  match Residue::parse(br) {
    Ok(_) => @test.fail("expected invalid type error")
    Err(_) => ()
  }
}
