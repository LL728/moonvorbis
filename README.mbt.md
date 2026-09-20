# moonvorbis

纯 MoonBit 实现的 OGG/Vorbis 音频解码器。不依赖任何 C 库或系统编解码器，
从字节流到 PCM 全部由 MoonBit 代码完成。

支持解码为标准 WAV、命令行批量转换，以及编译成 WebAssembly 在浏览器内直接播放。

## 功能

- **OGG 容器**：页解析、segment table 重组、CRC-32 校验、packet 组装
- **Vorbis 头部**：identification / comment / setup 三个包头
- **Codebook**：Huffman 解码、VQ lookup type 1/2、ordered 与 sparse 编码
- **Floor 1**：曲线解码与合成
- **Residue**：type 1 / type 2，含多声道交错 VQ
- **立体声耦合**：magnitude/angle 反变换
- **IMDCT 与重叠相加**：含长短块（window switching）切换
- **输出**：多声道 16-bit PCM WAV

## 用法

### 命令行

```bash
moon run cmd/main --target wasm-gc -- input.ogg output.wav
```

省略输出路径时写入 `input.ogg.wav`。

### 浏览器

线上版本：<https://ll728.github.io/moonvorbis/demo/>

本地运行：

```bash
# 重新生成 demo/moonvorbis.wasm（仓库内已附带一份）
moon build --target wasm-gc --release
cp _build/wasm-gc/release/build/moonvorbis.wasm demo/

python -m http.server
# 打开 http://localhost:8000/demo/
```

页面在本地完成解码，音频不会上传。需要浏览器支持 WebAssembly JS String
Builtins：Chrome / Edge 130+、Firefox 134+，Safari 目前不支持。

## 结构

| 文件 | 职责 |
| --- | --- |
| `bitreader.mbt` | LSB-first 位读取器，带越界检查 |
| `ogg_crc.mbt` | OGG 页校验用的 CRC-32 |
| `ogg_page.mbt` | 页头解析与校验 |
| `ogg_packet.mbt` | 跨页 packet 组装 |
| `vorbis_info.mbt` | identification 头 |
| `vorbis_comment.mbt` | comment 头 |
| `vorbis_setup.mbt` | setup 头，聚合下列子结构 |
| `codebook.mbt` | codebook 与 Huffman/VQ 解码 |
| `huffman.mbt` | Huffman 表构建 |
| `floor1.mbt` | floor1 解码与合成 |
| `residue.mbt` | residue 配置与解码 |
| `mapping.mbt` | channel mapping 与耦合 |
| `mode.mbt` | block flag / mapping 选择 |
| `mdct.mbt` | IMDCT |
| `window.mbt` | 窗函数 |
| `decoder.mbt` | 解码主循环 |
| `vorbis_stream.mbt` | 高层编排：字节流 → PCM |
| `wav.mbt` | WAV 序列化 |
| `wasm_api.mbt` | WASM 导出接口 |
| `cmd/main/` | 命令行入口 |
| `tools/verify.py` | 对 libvorbis 的交叉验证脚本 |
| `tools/wasm_contract.py` | 静态校验 wasm 的导入/导出契约 |
| `demo/headless-test.html` | 无头浏览器冒烟测试 |

## 测试

```bash
moon test
```

单元测试验证的是「实现与理解自洽」，抓不到规范理解本身的偏差。作为补充，
`tools/verify.py` 从零生成已知内容的 OGG、用本解码器解出 WAV，再和 libvorbis
的输出比较相关系数与 RMS 误差：

```bash
python tools/verify.py --stereo            # 相关系数 0.9999
python tools/verify.py --stereo --noise    # 相关系数 0.9970
```

需要 `numpy` 与 `soundfile`。

WASM 侧另有两个检查。`tools/wasm_contract.py` 静态解析二进制，确认导出
`decode_ogg_base64` 的签名是 `String -> String`，且除引擎内置外没有任何导入
（`demo/main.js` 用的是空 imports 对象，多一条导入实例化就会失败）。
`demo/headless-test.html` 则在无头浏览器里跑完整链路，把 WAV 校验和写进页面：

```bash
python tools/wasm_contract.py
msedge --headless=new --virtual-time-budget=20000 \
  --dump-dom http://localhost:8000/demo/headless-test.html
```

随附的 `demo/sample.ogg` 在浏览器中解出 2ch / 44100Hz / 44608 帧，与命令行
解码的产物逐字节相同。

## 开发记录

[当 52 个测试全绿，却解不出一段正弦波](docs/stb-vorbis-cross-validation.md) ——
记录用 stb_vorbis 交叉验证揪出 7 处 Vorbis 规范偏差的过程，以及为什么自造测试
抓不到这类错误。

## 限制

- 尚未支持 floor 0、residue type 0、lattice codebook
- 只做解码，不做编码
