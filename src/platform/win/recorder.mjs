// platform/win/recorder.mjs — запись с микрофона на Windows через ffmpeg (dshow).
//
// ffmpeg кладёт сырой PCM 16 кГц моно на stdout — ровно тот формат, что ждёт
// распознаватель.
//
// Устройство выбирается так:
//   1) VOICEOG_AUDIO_DEVICE (переменная окружения) — силой;
//   2) устройство из настроек (выбор в морде);
//   3) авто: перебираем аудио-устройства и берём то, где есть реальный сигнал
//      (иначе легко нарваться на «мёртвый» микрофон и писать тишину);
//   4) если сигнала нет нигде — первое из списка.

import { spawn } from 'node:child_process';
import ffmpegStatic from 'ffmpeg-static';

const FFMPEG = process.env.VOICEOG_FFMPEG || ffmpegStatic || 'ffmpeg';
const FIXED_DEVICE = process.env.VOICEOG_AUDIO_DEVICE || null;

const SAMPLE_RATE = 16000;
const CHANNELS = 1;
const BYTES_PER_SAMPLE = 2;

let cachedDevice;

// Список аудио-устройств DirectShow через ffmpeg. Новые сборки помечают тип в
// строке — «Имя» (audio); старые печатают секцию «DirectShow audio devices».
// Альтернативные имена (@device_…) пропускаем.
export function listAudioDevices() {
  return new Promise((resolve) => {
    let proc;
    try {
      proc = spawn(
        FFMPEG,
        ['-hide_banner', '-list_devices', 'true', '-f', 'dshow', '-i', 'dummy'],
        { stdio: ['ignore', 'ignore', 'pipe'], windowsHide: true },
      );
    } catch {
      resolve([]);
      return;
    }
    let err = '';
    proc.stderr.on('data', (d) => (err += d.toString('utf8')));
    proc.on('error', () => resolve([]));
    proc.on('close', () => {
      const devs = [];
      let inAudio = false;
      for (const line of err.split(/\r?\n/)) {
        const typed = /"([^"]+)"\s*\((audio|video|none)\)\s*$/i.exec(line);
        if (typed) {
          if (typed[2].toLowerCase() === 'audio') devs.push(typed[1]);
          continue;
        }
        if (/DirectShow audio devices/i.test(line)) {
          inAudio = true;
          continue;
        }
        if (/DirectShow video devices/i.test(line)) {
          inAudio = false;
          continue;
        }
        if (!inAudio) continue;
        const m = /"([^"]+)"/.exec(line);
        if (m && !m[1].startsWith('@')) devs.push(m[1]);
      }
      resolve([...new Set(devs)]);
    });
  });
}

function recordArgs(device) {
  return [
    '-hide_banner', '-loglevel', 'error',
    '-f', 'dshow',
    '-audio_buffer_size', '50',
    '-i', `audio=${device}`,
    '-f', 's16le',
    '-acodec', 'pcm_s16le',
    '-ac', String(CHANNELS),
    '-ar', String(SAMPLE_RATE),
    '-',
  ];
}

function rms(buf) {
  const n = Math.floor(buf.length / BYTES_PER_SAMPLE);
  if (!n) return 0;
  let sum = 0;
  for (let i = 0; i < n; i++) {
    const s = buf.readInt16LE(i * BYTES_PER_SAMPLE);
    sum += s * s;
  }
  return Math.sqrt(sum / n);
}

// Короткая проба устройства: пишем ms миллисекунд и меряем уровень.
// Первые ~40% отбрасываем — это прогрев dshow, там часто пусто/шум. 800мс мало:
// «медленное» устройство не успевает разогреться и получает заниженный балл.
function probeDevice(device, ms = 1300) {
  return new Promise((resolve) => {
    let proc;
    try {
      proc = spawn(FFMPEG, recordArgs(device), { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true });
    } catch {
      resolve(0);
      return;
    }
    const chunks = [];
    proc.stdout.on('data', (d) => chunks.push(d));
    proc.on('error', () => resolve(0));
    const kill = () => {
      try {
        proc.kill();
      } catch {
        /* пусто */
      }
    };
    setTimeout(kill, ms);
    proc.on('close', () => {
      const b = Buffer.concat(chunks);
      const warm = Math.floor((b.length * 0.4) / BYTES_PER_SAMPLE) * BYTES_PER_SAMPLE;
      resolve(rms(b.subarray(warm)));
    });
  });
}

// Порог «есть звук»: тишина даёт ~0–1, живой микрофон — сотни.
const SIGNAL_RMS = 50;

async function resolveDevice(requested) {
  if (FIXED_DEVICE) return FIXED_DEVICE;
  if (requested) return requested;
  if (cachedDevice) return cachedDevice;

  const devs = await listAudioDevices();
  if (!devs.length) return null;

  let best = null;
  let bestRms = -1;
  for (const d of devs) {
    const level = await probeDevice(d);
    if (level > bestRms) {
      bestRms = level;
      best = d;
    }
    await new Promise((r) => setTimeout(r, 150)); // дать устройству «остыть» между пробами
  }
  cachedDevice = bestRms >= SIGNAL_RMS ? best : devs[0];
  return cachedDevice;
}

export class Recorder {
  constructor(device = null) {
    this.proc = null;
    this.chunks = [];
    this.device = null;
    this.requested = device || null;
  }

  // Сменить выбранное устройство (из настроек). Пусто — снова авто-выбор.
  setDevice(name) {
    this.requested = name || null;
    cachedDevice = undefined;
  }

  get recording() {
    return this.proc !== null;
  }

  async start() {
    if (this.proc) return false;

    const device = await resolveDevice(this.requested);
    if (!device) return false; // нет микрофона — старт не состоялся

    this.chunks = [];
    this.device = device;
    const proc = spawn(FFMPEG, recordArgs(device), {
      stdio: ['ignore', 'pipe', 'ignore'],
      windowsHide: true,
    });

    this.proc = proc;
    proc.stdout.on('data', (d) => this.chunks.push(d));
    proc.on('error', () => {
      if (this.proc === proc) this.proc = null;
    });
    proc.on('close', () => {
      if (this.proc === proc) this.proc = null;
    });
    return true;
  }

  // Останавливает запись и отдаёт весь накопленный PCM.
  stop() {
    return new Promise((resolve) => {
      const proc = this.proc;
      if (!proc) {
        resolve(Buffer.alloc(0));
        return;
      }
      this.proc = null;

      let settled = false;
      const done = () => {
        if (settled) return;
        settled = true;
        resolve(Buffer.concat(this.chunks));
      };

      proc.once('close', done);
      try {
        proc.kill();
      } catch {
        /* уже мёртв */
      }
      setTimeout(() => {
        try {
          proc.kill('SIGKILL');
        } catch {
          /* пусто */
        }
      }, 700);
      setTimeout(done, 1200);
    });
  }
}
