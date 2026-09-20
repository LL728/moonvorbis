// mdct.mbt
//
// Vorbis IMDCT：把 n2 个频域系数原地变换为 n 个时域样本。

///|
/// Vorbis IMDCT。`buffer[0..n2]` 为输入频域系数，结果写回 `buffer[0..n]`。
pub fn inverse_mdct(buffer : Array[Float], n : Int) -> Unit {
  let n2 = n >> 1
  let x : Array[Float] = []
  for j in 0..<n2 {
    x.push(buffer[j])
  }
  let pi : Float = 3.1415927
  let scale = pi / Float::from_int(2 * n)
  for i in 0..<n {
    let mut acc : Float = 0
    for j in 0..<n2 {
      let angle = scale *
        Float::from_int(2 * i + 1 + n2) *
        Float::from_int(2 * j + 1)
      acc = acc + x[j] * @math.cosf(angle)
    }
    buffer[i] = acc
  }
}
