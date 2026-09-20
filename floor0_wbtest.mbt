// Whitebox tests for floor0.mbt.
// 测试向量由 Python 按 Vorbis floor0 位布局生成；曲线期望值由 Python 按
// libvorbis 的 floor0 合成公式逐行转写算出。

///|
/// 两个测试用的码本：一个没有 lookup table，一个维度 2、码长各 1 位、
/// delta=2^-7，其 multiplicands_f 为 [2^-7, 2^-6, 1.5*2^-6, 2^-7]。
fn floor0_test_codebooks() -> Array[Codebook] {
  let plain = match
    Codebook::parse(
      BitReader::new(b"\x42\x43\x56\x02\x00\x04\x00\x00\x04\x11\x04\x00"),
    ) {
    Ok(c) => c
    Err(e) => abort("测试码本解析失败: " + e)
  }
  let with_lookup = match
    Codebook::parse(
      BitReader::new(
        b"\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x30\x5f\x23\x64\x02",
      ),
    ) {
    Ok(c) => c
    Err(e) => abort("测试码本解析失败: " + e)
  }
  [plain, plain, with_lookup]
}

///|
/// 解析：order=4、rate=44100、barkmap=64、ampbits=6、ampdB=5、1 个 book（2 号）。
test "floor0 解析：真实配置" {
  let br = BitReader::new(b"\x04\x44\xac\x40\x00\x46\x01\x08\x00")
  match Floor0::parse(br, floor0_test_codebooks()) {
    Ok(f) => {
      @test.assert_eq(f.order, 4)
      @test.assert_eq(f.rate, 44100)
      @test.assert_eq(f.bark_map_size, 64)
      @test.assert_eq(f.amplitude_bits, 6)
      @test.assert_eq(f.amplitude_offset, 5)
      @test.assert_eq(f.books.length(), 1)
      @test.assert_eq(f.books[0], 2)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// order 为 0 时没有系数可取，配置非法。
test "floor0 解析失败：order 为 0" {
  let br = BitReader::new(b"\x00\x44\xac\x40\x00\x46\x01\x08\x00")
  match Floor0::parse(br, floor0_test_codebooks()) {
    Ok(_) => @test.fail("expected error")
    Err(_) => ()
  }
}

///|
/// book 号超出码本表范围。
test "floor0 解析失败：book 号越界" {
  let br = BitReader::new(b"\x04\x44\xac\x40\x00\x46\x01\x24\x00")
  match Floor0::parse(br, floor0_test_codebooks()) {
    Ok(_) => @test.fail("expected error")
    Err(_) => ()
  }
}

///|
/// 被引用的码本没有 lookup table，取不出 LSP 系数。
test "floor0 解析失败：book 没有 lookup table" {
  let br = BitReader::new(b"\x04\x44\xac\x40\x00\x46\x01\x00\x00")
  match Floor0::parse(br, floor0_test_codebooks()) {
    Ok(_) => @test.fail("expected error")
    Err(_) => ()
  }
}

///|
/// 幅度为 0 表示本帧没有 floor 数据，不是解码失败——调用方据此把该声道
/// 按静音处理。
test "floor0 解码：幅度为 0 视为没有 floor 数据" {
  let floor0 : Floor0 = {
    order: 4,
    rate: 44100,
    bark_map_size: 64,
    amplitude_bits: 6,
    amplitude_offset: 5,
    books: [2],
  }
  // 6 位幅度全 0
  match floor0.decode(BitReader::new(b"\x00"), []) {
    Ok(v) =>
      match v {
        Some(_) => @test.fail("expected none")
        None => ()
      }
    Err(e) => @test.fail(e)
  }
}

///|
/// 解码：幅度取满（5.0），码字依次取 entry 0、entry 1；系数按维度 2 分块，
/// 每块加上前一块的最后一个值，最后把幅度接在末尾。
test "floor0 解码：系数与幅度" {
  let floor0 : Floor0 = {
    order: 4,
    rate: 44100,
    bark_map_size: 64,
    amplitude_bits: 6,
    amplitude_offset: 5,
    books: [2],
  }
  // 幅度 63 / book 号 0 / 码字 0, 1
  match floor0.decode(BitReader::new(b"\x3f\x01"), floor0_test_codebooks()) {
    Ok(v) =>
      match v {
        Some(lsp) => {
          @test.assert_eq(lsp.length(), 5)
          @test.assert_eq(lsp[0].reinterpret_as_uint(), 0x3C000000U) //  2^-7
          @test.assert_eq(lsp[1].reinterpret_as_uint(), 0x3C800000U) //  2^-6
          @test.assert_eq(lsp[2].reinterpret_as_uint(), 0x3D200000U) // 2.5*2^-6
          @test.assert_eq(lsp[3].reinterpret_as_uint(), 0x3CC00000U) //  3*2^-7
          @test.assert_eq(lsp[4].reinterpret_as_uint(), 0x40A00000U) //  5.0
        }
        None => @test.fail("expected some")
      }
    Err(e) => @test.fail(e)
  }
}

///|
/// 合成：LSP 系数与幅度已知时，增益曲线的头几个值应与参考转写一致。
test "floor0 合成：曲线取值" {
  let floor0 : Floor0 = {
    order: 4,
    rate: 44100,
    bark_map_size: 64,
    amplitude_bits: 6,
    amplitude_offset: 5,
    books: [2],
  }
  let memo : Array[Float] = [0.3125, 0.625, 0.9375, 1.25, 5.0]
  let curve = floor0.synthesize(memo, 128)
  @test.assert_eq(curve.length(), 128)
  let expected : Array[Double] = [
    815.456, 4988.291, 4152.948, 101.185, 56.581, 112.408, 7.154, 2.364,
  ]
  for i in 0..<expected.length() {
    let got = curve[i].to_double()
    let rel = (got - expected[i]).abs() / expected[i]
    if rel > 0.001 {
      @test.fail(
        "curve[\{i}] = \{got}，期望 \{expected[i]}（相对差 \{rel}）",
      )
    }
  }
}
