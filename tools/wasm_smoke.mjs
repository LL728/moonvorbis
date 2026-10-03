#!/usr/bin/env node
// tools/wasm_smoke.mjs
//
// WASM 运行时冒烟测试：在 Node 里真正加载 wasm、解一个 OGG、写出 WAV。
// 与 tools/wasm_contract.py 互补——那个只静态解析二进制查导入/导出契约，
// 不执行任何代码；这个跑完整条解码链路，能抓到静态检查看不见的问题。
//
// 用 base64 字符串跨边界，与浏览器侧 demo/decoder.js 调用的是同一个导出。
// 需要支持 WebAssembly JS String Builtins 的 Node（V8 12.6+，即 Node 22+）。
//
// 用法:
//   node tools/wasm_smoke.mjs [out.wav] [wasm] [ogg]
// 三个参数都可省略：wasm 与 ogg 默认取仓库自带的 demo/moonvorbis.wasm 与
// demo/sample.ogg，输出默认写到系统临时目录。

import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const REPO = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..");
// 默认写临时目录，免得冒烟跑一次就在仓库里留下一个 wav。
const outPath = path.resolve(
  process.argv[2] ?? path.join(os.tmpdir(), "moonvorbis-wasm-smoke.wav"),
);
const wasmPath = path.resolve(process.argv[3] ?? path.join(REPO, "demo", "moonvorbis.wasm"));
const oggPath = path.resolve(process.argv[4] ?? path.join(REPO, "demo", "sample.ogg"));

function fail(msg) {
  console.error(`失败: ${msg}`);
  process.exit(1);
}

// demo/main.js 用的是空 imports 对象，这里保持一致：多一条导入就会实例化失败。
let exports;
try {
  const module = await WebAssembly.compile(fs.readFileSync(wasmPath), {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  ({ exports } = await WebAssembly.instantiate(module, {}));
} catch (e) {
  fail(`${wasmPath} 编译或实例化失败: ${e.message}`);
}

if (typeof exports.decode_ogg_base64 !== "function") {
  fail(`${wasmPath} 没有导出 decode_ogg_base64`);
}

const encoded = exports.decode_ogg_base64(fs.readFileSync(oggPath).toString("base64"));
if (typeof encoded !== "string" || encoded.length === 0) {
  fail(`${wasmPath} 解 ${oggPath} 返回空字符串`);
}

const wav = Buffer.from(encoded, "base64");
// 解码结果必须是完整的 WAV 容器，否则后面解出来的「一致」没有意义。
const riff = wav.subarray(0, 4).toString("latin1");
const wave = wav.subarray(8, 12).toString("latin1");
if (wav.length < 44 || riff !== "RIFF" || wave !== "WAVE") {
  fail(`解码结果不是合法的 WAV（前 4 字节 "${riff}"，8-12 字节 "${wave}"）`);
}
const declared = wav.readUInt32LE(4) + 8;
if (declared !== wav.length) {
  fail(`WAV 的 RIFF 长度字段是 ${declared}，实际 ${wav.length} 字节`);
}

fs.writeFileSync(outPath, wav);
console.log(`OK: ${path.relative(REPO, oggPath)} -> ${outPath}（${wav.length} 字节）`);
