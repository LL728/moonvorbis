// Whitebox tests for residue.mbt.
// 测试向量由 Python 按 Vorbis residue setup 位布局生成。

///|
/// type 2、begin=0、end=128、partition_size=8、2 个 classification、classbook=3、
/// cascade=[2,41]、residue_books 含 4 个 codebook 索引。
test "residue 解析" {
  let data = b"\x02\x00\x00\x00\x00\x80\x00\x00\x07\x00\x00\xc1\x80\x64\x29\x30\x38\x40\x00"
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
      // residue_books[0]: cascade=2(bit1) -> pass1=5, 其余 -1
      @test.assert_eq(r.residue_books[0][0], -1)
      @test.assert_eq(r.residue_books[0][1], 5)
      @test.assert_eq(r.residue_books[0][2], -1)
      // residue_books[1]: cascade=41(bit0,3,5) -> pass0=6, pass3=7, pass5=8
      @test.assert_eq(r.residue_books[1][0], 6)
      @test.assert_eq(r.residue_books[1][1], -1)
      @test.assert_eq(r.residue_books[1][3], 7)
      @test.assert_eq(r.residue_books[1][5], 8)
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
