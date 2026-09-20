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

```bash
# 重新生成 demo/moonvorbis.wasm（仓库内已附带一份）
moon build --target wasm-gc --release
cp _build/wasm-gc/release/build/moonvorbis.wasm demo/

python -m http.server
# 打开 http://localhost:8000/demo/
```

页面在本地完成解码，音频不会上传。需要浏览器支持 WebAssembly JS String
Builtins（Chrome / Edge 130+）。

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

## 测试

```bash
moon test
```

## 限制

- 尚未支持 floor 0、residue type 0、lattice codebook
- 只做解码，不做编码
