// Whitebox tests for mapping.mbt.
// 测试向量由 Python 生成：立体声、2 个 submap、1 个耦合对、mux=[0,1]。

///|
/// channels=2，submaps=2，coupling(mag=0,angle=1)，mux=[0,1]，
/// submap0(residue=0)、submap1(residue=1)。
test "mapping 解析：立体声耦合" {
  let data = b"\x23\x80\x40\x00\x00\x00\x00\x00\x04\x00"
  let br = BitReader::new(data)
  match Mapping::parse(br, 2) {
    Ok(m) => {
      @test.assert_eq(m.submaps, 2)
      @test.assert_eq(m.coupling_steps, 1)
      @test.assert_eq(m.magnitude.length(), 1)
      @test.assert_eq(m.magnitude[0], 0)
      @test.assert_eq(m.angle[0], 1)
      @test.assert_eq(m.mux.length(), 2)
      @test.assert_eq(m.mux[0], 0)
      @test.assert_eq(m.mux[1], 1)
      @test.assert_eq(m.time_config[0], 0)
      @test.assert_eq(m.floor[0], 0)
      @test.assert_eq(m.residue[0], 0)
      @test.assert_eq(m.residue[1], 1)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// magnitude 与 angle 相等时应返回错误。
test "mapping 解析失败：magnitude 等于 angle" {
  // submaps=2, coupling_steps=1, mag=0, angle=0
  let data = b"\x23\x00"
  let br = BitReader::new(data)
  match Mapping::parse(br, 2) {
    Ok(_) => @test.fail("expected coupling error")
    Err(_) => ()
  }
}
