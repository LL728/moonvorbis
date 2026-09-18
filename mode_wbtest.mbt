// Whitebox tests for mode.mbt.
// 测试向量由 Python 生成：2 个 mode。

///|
/// mode0(blockflag=0, mapping=0)、mode1(blockflag=1, mapping=1)。
test "mode 解析" {
  let data = b"\x01\x00\x00\x00\x00\x80\x00\x00\x00\x00\x01"
  let br = BitReader::new(data)
  match parse_modes(br) {
    Ok(modes) => {
      @test.assert_eq(modes.length(), 2)
      @test.assert_eq(modes[0].blockflag, 0)
      @test.assert_eq(modes[0].windowtype, 0)
      @test.assert_eq(modes[0].transformtype, 0)
      @test.assert_eq(modes[0].mapping, 0)
      @test.assert_eq(modes[1].blockflag, 1)
      @test.assert_eq(modes[1].mapping, 1)
    }
    Err(e) => @test.fail(e)
  }
}
