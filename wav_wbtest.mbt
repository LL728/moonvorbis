// Whitebox tests for wav.mbt.

///|
/// 验证 44 字节头 + 16 位样本序列化。
test "WAV 16-bit PCM 编码" {
  let pcm : Array[Array[Float]] = [[0.0, 0.5, -0.5, 1.0, -1.0]]
  let wav = wav_encode_pcm16(pcm, 44100)
  @test.assert_eq(wav.length(), 44 + 10)
  // RIFF / WAVE magic
  @test.assert_eq(wav.unsafe_get(0), b'R')
  @test.assert_eq(wav.unsafe_get(8), b'W')
  // fmt: PCM=1, mono=1, rate=44100, bits=16
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(20)).to_int(),
    1,
  )
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(22)).to_int(),
    1,
  )
  @test.assert_eq(wav.unsafe_read_uint32_le(24).reinterpret_as_int(), 44100)
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(34)).to_int(),
    16,
  )
  // data chunk 大小
  @test.assert_eq(wav.unsafe_read_uint32_le(40).reinterpret_as_int(), 10)
  // 样本：0.0 -> 0，1.0 -> 32767，-1.0 -> -32767
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(44)).to_int(),
    0,
  )
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(50)).to_int(),
    32767,
  )
  @test.assert_eq(
    Int16::reinterpret_from_uint16(wav.unsafe_read_uint16_le(52)).to_int(),
    -32767,
  )
}
