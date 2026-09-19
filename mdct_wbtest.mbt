// Whitebox tests for mdct.mbt.
// 参考输出由 numpy.float32 用 32 位浮点模拟同一公式生成（与 @math.cosf 精度一致）。

///|
/// n=8、输入 [1,2,3,4]（n2=4），验证 IMDCT 输出（32 位浮点 bit 级一致）。
test "IMDCT" {
  let buffer : Array[Float] = [1, 2, 3, 4, 0, 0, 0, 0]
  inverse_mdct(buffer, 8)
  @test.assert_eq(buffer[0].reinterpret_as_uint(), 0x4020545AU)
  @test.assert_eq(buffer[1].reinterpret_as_uint(), 0xC01610EAU)
  @test.assert_eq(buffer[2].reinterpret_as_uint(), 0x401610E6U)
  @test.assert_eq(buffer[3].reinterpret_as_uint(), 0xC0205459U)
  @test.assert_eq(buffer[7].reinterpret_as_uint(), 0x409725A0U)
}
