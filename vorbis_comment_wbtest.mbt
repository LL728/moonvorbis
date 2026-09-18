// Whitebox tests for vorbis_comment.mbt.
// 测试向量由 Python 构造：vendor="moonx", comments=["TITLE=Hi", "ARTIST=LL728"]。

///|
/// 正常解析 vendor 与 comment 列表。
test "解析 comment：vendor 与元数据" {
  let packet = b"\x03\x76\x6f\x72\x62\x69\x73\x05\x00\x00\x00\x6d\x6f\x6f\x6e\x78\x02\x00\x00\x00\x08\x00\x00\x00\x54\x49\x54\x4c\x45\x3d\x48\x69\x0c\x00\x00\x00\x41\x52\x54\x49\x53\x54\x3d\x4c\x4c\x37\x32\x38"
  match VorbisComment::parse(packet) {
    Ok(comment) => {
      @test.assert_eq(comment.vendor, "moonx")
      @test.assert_eq(comment.comments.length(), 2)
      @test.assert_eq(comment.comments[0], "TITLE=Hi")
      @test.assert_eq(comment.comments[1], "ARTIST=LL728")
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// 空 comment 列表也应正常解析。
test "解析 comment：空列表" {
  let packet = b"\x03vorbis\x05\x00\x00\x00moonx\x00\x00\x00\x00"
  match VorbisComment::parse(packet) {
    Ok(comment) => {
      @test.assert_eq(comment.vendor, "moonx")
      @test.assert_eq(comment.comments.length(), 0)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// magic 不符时应返回错误。
test "解析 comment 失败：magic 错误" {
  let packet = b"\x03xxxxxx\x05\x00\x00\x00moonx\x00\x00\x00\x00"
  match VorbisComment::parse(packet) {
    Ok(_) => @test.fail("expected magic error")
    Err(_) => ()
  }
}

///|
/// 数据截断时应返回错误。
test "解析 comment 失败：截断" {
  match VorbisComment::parse(b"\x03vorbis\x05\x00") {
    Ok(_) => @test.fail("expected truncation error")
    Err(_) => ()
  }
}
