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
/// ordered，6 个 entry，起始码长 3，游程 (长度 3 × 2, 长度 4 × 4)，无 lookup table。
/// ordered 的码长每次游程后递增 1（不重读）。
test "codebook 解析：ordered 游程编码" {
  let data = b"\x42\x43\x56\x01\x00\x06\x00\x00\x85\x08"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 1)
      @test.assert_eq(cb.entries, 6)
      @test.assert_eq(cb.lengths.length(), 6)
      @test.assert_eq(cb.lengths[0], 3)
      @test.assert_eq(cb.lengths[1], 3)
      @test.assert_eq(cb.lengths[2], 4)
      @test.assert_eq(cb.lengths[3], 4)
      @test.assert_eq(cb.lengths[4], 4)
      @test.assert_eq(cb.lengths[5], 4)
      @test.assert_eq(cb.lookup_type, 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// lookup type 1：min=0.0、delta=1.0、value_bits=4、sequence=0、原始 2 个 multiplicands [1,2]。
/// lookup1_values(4, 2) = 2，原始值按 base-2 unvectorize 展开成 entries*dim = 8 个。
test "codebook 解析：lookup table type 1" {
  let data = b"\x42\x43\x56\x02\x00\x04\x00\x00\x04\x11\x44\x00\x00\x00\x00\x04\x00\x00\x8a\x8d\x10"
  let br = BitReader::new(data)
  match Codebook::parse(br) {
    Ok(cb) => {
      @test.assert_eq(cb.dimensions, 2)
      @test.assert_eq(cb.entries, 4)
      @test.assert_eq(cb.lookup_type, 1)
      // min=0.0 是 0x00000000；delta=1.0 解包后是标准 Float 1.0（IEEE 754 位 0x3F800000）
      @test.assert_eq(cb.min_value.reinterpret_as_uint(), 0x00000000U)
      @test.assert_eq(cb.delta_value.reinterpret_as_uint(), 0x3F800000U)
      @test.assert_eq(cb.value_bits, 4)
      @test.assert_eq(cb.sequence_flag, 0)
      @test.assert_eq(cb.multiplicands.length(), 2)
      @test.assert_eq(cb.multiplicands[0], 1)
      @test.assert_eq(cb.multiplicands[1], 2)
      // 预展开成 entries*dim = 8 个：entry0=[1,1] entry1=[2,1] entry2=[1,2] entry3=[2,2]
      @test.assert_eq(cb.multiplicands_f.length(), 8)
      @test.assert_eq(cb.multiplicands_f[0].reinterpret_as_uint(), 0x3F800000U)
      @test.assert_eq(cb.multiplicands_f[1].reinterpret_as_uint(), 0x3F800000U)
      @test.assert_eq(cb.multiplicands_f[2].reinterpret_as_uint(), 0x40000000U)
      @test.assert_eq(cb.multiplicands_f[3].reinterpret_as_uint(), 0x3F800000U)
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
