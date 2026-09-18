// Whitebox tests for ogg_crc.mbt.
// 参考向量由独立的 Python 实现（同一算法）生成，用于对拍验证。

///|
/// 空输入的 OGG CRC-32 应为 0（初始值即 0，且无字节参与运算）。
test "ogg_crc32 空输入" {
  @test.assert_eq(ogg_crc32(b""), 0x00000000U)
}

///|
/// OGG 页的 magic number "OggS"。
test "ogg_crc32 magic 字节" {
  @test.assert_eq(ogg_crc32(b"OggS"), 0x5fb0a94fU)
}

///|
/// 普通 ASCII 文本。
test "ogg_crc32 ascii" {
  @test.assert_eq(ogg_crc32(b"hello"), 0xa1de215eU)
}

///|
/// 二进制字节序列。
test "ogg_crc32 二进制" {
  @test.assert_eq(ogg_crc32(b"\x00\x01\x02\x03"), 0xac691451U)
}

///|
/// OGG 页头前缀（magic "OggS" + version 0 + header_type 2 + granule 前 6 字节）。
/// 与 Python 参考实现使用完全相同的 12 字节输入对拍。
test "ogg_crc32 页头前缀" {
  @test.assert_eq(
    ogg_crc32(b"OggS\x00\x02\x00\x00\x00\x00\x00\x00"),
    0x6f19142cU,
  )
}
