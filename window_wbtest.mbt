// Whitebox tests for window.mbt.
// 参考值由 numpy.float32 用 32 位浮点模拟生成。

///|
/// n2=8，验证 window 的前后关键值。
test "window 计算" {
  let w = compute_window(8)
  @test.assert_eq(w[0].reinterpret_as_uint(), 0x3C773EB4U)
  @test.assert_eq(w[1].reinterpret_as_uint(), 0x3E07250EU)
  @test.assert_eq(w[2].reinterpret_as_uint(), 0x3EAF1BD9U)
  @test.assert_eq(w[3].reinterpret_as_uint(), 0x3F174543U)
  @test.assert_eq(w[7].reinterpret_as_uint(), 0x3F7FF88AU)
}
