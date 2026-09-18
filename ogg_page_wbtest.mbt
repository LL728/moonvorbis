// Whitebox tests for ogg_page.mbt.
// 测试页由 Python 独立构造（含正确的 CRC），用于验证字段解析与 CRC 校验。

///|
/// 页 A：header_type=0, serial=0x12345678, granule=0, seq=0, 单 segment=[3], body="ABC"。
test "解析页 A（单 segment）" {
  let data = b"\x4f\x67\x67\x53\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x78\x56\x34\x12\x00\x00\x00\x00\x00\x00\x00\x00\x01\x03\x41\x42\x43"
  // 上面故意用 checksum=0，本测试先测「字段解析」，CRC 用下一测试单独验证
  let data_ok = b"\x4f\x67\x67\x53\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x78\x56\x34\x12\x00\x00\x00\x00\xee\x4d\x42\xfa\x01\x03\x41\x42\x43"
  match OggPage::parse(data_ok, 0) {
    Ok(page) => {
      @test.assert_eq(page.header_type, 0)
      @test.assert_eq(page.granule_position, 0L)
      @test.assert_eq(page.serial_number, 0x12345678U)
      @test.assert_eq(page.page_sequence, 0U)
      @test.assert_eq(page.n_segments, 1)
      @test.assert_eq(page.body_len, 3)
      @test.assert_eq(page.total_size(), 31)
      @test.assert_eq(page.segment_len(0), 3)
    }
    Err(e) => @test.fail(e)
  }
  // 校验 checksum=0 的页应失败（CRC 不匹配）
  match OggPage::parse(data, 0) {
    Ok(_) => @test.fail("expected CRC error")
    Err(_) => ()
  }
}

///|
/// 页 B：header_type=0x04(EOS), serial=1, granule=100, seq=5, 双 segment=[2,3], body="ABCDE"。
test "解析页 B（EOS、双 segment、非零字段）" {
  let data = b"\x4f\x67\x67\x53\x00\x04\x64\x00\x00\x00\x00\x00\x00\x00\x01\x00\x00\x00\x05\x00\x00\x00\x97\xce\xa7\xf0\x02\x02\x03\x41\x42\x43\x44\x45"
  match OggPage::parse(data, 0) {
    Ok(page) => {
      @test.assert_eq(page.header_type, 4)
      @test.assert_eq(page.granule_position, 100L)
      @test.assert_eq(page.serial_number, 1U)
      @test.assert_eq(page.page_sequence, 5U)
      @test.assert_eq(page.n_segments, 2)
      @test.assert_eq(page.body_len, 5)
      @test.assert_eq(page.total_size(), 34)
      @test.assert_eq(page.segment_len(0), 2)
      @test.assert_eq(page.segment_len(1), 3)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// magic 不符时应返回错误。
test "解析失败：magic 错误" {
  match OggPage::parse(
    b"xxxx\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00",
    0,
  ) {
    Ok(_) => @test.fail("expected magic error")
    Err(_) => ()
  }
}

///|
/// 数据截断（页头不足 27 字节）时应返回错误。
test "解析失败：页头截断" {
  match OggPage::parse(b"OggS\x00\x00", 0) {
    Ok(_) => @test.fail("expected truncation error")
    Err(_) => ()
  }
}
