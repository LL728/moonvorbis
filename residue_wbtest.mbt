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
  match residue.decode(BitReader::new(b"\x00"), [cb0, cb1], [target], 4) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(target[0].reinterpret_as_uint(), 0x41200000U) // 10.0
  @test.assert_eq(target[1].reinterpret_as_uint(), 0x41400000U) // 12.0
  @test.assert_eq(target[2].reinterpret_as_uint(), 0x41200000U)
  @test.assert_eq(target[3].reinterpret_as_uint(), 0x41400000U)
}

///|
/// 从字节流里解析出一个 residue 的 VQ 书：dimensions=2、entries=2、
/// lookup type 2、delta = 2^-7、multiplicands = [1,2,3,1]。
/// 于是 entry 0 = (2^-7, 2^-6)，entry 1 = (3·2^-7, 2^-7)，都是精确值。
fn vq_book_for_interleave() -> Result[Codebook, String] {
  Codebook::parse(
    BitReader::new(
      b"\x42\x43\x56\x02\x00\x02\x00\x00\x00\x20\x00\x00\x00\x00\x00\x00\x30\x5f\x21\x0f",
    ),
  )
}

///|
/// type 0 的交织写法：step 个码字按下标步进铺开。
/// 码字依次是 1、1、0，dimensions=2、step=3，于是
/// 码字 0 落在下标 0/3，码字 1 落在 1/4，码字 2 落在 2/5。
test "residue type 0：分量按下标步进摆放" {
  let book = match vq_book_for_interleave() {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let target : Array[Float] = []
  for _ in 0..<6 {
    target.push(0)
  }
  match decode_partition(book, BitReader::new(b"\x03"), target, 0, 6, 0) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(target[0].reinterpret_as_uint(), 0x3CC00000U) // 3·2^-7
  @test.assert_eq(target[1].reinterpret_as_uint(), 0x3CC00000U)
  @test.assert_eq(target[2].reinterpret_as_uint(), 0x3C000000U) // 2^-7
  @test.assert_eq(target[3].reinterpret_as_uint(), 0x3C000000U)
  @test.assert_eq(target[4].reinterpret_as_uint(), 0x3C000000U)
  @test.assert_eq(target[5].reinterpret_as_uint(), 0x3C800000U) // 2^-6
}

///|
/// 同样的码字走 type 1 就是顺序摆放，结果与 type 0 不同——这正是两种类型
/// 唯一的区别，也是这条测试存在的理由。
test "residue type 1：分量顺序摆放，与 type 0 不同" {
  let book = match vq_book_for_interleave() {
    Ok(c) => c
    Err(e) => @test.fail(e)
  }
  let target : Array[Float] = []
  for _ in 0..<6 {
    target.push(0)
  }
  match decode_partition(book, BitReader::new(b"\x03"), target, 0, 6, 1) {
    Ok(_) => ()
    Err(e) => @test.fail(e)
  }
  @test.assert_eq(target[0].reinterpret_as_uint(), 0x3CC00000U)
  @test.assert_eq(target[1].reinterpret_as_uint(), 0x3C000000U)
  @test.assert_eq(target[2].reinterpret_as_uint(), 0x3CC00000U)
  @test.assert_eq(target[3].reinterpret_as_uint(), 0x3C000000U)
  @test.assert_eq(target[4].reinterpret_as_uint(), 0x3C000000U)
  @test.assert_eq(target[5].reinterpret_as_uint(), 0x3C800000U)
}

///|
/// classbook 码字按 classification 数做进制展开，高位写在前面。
test "classification 展开：高位在前" {
  let row : Array[Int] = []
  for _ in 0..<8 {
    row.push(0)
  }
  spread_classification(row, 1, 2, 5, 3) // 5 = (1, 2) 以 3 为底
  @test.assert_eq(row[1], 1)
  @test.assert_eq(row[2], 2)
  @test.assert_eq(row[0], 0)
  @test.assert_eq(row[3], 0)
}
