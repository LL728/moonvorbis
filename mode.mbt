// mode.mbt
//
// Vorbis mode setup 解析。
//
// mode 决定每个音频 packet 的 block size（长/短块）与使用的 mapping。
// Vorbis 当前仅支持 window type 0 与 transform type 0。

///|
/// 单个 mode 的配置。
pub struct Mode {
  blockflag : Int
  windowtype : Int
  transformtype : Int
  mapping : Int
}

///|
/// 从 `br` 的当前位置解析全部 mode（mode count 在前，后跟每个 mode 的字段）。
///
/// 校验 windowtype / transformtype 必须为 0（Vorbis 仅支持这一种）。
pub fn parse_modes(br : BitReader) -> Result[Array[Mode], String] {
  let mode_count = br.read_bits(6) + 1
  let modes : Array[Mode] = []
  for _ in 0..<mode_count {
    let blockflag = br.read_bits(1)
    let windowtype = br.read_bits(16)
    let transformtype = br.read_bits(16)
    let mapping = br.read_bits(8)
    if windowtype != 0 || transformtype != 0 {
      return Err("unsupported window/transform type")
    }
    modes.push({ blockflag, windowtype, transformtype, mapping, })
  }
  Ok(modes)
}
