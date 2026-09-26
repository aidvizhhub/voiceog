// platform/win/recorder.mjs — запись с микрофона на Windows через ffmpeg (dshow).
//
// ffmpeg кладёт сырой PCM 16 кГц моно на stdout — ровно тот формат, что ждёт
// распознаватель. Устройство определяем сами (первое аудио в списке dshow),
// если не задано VOICEOG_AUDIO_DEVICE.

import { spawn } from 'node:child_process';
import ffmpegStatic from 'ffmpeg-static';

const FFMPEG = process.env.VOICEOG_FFMPEG || ffmpegStatic || 'ffmpeg';
const FIXED_DEVICE = process.env.VOICEOG_AUDIO_DEVICE || null;

let cachedDevice;

// Список аудио-устройств DirectShow через ffmpeg. Новые сборки помечают тип в
// строке — «Имя» (audio); старые печатают секцию «DirectShow audio devices».
// Поддерживаем оба формата, альтернативные имена (@device_…) пропускаем.
function listAudioDevices() {
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
        // Новый ffmpeg: без заголовков, тип помечен в конце строки — "Имя" (audio).
        const typed = /"([^"]+)"\s*\((audio|video|none)\)\s*$/i.exec(line);
        if (typed) {
          if (typed[2].toLowerCase() === 'audio') devs.push(typed[1]);
          continue;
        }
        // Старый ffmpeg: секции с заголовками.
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
      // уникальные, в порядке появления
      resolve([...new Set(devs)]);
    });
  });
}

async function resolveDevice() {
  if (FIXED_DEVICE) return FIXED_DEVICE;
  if (cachedDevice) return cachedDevice;
  const devs = await listAudioDevices();
  cachedDevice = devs[0] || null;
  return cachedDevice;
}

export class Recorder {
  constructor() {
    this.proc = null;
    this.chunks = [];
    this.device = null;
  }

  get recording() {
    return this.proc !== null;
  }

  async start() {
    if (this.proc) return false;

    const device = await resolveDevice();
    if (!device) return false; // нет микрофона — старт не состоялся

    this.chunks = [];
    this.device = device;
    const proc = spawn(
      FFMPEG,
      [
        '-hide_banner', '-loglevel', 'error',
        '-f', 'dshow',
        '-audio_buffer_size', '50',
        '-i', `audio=${device}`,
        '-f', 's16le',
        '-acodec', 'pcm_s16le',
        '-ac', '1',
        '-ar', '16000',
        '-',
      ],
      { stdio: ['ignore', 'pipe', 'ignore'], windowsHide: true },
    );

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
