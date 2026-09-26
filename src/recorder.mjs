// recorder.mjs — запись с микрофона на стороне демона.
// Нужна для глобального хоткея: браузер тут не участвует.
// Пишем через pw-record (PipeWire) в сырой PCM 16 кГц моно.

import { spawn } from 'node:child_process';

const REC = process.env.VOICEOG_RECORDER || 'pw-record';
const ARGS = ['--format=s16', '--rate=16000', '--channels=1', '-'];

export class Recorder {
  constructor() {
    this.proc = null;
    this.chunks = [];
  }

  get recording() {
    return this.proc !== null;
  }

  start() {
    if (this.proc) return false;
    this.chunks = [];
    const proc = spawn(REC, ARGS, { stdio: ['ignore', 'pipe', 'ignore'] });
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
        proc.kill('SIGINT');
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
