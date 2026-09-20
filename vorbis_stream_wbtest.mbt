// Whitebox tests for vorbis_stream.mbt.
// Vorbis 按块编码，最后一个 packet 常解出超过原始长度的样本，
// 必须按 granule position 裁掉——这些测试锁住这个行为。

///|
/// 构造一个只填了 PCM 与 granule 的流，用于单独验证裁剪逻辑。
fn stream_with(pcm : Array[Array[Float]], granule : Int64) -> VorbisStream {
  {
    assembler: PacketAssembler::new(),
    header_state: 3,
    info: None,
    comment: None,
    setup: None,
    decoder: None,
    pcm,
    last_granule: granule,
  }
}

///|
/// granule 短于已解出的样本时应裁掉尾部。
test "trim_to_granule 裁掉尾部多余样本" {
  let stream = stream_with([[1.0, 2.0, 3.0, 4.0, 5.0]], 3L)
  stream.trim_to_granule()
  @test.assert_eq(stream.pcm()[0].length(), 3)
  @test.assert_eq(stream.pcm()[0][2], 3.0)
}

///|
/// 多声道时每个声道裁到同一长度。
test "trim_to_granule 逐声道裁剪" {
  let stream = stream_with([[1.0, 2.0, 3.0], [4.0, 5.0, 6.0]], 2L)
  stream.trim_to_granule()
  @test.assert_eq(stream.pcm()[0].length(), 2)
  @test.assert_eq(stream.pcm()[1].length(), 2)
  @test.assert_eq(stream.pcm()[1][1], 5.0)
}

///|
/// 没有 granule（-1）时不应改动数据。
test "trim_to_granule 在 granule 缺失时原样保留" {
  let stream = stream_with([[1.0, 2.0, 3.0]], -1L)
  stream.trim_to_granule()
  @test.assert_eq(stream.pcm()[0].length(), 3)
}

///|
/// granule 大于已解出的样本数时不能扩张数组。
test "trim_to_granule 不扩张数组" {
  let stream = stream_with([[1.0, 2.0]], 100L)
  stream.trim_to_granule()
  @test.assert_eq(stream.pcm()[0].length(), 2)
}
