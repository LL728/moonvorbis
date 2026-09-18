// Whitebox tests for floor1.mbt.
// 测试向量由 Python 按 Vorbis floor1 setup 位布局生成。

///|
/// 简单 floor1：1 个 partition、1 个 class（dim=2, subclasses=0, book=5），
/// multiplier=1、rangebits=3、x_list=[0,8,1,3]。
test "floor1 解析：简单" {
  let data = b"\x01\x82\x01\x93\x01"
  let br = BitReader::new(data)
  match Floor1::parse(br) {
    Ok(f) => {
      @test.assert_eq(f.partitions, 1)
      @test.assert_eq(f.partition_class_list.length(), 1)
      @test.assert_eq(f.partition_class_list[0], 0)
      @test.assert_eq(f.class_dimensions[0], 2)
      @test.assert_eq(f.class_subclasses[0], 0)
      @test.assert_eq(f.class_masterbooks[0], -1)
      @test.assert_eq(f.subclass_books[0][0], 5)
      @test.assert_eq(f.multiplier, 1)
      @test.assert_eq(f.rangebits, 3)
      @test.assert_eq(f.x_list.length(), 4)
      @test.assert_eq(f.x_list[0], 0)
      @test.assert_eq(f.x_list[1], 8)
      @test.assert_eq(f.x_list[2], 1)
      @test.assert_eq(f.x_list[3], 3)
    }
    Err(e) => @test.fail(e)
  }
}

///|
/// 复杂 floor1：2 个 partition [0,1]，2 个 class：
/// class0(dim=2, subclasses=0, book=10)；class1(dim=3, subclasses=1, masterbook=5, books=[2,7])；
/// multiplier=2、rangebits=4、x_list=[0,16,3,5,7,9,11]。
test "floor1 解析：复杂（含 masterbook 与多 subclass）" {
  let data = b"\x02\x22\x2c\xa8\x82\x01\x84\x68\xea\x72\x01"
  let br = BitReader::new(data)
  match Floor1::parse(br) {
    Ok(f) => {
      @test.assert_eq(f.partitions, 2)
      @test.assert_eq(f.partition_class_list[0], 0)
      @test.assert_eq(f.partition_class_list[1], 1)
      // class 0
      @test.assert_eq(f.class_dimensions[0], 2)
      @test.assert_eq(f.class_subclasses[0], 0)
      @test.assert_eq(f.class_masterbooks[0], -1)
      @test.assert_eq(f.subclass_books[0][0], 10)
      // class 1
      @test.assert_eq(f.class_dimensions[1], 3)
      @test.assert_eq(f.class_subclasses[1], 1)
      @test.assert_eq(f.class_masterbooks[1], 5)
      @test.assert_eq(f.subclass_books[1].length(), 2)
      @test.assert_eq(f.subclass_books[1][0], 2)
      @test.assert_eq(f.subclass_books[1][1], 7)
      // multiplier / rangebits
      @test.assert_eq(f.multiplier, 2)
      @test.assert_eq(f.rangebits, 4)
      // x_list
      @test.assert_eq(f.x_list.length(), 7)
      @test.assert_eq(f.x_list[0], 0)
      @test.assert_eq(f.x_list[1], 16)
      @test.assert_eq(f.x_list[2], 3)
      @test.assert_eq(f.x_list[3], 5)
      @test.assert_eq(f.x_list[4], 7)
      @test.assert_eq(f.x_list[5], 9)
      @test.assert_eq(f.x_list[6], 11)
    }
    Err(e) => @test.fail(e)
  }
}
