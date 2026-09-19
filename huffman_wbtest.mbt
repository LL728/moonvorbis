// Whitebox tests for huffman.mbt.
// 参考码字由 Python 独立实现 Vorbis canonical Huffman 生成。

///|
/// 等长码 [2,2]：码字 [0, 2]（bit_reverse 后）。
test "huffman build：等长码" {
  match HuffmanTable::build([2, 2]) {
    Ok(t) => {
      @test.assert_eq(t.codewords.length(), 2)
      @test.assert_eq(t.codewords[0], 0U)
      @test.assert_eq(t.codewords[1], 2U)
      @test.assert_eq(t.symbols[0], 0)
      @test.assert_eq(t.symbols[1], 1)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// 带 hole 的码 [0,2,2]：entry 0 是 hole，解码表只含 entry 1、2。
test "huffman build：带 hole" {
  match HuffmanTable::build([0, 2, 2]) {
    Ok(t) => {
      @test.assert_eq(t.codewords.length(), 2)
      @test.assert_eq(t.symbols[0], 1)
      @test.assert_eq(t.symbols[1], 2)
      @test.assert_eq(t.codewords[0], 0U)
      @test.assert_eq(t.codewords[1], 2U)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// 变长码 [1,2,2]：码字 [0,1,3]，解码 bit 流应还原 entry 索引。
test "huffman decode：变长码" {
  let t = match HuffmanTable::build([1, 2, 2]) {
    Ok(t) => t
    Err(e) => @test.fail(e)
  }
  // entry 0：码字 [0]
  match t.decode(BitReader::new(b"\x00")) {
    Ok(s) => @test.assert_eq(s, 0)
    Err(e) => @test.fail(e)
  }
  // entry 1：码字 [1,0]
  match t.decode(BitReader::new(b"\x01")) {
    Ok(s) => @test.assert_eq(s, 1)
    Err(e) => @test.fail(e)
  }
  // entry 2：码字 [1,1]
  match t.decode(BitReader::new(b"\x03")) {
    Ok(s) => @test.assert_eq(s, 2)
    Err(e) => @test.fail(e)
  }
}
