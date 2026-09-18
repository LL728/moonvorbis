// Whitebox tests for bitreader.mbt.
// 这些测试运行在包内部作用域，可以直接访问 BitReader 的 pub API。

///|
/// 0xB2 = 0b10110010，LSB-first 逐位读取应依次得到 0,1,0,0,1,1,0,1。
test "read_bit LSB-first 逐位顺序" {
  let br = BitReader::new(b"\xB2")
  @test.assert_eq(br.read_bit(), 0)
  @test.assert_eq(br.read_bit(), 1)
  @test.assert_eq(br.read_bit(), 0)
  @test.assert_eq(br.read_bit(), 0)
  @test.assert_eq(br.read_bit(), 1)
  @test.assert_eq(br.read_bit(), 1)
  @test.assert_eq(br.read_bit(), 0)
  @test.assert_eq(br.read_bit(), 1)
}

///|
/// 读满一个完整字节时，LSB-first 顺序拼回去应还原为原字节值。
test "read_bits 读满一个字节等于原字节值" {
  let br = BitReader::new(b"\xB2")
  @test.assert_eq(br.read_bits(8), 178)
}

///|
/// 0x05 = 0b00000101，低 3 位 LSB-first 为 1,0,1 → 1 + 0 + 4 = 5。
test "read_bits 读取部分位" {
  let br = BitReader::new(b"\x05")
  @test.assert_eq(br.read_bits(3), 5)
}

///|
/// 跨字节读取：前 8 位来自 0xFF（=255），第 9 位来自 0x01 的最低位（=1），
/// 结果为 255 + (1 << 8) = 511。
test "read_bits 跨字节读取" {
  let br = BitReader::new(b"\xFF\x01")
  @test.assert_eq(br.read_bits(9), 511)
}

///|
/// 位位置推进：读 5 位后 tell=5，remaining=19；seek 回退到 2 位处生效。
test "tell seek remaining 定位" {
  let br = BitReader::new(b"\x00\x00\x00") // 24 位
  let _ = br.read_bits(5)
  @test.assert_eq(br.tell(), 5)
  @test.assert_eq(br.remaining_bits(), 19)
  br.seek(2)
  @test.assert_eq(br.tell(), 2)
}

///|
/// byte_align 把非字节对齐的位置推进到下一个字节边界。
test "byte_align 字节对齐" {
  let br = BitReader::new(b"\x00\x00")
  br.skip(3)
  br.byte_align()
  @test.assert_eq(br.tell(), 8)
}

///|
/// 已经字节对齐时 byte_align 不应改变位置。
test "byte_align 已在边界时不移动" {
  let br = BitReader::new(b"\x00\x00")
  br.skip(8)
  br.byte_align()
  @test.assert_eq(br.tell(), 8)
}
