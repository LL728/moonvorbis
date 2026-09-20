# 当 52 个测试全绿，却解不出一段正弦波

> 纯 MoonBit OGG/Vorbis 解码器开发中，用 stb_vorbis 做交叉验证揪出 7 处规范偏差的经历。

## 一、症状：一个「全绿」的失败

moonvorbis 是一个纯 MoonBit 实现的 OGG/Vorbis 解码器，不依赖任何 C 库，从字节流到 PCM 全部自己完成。写下这篇文章时，它有 52 个单元测试，全部通过；`moon check` 无警告；`moon fmt` 无改动。

然后我拿它解一个真实的 OGG 文件——用 Python 的 soundfile 生成的一段 440 Hz 正弦波，内容完全已知。

```
解码失败: missing setup framing flag
```

连 setup header 都没解析过去。

把 parse 层的问题勉强绕开之后，第二次运行给出的不是报错，而是更糟的东西：一段**饱和方波**。所有样本都被顶到 ±1.0，RMS 高达 1.02，而原信号的 RMS 应该是 0.283。

这两个失败分属不同层次。第一个是解析挂了，一目了然；第二个是解析全部通过、程序不报任何错、只是算出来的东西完全不对——这才是真正难查的那类。

## 二、为什么自造测试抓不到

关键问题在测试向量是从哪来的。

那些测试里的字节序列，是我照着 Vorbis 规范文档，按自己的理解手写出来的。于是形成了一个闭环：

```
我理解规范 → 写出测试向量 → 写出实现 → 测试通过 ✅
     ↑__________________________________________|
```

如果我对规范的理解是错的，那么**测试向量和实现是错在同一边的**——它们共享同一个错误前提，然后互相印证。测试跑得再多次，也只是在确认「我的实现和我的理解一致」，而这从来不是问题所在。

这不是覆盖率不够。52 个测试覆盖了 codebook、floor、residue、mapping、IMDCT 的每一条分支。问题是**参照系本身偏了**。

要发现这种偏差，需要一个独立于我理解的参照系。

## 三、方法：引入外部对照

三件事：

**1. 一个「可执行的规范」。** [stb_vorbis.c](https://github.com/nothings/stb) 是 public domain 的单文件 C 实现，被广泛使用和验证过。规范文档是散文，可以有多种读法；stb_vorbis 是同一份规范的一种**确定性读法**，可以直接对着看。

**2. 已知内容的输入。** 用 libvorbis（经 Python soundfile）生成正弦波 OGG。信号内容是我自己定的，就避免了「输出看起来像音频」这种模糊判据。

**3. 连续量而非布尔量做判据。** 不再问「解码成功了吗」，而是问「解出来的波形和原波形差多少」：

```python
a, _ = sf.read('decoded.wav', always_2d=True)
b, _ = sf.read('source.ogg',  always_2d=True)
corr = np.corrcoef(a[:, ch], b[:, ch])[0, 1]
rms  = np.sqrt(np.mean((a[:, ch] - b[:, ch]) ** 2))
```

相关系数能把「大致对但有系统偏差」「方向对但幅度错」「只是相位偏了」区分开，而布尔判据会把它们全部归为「跑通了」。

## 四、七处规范偏差

以下每一条都是「读规范时理解偏了」。修复之前，这七条全部处于「测试通过」的状态——有的是因为测试断言的正是那个错误的理解，有的是因为根本没有测试覆盖到那条分支。**测试全绿只说明实现与理解自洽，不说明理解正确。**

### 1. mapping 的 submaps 与 coupling_steps 各有 1 位标志位

`coupling_steps`（立体声耦合的对数）前面有一个 1 位 flag，置位才读 8 位；`submaps` 前面**也**有一个独立的 1 位 flag。

我原来的实现是靠推断：

```moonbit
// 错的：用 submaps 的数量去猜有没有 coupling
if submaps > 1 {
  coupling_steps = br.read_bits(8) + 1
  ...
}
```

这个启发式在多数立体声文件上「恰好」成立——因为立体声通常确实有多个 submap。但它不是规范。规范里这是两个互相独立的标志位，我就这么少读了一位，后面所有字段跟着错位。

```moonbit
// 对的：两个独立的 1 位 flag
let submaps = if br.read_bits(1) == 1 { br.read_bits(4) + 1 } else { 1 }

let mut coupling_steps = 0
if br.read_bits(1) == 1 {
  coupling_steps = br.read_bits(8) + 1
  ...
}
```

**这类「看起来合理的猜测」是最危险的**，因为它比错误更隐蔽：它在常见的输入上能工作。

### 2. `lookup1_values` 要向下取整，不是四舍五入

lookup type 1 的 codebook 有 `r` 个 lookup value，`r` 满足 `r^dim <= entries`。

我原来写的是「让 `r^dim` 最接近 `entries`」——当时觉得这样更精确，避免浮点误差：

```moonbit
// 错的
let lo = pow_int(r - 1, dim)
let hi = pow_int(r, dim)
if entries - lo < hi - entries { r - 1 } else { r }
```

规范要的是 floor。多出来的那个 r 会让 VQ 查找越界。

### 3. ordered codebook 的码长每次游程后自增 1

ordered codebook 的码长用游程编码。我漏掉了规范伪码里的一行：**每处理完一个游程，`current_length` 递增 1**，而不是重新读 5 位。

```moonbit
// 错的：每个游程都重读 5 位
current_length = br.read_bits(5) + 1

// 对的
current_length += 1
```

stb_vorbis 里对应的是 `codeword_lengths` 那段的 `++current_length;`——对着源码看，这一行非常显眼，对着规范散文读，很容易滑过去。

### 4. lookup type 1 的 multiplicands 要按 base-r 预展开

这一条的症状是运行时 panic：

```
RuntimeError: unreachable at Codebook::decode_vq
```

原因：VQ 解码时按 `dim` 为步长从 `multiplicands` 里取系数，但 lookup type 1 在文件里存的是 `r` 个标量（`r^dim = entries`），每 `dim` 个标量组合成一个码字。必须在解析阶段就展开成 `entries × dim` 的二维表，否则索引会直接越界。

```moonbit
let dim = self.dimensions
let base = entry * dim          // 展开后：每个 entry 占 dim 个连续下标
for ii in 0..<nn {
  targets[ch][offset + ii] = book.multiplicands_f[base + ii]
}
```

### 5. Vorbis 的 32 位浮点数**不是 IEEE 754**

`min_value` 和 `delta_value` 是 32 位，但它们不是 IEEE 754 单精度。我按位重解释成了 IEEE，结果就是**幅度全错**——这正是那段饱和方波的来源。

Vorbis 用的是自定义格式：**1 位符号 + 10 位指数 + 21 位尾数**，值为 `mantissa × 2^(exponent - 788)`，指数没有偏移编码，且尾数不隐含前导 1。

```moonbit
/// Vorbis 专用的 32 位浮点解包：1 位符号 + 10 位指数 + 21 位尾数。
/// 值为 `mantissa * 2^(exponent - 788)`，与 IEEE 754 不同，不能按位重解释。
fn float32_unpack(x : UInt) -> Float {
  let mantissa = (x & 0x1fffffU).reinterpret_as_int()
  let sign = (x & 0x80000000U) != 0U
  let exp = ((x & 0x7fe00000U) >> 21).reinterpret_as_int()
  let res = if sign { Float::from_int(0 - mantissa) } else { Float::from_int(mantissa) }
  @math.scalbnf(res, exp - 788)
}
```

**注意这个错误的隐蔽性**：程序不崩溃、不报错、解出来的确实「是音频」，只是每个值是错的。除了一听就知道不对，只有算相关系数才能量化地看出它错得多彻底。

### 6. 音频 packet 的第 0 位是 packet type

Vorbis 的包分两类：头部包（identification / comment / setup）和音频包。音频包的**第一个 bit 是 packet type，必须为 0**，其后才是 mode number。

我原来直接从第 0 位读 mode number，等于每个音频包都少读了一位，后面整个位流错位。

```moonbit
// 音频 packet 的第一个 bit 是 packet type（0 = audio，1 = header）
if br.read_bits(1) != 0 {
  return Err("not an audio packet")
}
let mode_number = br.read_bits(ilog(self.setup.modes.length() - 1))
```

### 7. residue 的 classifications 数组大小，与 type 2 的 target 长度

最后一个 panic：

```
RuntimeError: unreachable at Residue::decode (Array::set)
```

`classifications` 数组原本只分配了 `part_read` 个元素。但内层循环一次会消费 `classwords` 个（`classwords` 是 classbook 的维度），在 `pcount` 接近 `part_read` 时索引会越过末尾。需要留出 `part_read + classwords` 大小。

同时，type 2 的 residue 是 non-interleaved 的，系数缓冲的有效长度是 `n * 2`（即 `n2` 的两倍），不是 `n2`。

### 补充：块切换时的窗边界

修完上面 7 条之后，波形终于「是」那个正弦波了，但仍有系统性偏差。最后一条不在 header 解析层，而在解码流程里：**长块与短块切换时，sin 窗的有效区域要按小块的尺寸收窄**。

```moonbit
let left_start = if blockflag == 1 && prev == 0 {
  (n - self.info.blocksize0) >> 2
} else { 0 }
let right_start = if blockflag == 1 && next == 0 {
  (3 * n - self.info.blocksize0) >> 2
} else { n2 }
let right_end = if blockflag == 1 && next == 0 {
  (3 * n + self.info.blocksize0) >> 2
} else { n }
```

这一条的教训是：**即使 header 全对，解码流程本身也可能有自己的坑**。相关系数在这里的作用体现得最明显——波形肉眼看着完全正常，但相关系数就是卡在 0.98 上不去，逼着我去找那个「还差一点」的地方。

## 五、修复后的验证

同一段立体声正弦波（左 440 Hz / 右 554 Hz），解码结果与 libvorbis 原始输出的对比：

```
声道 0:  相关系数 0.9999   RMS 误差 0.0032
声道 1:  相关系数 0.9998   RMS 误差 0.0066
```

残余误差来自两处，都是预期内的：Vorbis 本身是有损压缩（我对比的是解码结果而非原始波形），以及 float32 精度与首帧的 overlap 偏移。

从 RMS 1.02 的饱和方波，到相关系数 0.9999——**这个数字才是「解码器真的工作了」的证据**，而不是「测试全绿」。

## 六、可迁移的部分

几个不限于 Vorbis 的结论：

1. **自造测试有结构性盲区。** 如果测试向量的来源和实现的来源是同一个人的同一次理解，它们无法互相证伪。这不是覆盖率的锅。

2. **找一个「可执行的规范」。** 散文规范可以有多种读法，一份被广泛使用的参考实现只有一种。对着源码看，能发现对着文档读时滑过去的东西——比如那行 `++current_length`。

3. **用连续量做判据。** 「成功/失败」把「完全正确」和「方向对但幅度错 80%」归成了一类。相关系数、RMS 差值这类连续量，能把错误定位到具体是哪个环节。

4. **区分「panic 型」和「静默型」错误。** 越界、断言失败这类会自己跳出来，是幸运的；数值格式理解错、少读一个标志位这类不报错的，必须靠外部对照才能发现。**后者的危险程度远高于前者**——它们会在测试全绿的情况下顺利通过。

5. **当心「在常见输入上恰好成立」的启发式。** `if submaps > 1` 猜 coupling 那次最典型。这类代码比明显的 bug 更麻烦，因为它能通过你所有的测试。

## 七、现状

修复后，解码器支持：

- OGG 容器：页解析、CRC-32 校验、跨页 packet 组装
- 三个 Vorbis 包头
- codebook（Huffman + VQ lookup type 1/2）、floor 1、residue type 1/2
- 立体声耦合、IMDCT、含长短块切换的重叠相加
- 输出多声道 16-bit PCM WAV

尚未支持：floor 0、residue type 0、lattice codebook。

除命令行外，也编译了 WebAssembly 版本，可以在浏览器里直接解码播放——见 [`demo/`](../demo/)。
