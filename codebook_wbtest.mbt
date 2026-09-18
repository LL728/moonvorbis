// Whitebox tests for codebook.mbt.
// 测试向量由 Python 按 Vorbis codebook 位布局（LSB-first）生成。

///|
/// unordered、non-sparse，4 个 entry，码长 [2,3,2,3]，无 lookup table。
test "codebook 解析：unordered non-sparse" {
  let data = b"\x42\x43\x56\x02\x00\x04\x00\x00\x04\x11\x04\x00"
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
      @test.assert_eq(cb.lookup_type, 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// unordered、sparse，4 个 entry，其中 2 个 hole（码长 0），无 lookup table。
test "codebook 解析：unordered sparse（含 hole）" {
  let data = b"\x42\x43\x56\x01\x00\x04\x00\x00\x1a\x14\x00"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 1)
      @test.assert_eq(cb.entries, 4)
      @test.assert_eq(cb.lengths[0], 0)
      @test.assert_eq(cb.lengths[1], 2)
      @test.assert_eq(cb.lengths[2], 0)
      @test.assert_eq(cb.lengths[3], 3)
      @test.assert_eq(cb.lookup_type, 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// ordered，6 个 entry，游程 (长度 2 × 3, 长度 4 × 3)，无 lookup table。
test "codebook 解析：ordered 游程编码" {
  let data = b"\x42\x43\x56\x01\x00\x06\x00\x00\xc3\xc6\x00"
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
      @test.assert_eq(cb.lookup_type, 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// lookup type 1：min=0.0、delta=1.0、value_bits=4、sequence=0、2 个 multiplicands [1,2]。
/// lookup1_values(4, 2) = 2。
test "codebook 解析：lookup table type 1" {
  let data = b"\x42\x43\x56\x02\x00\x04\x00\x00\x84\x10\x42\x00\x00\x00\x00\x00\x00\x00\xfe\x8c\x10"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 2)
      @test.assert_eq(cb.entries, 4)
      @test.assert_eq(cb.lookup_type, 1)
      // 0.0 的 bit 模式是 0x00000000，1.0 是 0x3F800000
      @test.assert_eq(cb.min_value.reinterpret_as_uint(), 0x00000000U)
      @test.assert_eq(cb.delta_value.reinterpret_as_uint(), 0x3F800000U)
      @test.assert_eq(cb.value_bits, 4)
      @test.assert_eq(cb.sequence_flag, 0)
      @test.assert_eq(cb.multiplicands.length(), 2)
      @test.assert_eq(cb.multiplicands[0], 1)
      @test.assert_eq(cb.multiplicands[1], 2)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// sync pattern 不符时应返回错误。
test "codebook 解析失败：sync 错误" {
  let data = b"\x00\x00\x00\x02\x00\x04\x00\x00\x00\x00\x00\x00"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(_) => @test.fail("expected sync error")
    Err(_) => ()
  }
}
