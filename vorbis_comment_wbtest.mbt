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

///|
/// 查询用的测试向量：vendor="moonx"，
/// comments=["TITLE=夜曲🎵", "artist=LL728", "ARTIST=Second", "NOVALUE"]。
/// 含非 ASCII 值（含代理对）与重复 key，以及一条不含 '=' 的畸形 comment。
fn comment_fixture() -> VorbisComment {
  let packet = b"\x03\x76\x6f\x72\x62\x69\x73\x05\x00\x00\x00\x6d\x6f\x6f\x6e\x78\x04\x00\x00\x00\x10\x00\x00\x00\x54\x49\x54\x4c\x45\x3d\xe5\xa4\x9c\xe6\x9b\xb2\xf0\x9f\x8e\xb5\x0c\x00\x00\x00\x61\x72\x74\x69\x73\x74\x3d\x4c\x4c\x37\x32\x38\x0d\x00\x00\x00\x41\x52\x54\x49\x53\x54\x3d\x53\x65\x63\x6f\x6e\x64\x07\x00\x00\x00\x4e\x4f\x56\x41\x4c\x55\x45"
  match VorbisComment::parse(packet) {
    Ok(c) => c
    Err(e) => abort("fixture 应能解析: \{e}")
  }
}

///|
/// get 的 key 匹配不区分 ASCII 大小写，值是含代理对的 UTF-8。
test "查询 comment：key 不区分大小写，值含代理对" {
  let c = comment_fixture()
  @test.assert_eq(c.get("TITLE"), Some("夜曲🎵"))
  @test.assert_eq(c.get("title"), Some("夜曲🎵"))
  @test.assert_eq(c.get("TiTlE"), Some("夜曲🎵"))
}

///|
/// 同一 key 出现多次时 get 取靠前的那个，get_all 按文件顺序全部返回。
test "查询 comment：重复 key 的 get 与 get_all" {
  let c = comment_fixture()
  @test.assert_eq(c.get("ARTIST"), Some("LL728"))
  @test.assert_eq(c.get_all("ARTIST"), ["LL728", "Second"])
  @test.assert_eq(c.get_all("artist"), ["LL728", "Second"])
}

///|
/// 不存在的 key 返回 None，get_all 返回空数组。
test "查询 comment：key 不存在" {
  let c = comment_fixture()
  @test.assert_eq(c.get("ALBUM"), None)
  @test.assert_eq(c.get_all("ALBUM").length(), 0)
}

///|
/// 不含 '=' 的畸形 comment 不应被任何 key 命中，也不影响其它条目。
test "查询 comment：跳过不含 '=' 的条目" {
  let c = comment_fixture()
  @test.assert_eq(c.get("NOVALUE"), None)
  @test.assert_eq(c.get(""), None)
  @test.assert_eq(c.get("TITLE"), Some("夜曲🎵"))
}

///|
/// `=` 前有代理对时切分点仍须落在正确位置：`String::find` 返回的是 code unit 下标，
/// 若当成字符下标处理，`"🎵=X"` 会在 `🎵` 中间切开。这条把该假设钉死。
test "查询 comment：key 含代理对时正确切分" {
  let packet = b"\x03vorbis\x05\x00\x00\x00moonx\x01\x00\x00\x00\x06\x00\x00\x00\xf0\x9f\x8e\xb5\x3d\x58"
  match VorbisComment::parse(packet) {
    Ok(c) => @test.assert_eq(c.get("🎵"), Some("X"))
    Err(e) => @test.fail(e)
  }
}

///|
/// 空 comment 列表上查询返回 None。
test "查询 comment：空列表" {
  let packet = b"\x03vorbis\x05\x00\x00\x00moonx\x00\x00\x00\x00"
  match VorbisComment::parse(packet) {
    Ok(c) => {
      @test.assert_eq(c.get("TITLE"), None)
      @test.assert_eq(c.get_all("TITLE").length(), 0)
    }
    Err(e) => @test.fail(e)
  }
}
