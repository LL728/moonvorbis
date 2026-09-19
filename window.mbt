// window.mbt
//
// Vorbis 加窗函数：w[i] = sin(pi/2 * sin^2(pi/2 * (i+0.5)/n2))。

/// 计算 Vorbis window（长度 n2），用于相邻帧的重叠相加。
pub fn compute_window(n2 : Int) -> Array[Float] {
  let pi : Float = 3.1415927
  let half = pi / Float::from_int(2)
  let w : Array[Float] = []
  for i in 0..<n2 {
    let arg = Float::from_int(2 * i + 1) * pi / Float::from_int(4 * n2)
    let inner = @math.sinf(arg)
    let sq = inner * inner
    w.push(@math.sinf(sq * half))
  }
  w
}
