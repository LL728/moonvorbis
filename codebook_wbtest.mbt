// Whitebox tests for codebook.mbt.
// 测试向量由 Python 按 Vorbis codebook 位布局（LSB-first）生成。

///|
/// unordered、non-sparse，4 个 entry，码长 [2,3,2,3]。
test "codebook 解析：unordered non-sparse" {
  let data = b"\x42\x43\x56\x02\x00\x04\x00\x00\x04\x11\x04"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 2)
      @test.assert_eq(cb.entries, 4)
      @test.assert_eq(cb.lengths.length(), 4)
      @test.assert_eq(cb.lengths[0], 2)
      @test.assert_eq(cb.lengths[1], 3)
      @test.assert_eq(cb.lengths[2], 2)
      @test.assert_eq(cb.lengths[3], 3)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// unordered、sparse，4 个 entry，其中 2 个 hole（码长 0）。
test "codebook 解析：unordered sparse（含 hole）" {
  let data = b"\x42\x43\x56\x01\x00\x04\x00\x00\x1a\x14"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 1)
      @test.assert_eq(cb.entries, 4)
      @test.assert_eq(cb.lengths.length(), 4)
      @test.assert_eq(cb.lengths[0], 0)
      @test.assert_eq(cb.lengths[1], 2)
      @test.assert_eq(cb.lengths[2], 0)
      @test.assert_eq(cb.lengths[3], 3)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// ordered，6 个 entry，游程 (长度 2 × 3, 长度 4 × 3)，码长 [2,2,2,4,4,4]。
test "codebook 解析：ordered 游程编码" {
  let data = b"\x42\x43\x56\x01\x00\x06\x00\x00\xc3\xc6"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 1)
      @test.assert_eq(cb.entries, 6)
      @test.assert_eq(cb.lengths.length(), 6)
      @test.assert_eq(cb.lengths[0], 2)
      @test.assert_eq(cb.lengths[1], 2)
      @test.assert_eq(cb.lengths[2], 2)
      @test.assert_eq(cb.lengths[3], 4)
      @test.assert_eq(cb.lengths[4], 4)
      @test.assert_eq(cb.lengths[5], 4)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// sync pattern 不符时应返回错误。
test "codebook 解析失败：sync 错误" {
  let data = b"\x00\x00\x00\x02\x00\x04\x00\x00\x00\x00\x00"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(_) => @test.fail("expected sync error")
    Err(_) => ()
  }
}
