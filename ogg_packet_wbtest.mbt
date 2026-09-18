// Whitebox tests for ogg_packet.mbt.
// 用程序化构造的 OggPage（不经过 parse，因为 packet 重组不关心 CRC/页头字段）验证 lacing 逻辑。

///|
/// 构造一个 `len` 字节、内容全为 `byte` 的 Bytes。
fn repeat_byte(byte : Byte, len : Int) -> Bytes {
  let buf = @buffer.Buffer()
  for _ in 0..<len {
    buf.write_byte(byte)
  }
  buf.to_bytes()
}

///|
/// 构造一个测试用 OggPage：27 字节假头 + segment table + body。
/// packet 重组只读 segment table 和 body，头字段不参与，故全部置 0。
fn make_page(segments : Array[Int], body : Bytes) -> OggPage {
  let buf = @buffer.Buffer()
  for _ in 0..<27 {
    buf.write_byte(b'\x00')
  }
  for i in 0..<segments.length() {
    buf.write_byte(segments[i].to_byte())
  }
  for i in 0..<body.length() {
    buf.write_byte(body.unsafe_get(i))
  }
  {
    data: buf.to_bytes(),
    offset: 0,
    header_type: 0,
    granule_position: 0L,
    serial_number: 0U,
    page_sequence: 0U,
    checksum: 0U,
    n_segments: segments.length(),
    body_len: body.length(),
  }
}

///|
/// 单 segment（长度 < 255）组成一个完整 packet。
test "单 segment 页内完成" {
  let assembler = PacketAssembler::new()
  let page = make_page([3], b"ABC")
  let packets = assembler.push_page(page)
  @test.assert_eq(packets.length(), 1)
  @test.assert_eq(packets[0], b"ABC")
  @test.assert_eq(assembler.has_partial(), false)
}

///|
/// 多个 segment 组成多个 packet，每个长度 < 255 的 segment 结束一个 packet。
test "多 segment 页内完成多个 packet" {
  let assembler = PacketAssembler::new()
  let page = make_page([2, 3], b"ABCDE")
  let packets = assembler.push_page(page)
  @test.assert_eq(packets.length(), 2)
  @test.assert_eq(packets[0], b"AB")
  @test.assert_eq(packets[1], b"CDE")
}

///|
/// segment 长度为 255 表示 packet 继续，与下一个 segment 合并成一个 packet。
test "跨 segment 重组" {
  let assembler = PacketAssembler::new()
  let body = repeat_byte(b'A', 260)
  let page = make_page([255, 5], body)
  let packets = assembler.push_page(page)
  @test.assert_eq(packets.length(), 1)
  @test.assert_eq(packets[0].length(), 260)
  @test.assert_eq(assembler.has_partial(), false)
}

///|
/// 页以长度 255 的 segment 结尾时 packet 未完成，由下一页继续。
test "跨页重组" {
  let assembler = PacketAssembler::new()
  let page1 = make_page([255], repeat_byte(b'A', 255))
  let packets1 = assembler.push_page(page1)
  @test.assert_eq(packets1.length(), 0)
  @test.assert_eq(assembler.has_partial(), true)

  let page2 = make_page([10], repeat_byte(b'B', 10))
  let packets2 = assembler.push_page(page2)
  @test.assert_eq(packets2.length(), 1)
  @test.assert_eq(packets2[0].length(), 265)
}
