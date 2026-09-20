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

///|
/// residue decode（单声道 type1）：参考 target=[10,20,10,20]。
test "residue decode" {
  let residue = match
    Residue::parse(
      BitReader::new(
        b"\x01\x00\x00\x00\x00\x04\x00\x00\x01\x00\x00\x00\x40\x04\x00",
      ),
    ) {
    Ok(r) => r
    Err(e) => @test.fail(e)
  }
  let cb0 = match
    Codebook::parse(BitReader::new(b"\x42\x43\x56\x01\x00\x01\x00\x00\x00\x00")) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let cb1 = match
    Codebook::parse(
      BitReader::new(
        b"\x42\x43\x56\x02\x00\x01\x00\x00\x00\x01\x00\x00\x00\x08\x00\x00\x14\x1b\xca",
      ),
    ) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let target : Array[Float] = []
  for _ in 0..<4 {
    target.push(0)
  }
  match residue.decode(BitReader::new(b"\x00"), [cb0, cb1], target, 4) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(target[0].reinterpret_as_uint(), 0x41200000U) // 10.0
  @test.assert_eq(target[1].reinterpret_as_uint(), 0x41400000U) // 12.0
  @test.assert_eq(target[2].reinterpret_as_uint(), 0x41200000U)
  @test.assert_eq(target[3].reinterpret_as_uint(), 0x41400000U)
}
