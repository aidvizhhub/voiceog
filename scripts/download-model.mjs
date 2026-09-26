// scripts/download-model.mjs — качает и распаковывает модель распознавания.
// Кроссплатформенно: без bash, без curl. Архив .tar.bz2 распаковываем тем, что
// есть в системе: tar (Win10+/Linux/macOS) → python → 7-Zip.
//
//   node scripts/download-model.mjs

import fs from 'node:fs';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const NAME = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8';
const URL = `https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${NAME}.tar.bz2`;

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const MODELS = path.join(ROOT, 'models');
const DIR = path.join(MODELS, NAME);
const ARCHIVE = path.join(MODELS, `${NAME}.tar.bz2`);

function log(...a) {
  console.log('[voiceog]', ...a);
}

function done() {
  return fs.existsSync(path.join(DIR, 'tokens.txt'));
}

async function download() {
  if (fs.existsSync(ARCHIVE) && fs.statSync(ARCHIVE).size > 1024 * 1024) {
    log('архив уже скачан:', ARCHIVE);
    return;
  }
  log(`качаю ${NAME} (~487 МБ)...`);
  const res = await fetch(URL, { redirect: 'follow' });
  if (!res.ok || !res.body) throw new Error(`HTTP ${res.status}`);

  const total = Number(res.headers.get('content-length') || 0);
  const out = fs.createWriteStream(ARCHIVE);
  let got = 0;
  let lastPct = -1;

  for await (const chunk of res.body) {
    got += chunk.length;
    if (!out.write(Buffer.from(chunk))) {
      await new Promise((r) => out.once('drain', r));
    }
    if (total) {
      const pct = Math.floor((got / total) * 100);
      if (pct !== lastPct && pct % 5 === 0) {
        process.stdout.write(`\r[voiceog] ${pct}%  (${(got / 1048576).toFixed(0)}/${(total / 1048576).toFixed(0)} МБ)`);
        lastPct = pct;
      }
    }
  }
  await new Promise((r) => out.end(r));
  process.stdout.write('\n');
}

function run(cmd, args) {
  const r = spawnSync(cmd, args, { stdio: 'inherit', windowsHide: true });
  if (r.error) throw r.error;
  if (r.status !== 0) throw new Error(`${cmd} завершился с кодом ${r.status}`);
}

function tryRun(cmd, args) {
  try {
    run(cmd, args);
    return true;
  } catch {
    return false;
  }
}

function extract() {
  fs.mkdirSync(MODELS, { recursive: true });
  log('распаковываю...');

  // 1) системный tar (bsdtar) — умеет bz2 в один проход
  if (tryRun('tar', ['-xjf', ARCHIVE, '-C', MODELS])) return;

  // 2) python (tarfile умеет bz2 без внешних утилит)
  const py = tryRun('python', [
    '-c',
    `import tarfile,sys; tarfile.open(sys.argv[1],'r:bz2').extractall(sys.argv[2])`,
    ARCHIVE,
    MODELS,
  ]);
  if (py) return;

  // 3) 7-Zip: сначала .bz2 → .tar, потом .tar → папка
  const tarFile = path.join(MODELS, `${NAME}.tar`);
  if (tryRun('7z', ['x', ARCHIVE, `-o${MODELS}`, '-y']) && tryRun('7z', ['x', tarFile, `-o${MODELS}`, '-y'])) {
    try { fs.rmSync(tarFile); } catch {}
    return;
  }

  throw new Error('не нашёл чем распаковать: нужен tar, python или 7z');
}

async function main() {
  if (done()) {
    log('модель уже на месте:', DIR);
    return;
  }
  if (!fs.existsSync(MODELS)) fs.mkdirSync(MODELS, { recursive: true });
  await download();
  extract();
  if (!done()) throw new Error(`распаковалось, но нет tokens.txt в ${DIR}`);
  log('готово:', DIR);
}

main().catch((e) => {
  console.error('[voiceog] ошибка:', e && e.message ? e.message : e);
  process.exit(1);
});
