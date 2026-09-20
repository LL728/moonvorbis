// demo/main.js
//
// 浏览器演示：加载 moonvorbis.wasm，把 OGG 字节交给 MoonBit 解码，播放返回的 WAV。
// 解码胶水在 decoder.js 里，与 record.html 共用。

import {
  loadDecoder,
  readWavInfo,
  decodeOgg,
} from "./decoder.js";

const dropEl = document.getElementById("drop");
const fileEl = document.getElementById("file");
const statusEl = document.getElementById("status");
const resultEl = document.getElementById("result");
const playerEl = document.getElementById("player");
const metaEl = document.getElementById("meta");
const downloadEl = document.getElementById("download");

let decoder = null;
let lastUrl = null;

function setStatus(text, isError) {
  statusEl.textContent = text;
  statusEl.classList.toggle("error", Boolean(isError));
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
  let wav;
  try {
    wav = decodeOgg(decoder, ogg);
  } catch (err) {
    setStatus(`解码失败：${err.message}`, true);
    return;
  }
  const elapsed = performance.now() - started;

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
