// demo/record.js
//
// 演示录制页：把 index.html 的完整流程排成一条时间线，用 `?t=<毫秒>` 选中
// 其中某一刻的画面，供截图脚本逐帧抓取、合成 GIF。
//
// 解码本身是真的：页面确实加载 moonvorbis.wasm、确实解了 demo/sample.ogg，
// 波形和元信息都来自解码结果。`t` 只决定把流程画到哪一步，不改动任何数据。

import {
  loadDecoder,
  readPcmChannels,
  readWavInfo,
  fnv1a,
  decodeOgg,
} from "./decoder.js";

const SAMPLE_URL = "./sample.ogg";

// 时间线（毫秒）。各段的边界即取帧脚本要覆盖的时刻。
// 加载与就绪两段是静止画面，压得短些——成片里它们会合并成一帧。
const T_READY = 1500; // 解码器加载完成
const T_DECODING = 2600; // 文件被选中，开始解码
const T_DONE = 3800; // 解码完成，出结果
const T_SWEEP_START = 4100; // 播放头开始扫
const T_SWEEP_END = 8300; // 播放头扫到末尾

const params = new URLSearchParams(location.search);
const t = Number(params.get("t") ?? "0") || 0;

const dropEl = document.getElementById("drop");
const dropTitleEl = document.getElementById("dropTitle");
const dropHintEl = document.getElementById("dropHint");
const statusEl = document.getElementById("status");
const barEl = document.getElementById("bar");
const barInnerEl = barEl.querySelector("span");
const resultEl = document.getElementById("result");
const canvasEl = document.getElementById("wave");
const metaEl = document.getElementById("meta");

const rootStyle = getComputedStyle(document.documentElement);
const accent = rootStyle.getPropertyValue("--accent").trim() || "#2f6feb";
const muted = rootStyle.getPropertyValue("--muted").trim() || "#5b6472";

/// 把一条声道画成峰值包络：每个像素列取该列覆盖帧的最小/最大值。
function drawWave(channels, info, progress) {
  const ctx = canvasEl.getContext("2d");
  const width = canvasEl.width;
  const height = canvasEl.height;
  const mid = height / 2;
  const frames = channels[0].length;
  const columns = Math.floor(width / 2); // 每列 2 个内部像素，画出来更细腻

  ctx.clearRect(0, 0, width, height);
  ctx.lineWidth = 2;

  // 中轴线
  ctx.strokeStyle = muted;
  ctx.globalAlpha = 0.35;
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.moveTo(0, mid);
  ctx.lineTo(width, mid);
  ctx.stroke();

  const playheadX = Math.round(progress * width);

  for (let c = 0; c < channels.length; c += 1) {
    const data = channels[c];
    // 多声道时上下错开一点，避免两条曲线完全重叠
    const offset = channels.length > 1 ? (c - (channels.length - 1) / 2) * 10 : 0;
    for (let col = 0; col < columns; col += 1) {
      const from = Math.floor((col * frames) / columns);
      const to = Math.max(from + 1, Math.floor(((col + 1) * frames) / columns));
      let lo = 0;
      let hi = 0;
      for (let i = from; i < to; i += 1) {
        const v = data[i];
        if (v < lo) lo = v;
        if (v > hi) hi = v;
      }
      const x = col * 2;
      const yLo = mid + offset + lo * (mid * 0.88);
      const yHi = mid + offset + hi * (mid * 0.88);
      // 播放头左侧用实色，右侧减淡，一眼看出扫到哪
      ctx.strokeStyle = accent;
      ctx.globalAlpha = x <= playheadX ? 0.95 : 0.3;
      ctx.beginPath();
      ctx.moveTo(x, yHi);
      // 线段从 yHi 向上拉到 yLo；包络太薄时至少留 2 像素，否则整段会缩成
      // 一列小点，看上去像一条贴着中线下方走的细线
      ctx.lineTo(x, Math.min(yLo, yHi - 2));
      ctx.stroke();
    }
  }

  if (progress > 0) {
    ctx.globalAlpha = 1;
    ctx.strokeStyle = accent;
    ctx.lineWidth = 3;
    ctx.beginPath();
    ctx.moveTo(playheadX, 0);
    ctx.lineTo(playheadX, height);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
}

/// 按时间线把页面画成 `t` 时刻的样子。
function render(t, decoded) {
  dropEl.classList.remove("hover");
  barEl.classList.remove("show");
  resultEl.classList.remove("show");

  if (t < T_READY) {
    statusEl.textContent = "正在加载解码器…";
    return;
  }

  if (t < T_DECODING) {
    statusEl.textContent = "解码器已就绪，请选择 .ogg 文件";
    return;
  }

  // 文件已选中：drop 区显示文件名并高亮
  dropEl.classList.add("hover");
  dropTitleEl.textContent = "sample.ogg";
  dropHintEl.textContent = "2 声道 · 44.1 kHz · 来自仓库自带的示例素材";

  // 解码还没跑完时，即使 t 已经走到结果段也只能画解码中——数据是真的，
  // 不能因为时间线到了就把空结果画出去。
  if (t < T_DONE || !decoded) {
    statusEl.textContent = "正在解码 sample.ogg…";
    barEl.classList.add("show");
    const pct = Math.min(
      100,
      ((t - T_DECODING) / (T_DONE - T_DECODING)) * 100,
    );
    barInnerEl.style.width = `${pct}%`;
    return;
  }

  // 解码已完成：显示真实结果
  statusEl.textContent = "解码完成";
  resultEl.classList.add("show");
  metaEl.textContent = decoded.meta;

  const progress =
    t < T_SWEEP_START
      ? 0
      : Math.min(1, (t - T_SWEEP_START) / (T_SWEEP_END - T_SWEEP_START));
  drawWave(decoded.channels, decoded.info, progress);
}

/// 走一遍真实路径：加载 wasm → 取回 sample.ogg → 解码 → 解析 PCM。
async function main() {
  // 先按时间线画一次，让早于解码完成的帧也能取到
  render(t, null);

  const decoder = await loadDecoder();
  const response = await fetch(SAMPLE_URL);
  const ogg = new Uint8Array(await response.arrayBuffer());
  const started = performance.now();
  const wav = decodeOgg(decoder, ogg);
  const elapsed = performance.now() - started;

  const info = readWavInfo(wav);
  const channels = readPcmChannels(wav);
  const checksum = fnv1a(wav);

  const decoded = {
    info,
    channels,
    meta:
      `${info.sampleRate} Hz · ${info.channels} 声道 · ${info.frames} 帧 · ` +
      `WAV ${(wav.length / 1024).toFixed(1)} KB · 耗时 ${elapsed.toFixed(1)} ms · ` +
      `FNV ${checksum}`,
  };

  render(t, decoded);
  // 截图脚本据此判断这一帧已经画好
  document.title = `READY t=${t}`;
}

main().catch((err) => {
  statusEl.textContent = `加载失败：${err.message}`;
  document.title = "ERROR";
});
