// stt.mjs — обёртка над sherpa-onnx для локального распознавания речи.
// Модель: NVIDIA Parakeet TDT 0.6B v3 (INT8, ONNX) → 25 европейских языков,
// русский и украинский включены. Никакого облака, всё на машине.

import { createRequire } from 'node:module';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const require = createRequire(import.meta.url);
const sherpa = require('sherpa-onnx-node');

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');

const MODEL_NAME = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8';

export const MODEL_DIR =
  process.env.VOICEOG_MODEL || path.join(ROOT, 'models', MODEL_NAME);

const FILES = {
  encoder: 'encoder.int8.onnx',
  decoder: 'decoder.int8.onnx',
  joiner: 'joiner.int8.onnx',
  tokens: 'tokens.txt',
};

// Чего не хватает в папке модели (для честной диагностики).
export function modelInfo() {
  const missing = [];
  for (const f of Object.values(FILES)) {
    if (!fs.existsSync(path.join(MODEL_DIR, f))) missing.push(f);
  }
  return {
    dir: MODEL_DIR,
    name: path.basename(MODEL_DIR),
    ok: missing.length === 0,
    missing,
  };
}

export function createRecognizer() {
  const info = modelInfo();
  if (!info.ok) {
    throw new Error(
      `Модель не готова: ${MODEL_DIR}\n` +
        `нет файлов: ${info.missing.join(', ')}\n` +
        `Скачай: npm run model`,
    );
  }

  const config = {
    featConfig: { sampleRate: 16000, featureDim: 80 },
    modelConfig: {
      transducer: {
        encoder: path.join(MODEL_DIR, FILES.encoder),
        decoder: path.join(MODEL_DIR, FILES.decoder),
        joiner: path.join(MODEL_DIR, FILES.joiner),
      },
      tokens: path.join(MODEL_DIR, FILES.tokens),
      numThreads: Number(process.env.VOICEOG_THREADS || 4),
      provider: 'cpu',
      debug: 0,
      modelType: 'nemo_transducer',
    },
  };

  return new sherpa.OfflineRecognizer(config);
}

// Int16LE PCM → Float32 [-1, 1]
export function pcm16ToFloat32(buf) {
  const n = Math.floor(buf.length / 2);
  const out = new Float32Array(n);
  for (let i = 0; i < n; i++) {
    const s = buf.readInt16LE(i * 2);
    out[i] = s < 0 ? s / 32768 : s / 32767;
  }
  return out;
}

// WAV-байты → { samples, sampleRate }. Свой разбор: JS-обёртка sherpa
// readWaveFromBinary не отдаёт, а тащить временные файлы ради теста лень.
export function wavToSamples(buf) {
  if (
    buf.length < 44 ||
    buf.toString('latin1', 0, 4) !== 'RIFF' ||
    buf.toString('latin1', 8, 12) !== 'WAVE'
  ) {
    throw new Error('это не WAV');
  }

  let pos = 12;
  let fmt = null;
  let data = null;
  while (pos + 8 <= buf.length) {
    const id = buf.toString('latin1', pos, pos + 4);
    const size = buf.readUInt32LE(pos + 4);
    const body = pos + 8;
    if (id === 'fmt ') {
      fmt = {
        format: buf.readUInt16LE(body),
        channels: buf.readUInt16LE(body + 2),
        sampleRate: buf.readUInt32LE(body + 4),
        bits: buf.readUInt16LE(body + 14),
      };
    } else if (id === 'data') {
      data = buf.subarray(body, Math.min(body + size, buf.length));
    }
    pos = body + size + (size % 2);
  }

  if (!fmt || !data) throw new Error('WAV битый: нет fmt/data');

  const { format, channels, sampleRate, bits } = fmt;
  const bytesPerSample = bits / 8;
  const frameBytes = bytesPerSample * channels;
  const frames = Math.floor(data.length / frameBytes);
  const out = new Float32Array(frames);

  for (let i = 0; i < frames; i++) {
    const off = i * frameBytes; // берём левый канал, нам хватает
    if (format === 3 && bits === 32) out[i] = data.readFloatLE(off);
    else if (bits === 16) out[i] = data.readInt16LE(off) / 32768;
    else if (bits === 24) out[i] = data.readIntLE(off, 3) / 8388608;
    else if (bits === 32) out[i] = data.readInt32LE(off) / 2147483648;
    else if (bits === 8) out[i] = (data.readUInt8(off) - 128) / 128;
    else throw new Error(`не поддержал битность ${bits}, формат ${format}`);
  }

  return { samples: out, sampleRate };
}

// Меньше этого — движок падает в нативной Ort::Exception (0 фреймов после
// выделения признаков), поэтому обрубаем заранее. 150 мс при 16 кГц.
const MIN_SAMPLES = Math.round(16000 * 0.15);

export function transcribeSamples(recognizer, samples, sampleRate = 16000) {
  if (!samples || samples.length < MIN_SAMPLES) return '';

  const stream = recognizer.createStream();
  stream.acceptWaveform({ sampleRate, samples });
  recognizer.decode(stream);
  const { text } = recognizer.getResult(stream);
  return (text || '').trim();
}

// Прямо из сырого PCM 16 кГц моно (то, что шлёт браузер).
export function transcribePcm16(recognizer, buf, sampleRate = 16000) {
  return transcribeSamples(recognizer, pcm16ToFloat32(buf), sampleRate);
}

// Из готового WAV-файла/буфера (удобно для тестов).
export function transcribeWav(recognizer, buf) {
  const wave = wavToSamples(buf);
  return transcribeSamples(recognizer, wave.samples, wave.sampleRate);
}
