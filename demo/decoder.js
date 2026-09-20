// demo/decoder.js
//
// 浏览器侧的解码胶水：加载 moonvorbis.wasm，把 OGG 字节交给 MoonBit 解码，
// 再把返回的 WAV 解析成页面要用的信息。index.html 与 record.html 共用这一份。
//
// 跨边界只传 base64 字符串，避免在 JS 侧操作 wasm 的线性内存。

const WASM_URL = "./moonvorbis.wasm";

/// 加载并实例化 wasm 模块。
///
/// 解码器用 JS 字符串作为 MoonBit String，因此编译时需要开启 js-string
/// builtins，并把导入字符串常量的命名空间设成与 moon.pkg 一致的 "_"。
export async function loadDecoder() {
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

export function bytesToBase64(bytes) {
  const chunkSize = 0x8000;
  let binary = "";
  for (let i = 0; i < bytes.length; i += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(i, i + chunkSize));
  }
  return btoa(binary);
}

export function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}

/// 读取 WAV 头里的采样率、声道数与帧数，用于展示解码结果。
export function readWavInfo(bytes) {
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
  return { channels, sampleRate, frames, bitsPerSample };
}

/// 把 16-bit PCM 的 data 段按声道展开成归一化到 [-1, 1] 的采样数组。
///
/// 返回每个声道一条 Float32Array，画波形和算校验和都用它。
export function readPcmChannels(bytes) {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const info = readWavInfo(bytes);
  if (!info || info.bitsPerSample !== 16) {
    return null;
  }
  const blockAlign = info.channels * 2;
  const frames = Math.floor((bytes.length - 44) / blockAlign);
  const channels = [];
  for (let c = 0; c < info.channels; c += 1) {
    const data = new Float32Array(frames);
    for (let i = 0; i < frames; i += 1) {
      const offset = 44 + i * blockAlign + c * 2;
      data[i] = view.getInt16(offset, true) / 32768;
    }
    channels.push(data);
  }
  return channels;
}

/// WAV 字节的 FNV-1a 校验和，与 demo/headless-test.html 用的是同一个算法。
///
/// 必须用 Math.imul：普通乘法在 JS 里是 double，乘积超过 2^53 就会丢位。
export function fnv1a(bytes) {
  let hash = 0x811c9dc5;
  for (let i = 0; i < bytes.length; i += 1) {
    hash = Math.imul(hash ^ bytes[i], 0x01000193);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
}

/// 完整的解码流程：OGG 字节 → WAV 字节。失败时抛出带说明的 Error。
export function decodeOgg(decoder, oggBytes) {
  const base64 = decoder.decode_ogg_base64(bytesToBase64(oggBytes));
  if (!base64) {
    throw new Error("不是可识别的 OGG/Vorbis 数据");
  }
  return base64ToBytes(base64);
}
