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

///|
/// sequence_p（lattice codebook）：码字内部逐分量累加，累加器每个 entry 归零。
/// 两个码本除 sequence 位外完全相同。原始 multiplicands [1,2,3,1]、delta=2^-7，
/// 即 [2^-7, 2^-6, 1.5*2^-6, 2^-7]。
test "codebook：sequence_p 逐 entry 累加" {
  let plain = match
    Codebook::parse(
      BitReader::new(
        b"\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x30\x5f\x21\x0f",
      ),
    ) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let seqp = match
    Codebook::parse(
      BitReader::new(
        b"\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x30\x5f\x31\x0f",
      ),
    ) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }

  // 只有 sequence 位不同
  @test.assert_eq(plain.sequence_flag, 0)
  @test.assert_eq(seqp.sequence_flag, 1)
  @test.assert_eq(plain.multiplicands, seqp.multiplicands)

  // 未置位：逐分量原样展开
  @test.assert_eq(plain.multiplicands_f.length(), 4)
  @test.assert_eq(plain.multiplicands_f[0].reinterpret_as_uint(), 0x3C000000U) //  2^-7
  @test.assert_eq(plain.multiplicands_f[1].reinterpret_as_uint(), 0x3C800000U) //  2^-6
  @test.assert_eq(plain.multiplicands_f[2].reinterpret_as_uint(), 0x3CC00000U) // 1.5*2^-6
  @test.assert_eq(plain.multiplicands_f[3].reinterpret_as_uint(), 0x3C000000U) //  2^-7

  // 置位：entry 内累加，entry 1 的累加器从零重新开始。
  @test.assert_eq(seqp.multiplicands_f.length(), 4)
  @test.assert_eq(seqp.multiplicands_f[0].reinterpret_as_uint(), 0x3C000000U) // 2^-7
  @test.assert_eq(seqp.multiplicands_f[1].reinterpret_as_uint(), 0x3CC00000U) // 2^-7 + 2^-6
  @test.assert_eq(seqp.multiplicands_f[2].reinterpret_as_uint(), 0x3CC00000U) // 1.5*2^-6，重新开始
  @test.assert_eq(seqp.multiplicands_f[3].reinterpret_as_uint(), 0x3D000000U) // 1.5*2^-6 + 2^-7
}

///|
/// VQ 解码：维度 2 的码本只填 3 个位置——第二个码字只用得上一个分量，
/// 多出来的那个分量不该落到目标数组之外，也不该被写进去。
///
/// 码本同上（dimensions=2、entries=2、码长各 1 位、delta=2^-7），
/// multiplicands_f 为 [2^-7, 2^-6, 1.5*2^-6, 2^-7]。位流先给码字 0 再给
/// 码字 1，即 entry 0 的两个分量、entry 1 的第一个分量。
test "codebook：VQ 解码填不满一个码字时只用前几个分量" {
  let cb = match
    Codebook::parse(
      BitReader::new(
        b"\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x30\x5f\x23\x64\x02",
      ),
    ) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(cb.dimensions, 2)
  @test.assert_eq(cb.entries, 2)

  // 位流：码字 0 → entry 0，码字 1 → entry 1
  let target : Array[Float] = [99.0, 99.0, 99.0, 99.0]
  match cb.decode_vq_set(BitReader::new(b"\x02"), target, 0, 3) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  // 目标位置被赋值覆盖，而不是与初值相加
  @test.assert_eq(target[0].reinterpret_as_uint(), 0x3C000000U) //  2^-7
  @test.assert_eq(target[1].reinterpret_as_uint(), 0x3C800000U) //  2^-6
  @test.assert_eq(target[2].reinterpret_as_uint(), 0x3CC00000U) // 1.5*2^-6
  // 范围之外的位置不动
  @test.assert_eq(target[3].reinterpret_as_uint(), 99.0F.reinterpret_as_uint())

  // 从 offset 1 起填 4 个位置：两个码字都取 entry 1，正好两个整码字
  let target2 : Array[Float] = [99.0, 99.0, 99.0, 99.0, 99.0, 99.0]
  match cb.decode_vq_set(BitReader::new(b"\x03"), target2, 1, 4) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(target2[0].reinterpret_as_uint(), 99.0F.reinterpret_as_uint())
  @test.assert_eq(target2[1].reinterpret_as_uint(), 0x3CC00000U) // 1.5*2^-6
  @test.assert_eq(target2[2].reinterpret_as_uint(), 0x3C000000U) // 2^-7
  @test.assert_eq(target2[3].reinterpret_as_uint(), 0x3CC00000U) // 1.5*2^-6
  @test.assert_eq(target2[4].reinterpret_as_uint(), 0x3C000000U) // 2^-7
  @test.assert_eq(target2[5].reinterpret_as_uint(), 99.0F.reinterpret_as_uint())
}

///|
/// 没有 lookup table 的码本取不出分量，应当报错而不是填零。
test "codebook：VQ 解码拒绝无 lookup table 的码本" {
  let cb = match
    Codebook::parse(
      BitReader::new(b"\x42\x43\x56\x02\x00\x04\x00\x00\x04\x11\x04\x00"),
    ) {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let target : Array[Float] = [0.0, 0.0]
  match cb.decode_vq_set(BitReader::new(b"\x00"), target, 0, 2) {
    Ok(_) => @test.fail("expected error")
    Err(_) => ()
  }
}
