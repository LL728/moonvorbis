// demo/main.js
//
// 浏览器演示：加载 moonvorbis.wasm，把 OGG 字节交给 MoonBit 解码，播放返回的 WAV。
// 跨边界只传 base64 字符串，避免在 JS 侧操作 wasm 的线性内存。

const WASM_URL = "./moonvorbis.wasm";

const dropEl = document.getElementById("drop");
const fileEl = document.getElementById("file");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const playerEl = document.getElementById("player");
const metaEl = document.getElementById("meta");
const downloadEl = document.getElementById("download");

let decoder = null;
let lastUrl = null;

/// 加载并实例化 wasm 模块。
///
/// 解码器用 JS 字符串作为 MoonBit String，因此编译时需要开启 js-string
/// builtins，并把导入字符串常量的命名空间设成与 moon.pkg 一致的 "_"。
async function loadDecoder() {
  const response = await fetch(WASM_URL);
  if (!response.ok) {
    throw new Error(`无法读取 ${WASM_URL}（HTTP ${response.status}）`);
  }
  const bytes = await response.arrayBuffer();
  const module = await WebAssembly.compile(bytes, {
    builtins: ["js-string"],
    importedStringConstants: "_",
  });
  const instance = await WebAssembly.instantiate(module, {});
  return instance.exports;
}

function setStatus(text, isError) {
  statusEl.textContent = text;
  statusEl.classList.toggle("error", Boolean(isError));
}

function bytesToBase64(bytes) {
  const chunkSize = 0x8000;
  let binary = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/// 读取 WAV 头里的采样率、声道数与帧数，用于展示解码结果。
function readWavInfo(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const text = (offset) =>
    String.fromCharCode(
      bytes[offset],
      bytes[offset + 1],
      bytes[offset + 2],
      bytes[offset + 3],
    );
  if (bytes.length < 44 || text(0) !== "RIFF" || text(8) !== "WAVE") {
    return null;
  }
  const channels = view.getUint16(22, true);
  const sampleRate = view.getUint32(24, true);
  const bitsPerSample = view.getUint16(34, true);
  const dataSize = view.getUint32(40, true);
  const frames = dataSize / (channels * (bitsPerSample / 8));
  return { channels, sampleRate, frames };
}

async function decodeFile(file) {
  if (!decoder) {
    setStatus("解码器尚未就绪", true);
    return;
  }
  setStatus(`正在解码 ${file.name}…`);
  resultEl.classList.remove("show");

  const ogg = new Uint8Array(await file.arrayBuffer());
  const started = performance.now();
  let wavBase64;
  try {
    wavBase64 = decoder.decode_ogg_base64(bytesToBase64(ogg));
  } catch (err) {
    setStatus(`解码时出错：${err}`, true);
    return;
  }
  const elapsed = performance.now() - started;

  if (!wavBase64) {
    setStatus("解码失败：不是可识别的 OGG/Vorbis 数据", true);
    return;
  }

  const wav = base64ToBytes(wavBase64);
  if (lastUrl) {
    URL.revokeObjectURL(lastUrl);
  }
  lastUrl = URL.createObjectURL(new Blob([wav], { type: "audio/wav" }));
  playerEl.src = lastUrl;
  downloadEl.href = lastUrl;
  downloadEl.download = `${file.name.replace(/\.[^.]*$/, "")}.wav`;

  const info = readWavInfo(wav);
  metaEl.textContent = info
    ? `${info.sampleRate} Hz · ${info.channels} 声道 · ${info.frames} 帧 · ` +
      `WAV ${(wav.length / 1024).toFixed(1)} KB · 耗时 ${elapsed.toFixed(1)} ms`
    : `WAV ${(wav.length / 1024).toFixed(1)} KB · 耗时 ${elapsed.toFixed(1)} ms`;

  resultEl.classList.add("show");
  setStatus("解码完成");
}

dropEl.addEventListener("dragover", (event) => {
  event.preventDefault();
  dropEl.classList.add("hover");
});
dropEl.addEventListener("dragleave", () => dropEl.classList.remove("hover"));
dropEl.addEventListener("drop", (event) => {
  event.preventDefault();
  dropEl.classList.remove("hover");
  const file = event.dataTransfer.files[0];
  if (file) {
    decodeFile(file);
  }
});
fileEl.addEventListener("change", () => {
  const file = fileEl.files[0];
  if (file) {
    decodeFile(file);
  }
});

loadDecoder()
  .then((exports) => {
    decoder = exports;
    setStatus("解码器已就绪，请选择 .ogg 文件");
  })
  .catch((err) => {
    setStatus(
      `加载解码器失败：${err.message}。` +
        "请确认通过 HTTP 访问本页，且浏览器支持 WebAssembly JS String Builtins。",
      true,
    );
  });
