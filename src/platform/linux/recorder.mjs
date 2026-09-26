// recorder.mjs — запись микрофона.
//
// Не привязан к PipeWire: пробуем по очереди и берём первый, что есть.
//   pw-record — родной PipeWire
//   parec     — PulseAudio; а PipeWire прикидывается Pulse (pipewire-pulse),
//               поэтому parec кроет и его тоже — самый универсальный
//   arecord   — чистый ALSA, когда звукового сервера нет вовсе
//   ffmpeg    — на крайний случай, читает pulse
//
// Все пишут сырой PCM s16le 16 кГц моно в stdout — движку распознавания
// больше ничего и не нужно.

import { spawn, execFile } from 'node:child_process';
import { which } from './detect.mjs';

// Каждый вариант знает, как проверить себя и как собрать аргументы.
// device — необязательный выбор микрофона из настроек.
const CHAIN = [
  {
    name: 'pw-record',
    has: () => !!which('pw-record'),
    args: (device) => [
      '--format=s16', '--rate=16000', '--channels=1',
      ...(device ? ['--target', device] : []),
      '-',
    ],
  },
  {
    name: 'parec',
    has: () => !!which('parec'),
    args: (device) => [
      '--record', '--format=s16le', '--rate=16000', '--channels=1',
      ...(device ? ['--device', device] : []),
    ],
  },
  {
    name: 'arecord',
    has: () => !!which('arecord'),
    args: (device) => [
      '-t', 'raw', '-f', 'S16_LE', '-r', '16000', '-c', '1',
      ...(device ? ['-D', device] : []),
    ],
  },
  {
    name: 'ffmpeg',
    has: () => !!which('ffmpeg'),
    args: (device) => [
      '-hide_banner', '-loglevel', 'error',
      '-f', 'pulse', '-i', device || 'default',
      '-f', 's16le', '-ac', '1', '-ar', '16000', '-',
    ],
  },
];

// Если человек сам задал VOICEOG_RECORDER — уважаем и не умничаем.
// Голое имя (напр. VOICEOG_RECORDER=parec) берёт аргументы из цепочки;
// команда с аргументами используется как есть.
function fromEnv() {
  const cmd = process.env.VOICEOG_RECORDER;
  if (!cmd) return null;
  const [bin, ...rest] = cmd.split(/\s+/).filter(Boolean);
  if (rest.length) return { name: bin, args: () => rest };
  const known = CHAIN.find((b) => b.name === bin);
  return { name: bin, args: known ? known.args : () => [] };
}

export function pickRecorder() {
  return fromEnv() || CHAIN.find((b) => b.has()) || null;
}

export const recordingBackend = (pickRecorder() || { name: 'нет' }).name;

export class Recorder {
  constructor() {
    this.proc = null;
    this.chunks = [];
    this._device = '';
    this.backend = pickRecorder();
  }

  setDevice(device) {
    this._device = device || '';
  }

  get device() {
    return this._device;
  }

  get recording() {
    return this.proc !== null;
  }

  start() {
    if (this.proc) return false;
    if (!this.backend) return false;
    this.chunks = [];
    const proc = spawn(this.backend.name, this.backend.args(this.device), {
      stdio: ['ignore', 'pipe', 'ignore'],
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
  // SIGINT — чтобы утилита дописала хвост; SIGKILL — если не хочет умирать.
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
        proc.kill('SIGINT');
      } catch {
        // уже мёртв
      }
      setTimeout(() => {
        try {
          proc.kill('SIGKILL');
        } catch {
          // пусто
        }
      }, 700);
      setTimeout(done, 1200);
    });
  }
}

function run(cmd, args) {
  return new Promise((resolve) => {
    execFile(cmd, args, { maxBuffer: 4 * 1024 * 1024 }, (err, stdout) =>
      resolve(err ? '' : String(stdout)),
    );
  });
}

// Список микрофонов для морды. Возвращаем массив имён-строк.
// pactl понимает и PulseAudio, и PipeWire; arecord — запасной путь для ALSA.
export async function listAudioDevices() {
  if (which('pactl')) {
    const out = await run('pactl', ['list', 'short', 'sources']);
    const names = out
      .split('\n')
      .map((line) => line.split('\t')[1])
      .filter(Boolean)
      // .monitor — это запись системного звука, а не микрофон
      .filter((name) => !/\.monitor$/.test(name));
    if (names.length) return names;
  }
  if (which('arecord')) {
    const out = await run('arecord', ['-l']);
    return [...out.matchAll(/card (\d+):[^,]+\[[^\]]*\], device (\d+):/g)].map(
      (m) => `hw:${m[1]},${m[2]}`,
    );
  }
  return [];
}
