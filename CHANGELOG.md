# 更新日志

本项目遵循[语义化版本](https://semver.org/lang/zh-CN/)。版本号与日期以
[mooncakes.io](https://mooncakes.io/docs/LL728/moonvorbis) 上的发布记录为准。

## [0.1.3] - 2026-10-03

### 修复

- README 的安装说明漏了 `moon add moonbitlang/x`：库示例要 `import "moonbitlang/x/fs"`，
  而依赖不会跟着包传递，新建项目照着 README 抄会在 `moon check` 时报
  「containing module is not imported」。已在全新项目里按 README 走通验证。

0.1.2 发布时这份说明还没修，包内的 README 是修复前的快照，0.1.3 是第一个带上正确
安装说明的版本。本次只改文档与版本号，代码与解码路径无变化。

## [0.1.2] - 2026-10-03

### 新增

- `VorbisComment::get(key)` 与 `VorbisComment::get_all(key)`，按 key 查询 comment
  元数据（TITLE / ARTIST 等）。key 不区分 ASCII 大小写；规范允许同一 key 重复出现
  （如多位 ARTIST），`get` 取靠前的那个，`get_all` 按文件顺序取全部。
- `VorbisStream::metadata()`，拿到 comment 头的元数据；comment 头解析前返回 `None`。
- 命令行解码时打印 TITLE / ARTIST / ALBUM（文件里有的才打印）。
- `tools/wasm_smoke.mjs`：在 Node 里真正加载 wasm 跑一遍解码，把产物与命令行解码的
  输出逐字节比对。

### 变更

- **`VorbisStream` 不再暴露任何字段**，读取一律走访问器（`is_ready` / `sample_rate` /
  `channels` / `pcm` / `granule_position` / `metadata`）。0.1.1 里这些字段是 MoonBit
  `pub struct` 的默认可见性带出来的，并非有意设计的 API；字段可写会让外部绕过
  `push_page` 的状态机次序。同时删掉了只写不读的 `setup` 字段。
- CI 增加 WASM 契约检查与运行时冒烟，并增加 js 后端测试（与 wasm-gc 跑同一套用例）。

## [0.1.1] - 2026-09-22

### 变更

- README 补齐安装方式、参考项目的许可证与参考范围声明。
- 仓库根路径做成产品主页，README 改名对齐 mooncakes 的约定。

本次改动只涉及文档与包元数据，解码路径无变化。

## [0.1.0] - 2026-09-20

首个发布版本。完整的 Vorbis I 解码链路：

- OGG 容器：页解析、segment table 重组、CRC-32 校验、跨页 packet 组装
- Vorbis 三个包头：identification / comment / setup
- codebook：Huffman 解码、VQ lookup type 1/2、`sequence_p` 累计、ordered 与 sparse 编码
- floor 0 与 floor 1
- residue type 0 / 1 / 2，含多声道交错 VQ
- 声道映射与立体声耦合反变换
- IMDCT 与重叠相加，含长短块切换
- 按 granule position 裁剪输出
- 对外接口 `decode_ogg` 与 `VorbisStream`，输出 16-bit PCM WAV
- 命令行工具、浏览器 WASM demo、与 libvorbis 的交叉验证脚本

[0.1.3]: https://github.com/LL728/moonvorbis/releases/tag/v0.1.3
[0.1.2]: https://github.com/LL728/moonvorbis/releases/tag/v0.1.2
[0.1.1]: https://mooncakes.io/docs/LL728/moonvorbis
[0.1.0]: https://mooncakes.io/docs/LL728/moonvorbis
