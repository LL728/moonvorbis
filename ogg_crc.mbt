// ogg_crc.mbt
//
// OGG 页校验使用的 CRC-32，与标准 IEEE CRC-32 有两处关键差异：
//   * 采用非反射（MSB-first 表驱动）算法，多项式 0x04C11DB7；
//   * 初始值与最终结果均为 0，不做 0xFFFFFFFF 的异或取反。
// 因此不能直接复用 zlib/标准 CRC-32 的实现。

///|
/// OGG CRC-32 查找表（256 项无符号 32 位值），在模块首次访问时惰性构造。
let crc_lookup : FixedArray[UInt] = {
  let table = FixedArray::make(256, 0U)
  for i in 0..<256 {
    let mut r : UInt = i.reinterpret_as_uint() << 24
    for _ in 0..<8 {
      if (r & 0x80000000U) != 0U {
        r = (r << 1) ^ 0x04c11db7U
      } else {
        r = r << 1
      }
    }
    table[i] = r
  }
  table
}

///|
/// 计算一段字节序列的 OGG CRC-32，返回 `0` 到 `0xFFFFFFFF` 之间的无符号值。
///
/// 调用方可将其结果写入 OGG 页头的 22..26 字节（小端）做校验。
pub fn ogg_crc32(data : Bytes) -> UInt {
  let mut crc : UInt = 0U
  for i in 0..<data.length() {
    let byte = data.unsafe_get(i).to_uint()
    let idx = ((crc >> 24) ^ byte).reinterpret_as_int()
    crc = (crc << 8) ^ crc_lookup[idx]
  }
  crc
}
