// server.mjs — крошечный локальный сервер VOICEog.
// Отдаёт страницу с кнопкой, /transcribe для браузера и /toggle для глобального
// хоткея (запись идёт на стороне демона, готовый текст вставляется в активное окно).
// Слушает только 127.0.0.1 — наружу не торчит.

import http from 'node:http';
import fs from 'node:fs';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import {
  createRecognizer,
  transcribePcm16,
  transcribeWav,
  transcribeSamples,
  pcm16ToFloat32,
  modelInfo,
} from './stt.mjs';
import { loadSettings, saveSettings } from './settings.mjs';
import { isValidCombo } from './keys.mjs';
// Вся ОС-специфика — за фасадом: Linux (pw-record/wl-copy/evdev) или Windows
// (ffmpeg/Set-Clipboard/uiohook). Ядро про платформу не знает.
import {
  Recorder,
  listAudioDevices,
  injectText,
  injectionStatus,
  HotkeyListener,
  setFallbackBinding,
  disableFallbackBinding,
  hotkeyBackend,
  injectionBackend,
  recordingBackend,
} from './platform/index.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const ROOT = path.resolve(__dirname, '..');
const INDEX = path.join(ROOT, 'public', 'index.html');

const PORT = Number(process.env.VOICEOG_PORT || 7777);
const HOST = process.env.VOICEOG_HOST || '127.0.0.1';
const MAX_BODY = 64 * 1024 * 1024; // 64 МБ аудио — с запасом

const info = modelInfo();
if (!info.ok) {
  console.error(`[voiceog] модель не готова: ${info.dir}`);
  console.error(`[voiceog] нет файлов: ${info.missing.join(', ')}`);
  console.error('[voiceog] скачай модель: npm run model');
  process.exit(1);
}

console.log(`[voiceog] гружу модель ${info.name} ...`);
const t0 = Date.now();
const recognizer = createRecognizer();
console.log(`[voiceog] модель готова за ${((Date.now() - t0) / 1000).toFixed(1)} с`);

const inject = injectionStatus();
console.log(
  `[voiceog] вставка в окно: ${inject.ready ? 'ok (' + injectionBackend + ')' : 'НЕ готова — нет ' + (inject.missing || []).join(', ')}`,
);
console.log(`[voiceog] платформа: ${recordingBackend} + ${hotkeyBackend}`);

const recorder = new Recorder();
const NO_INJECT = process.env.VOICEOG_NO_INJECT === '1';

// --- настройки и активация (хоткей) ---

let settings = loadSettings();
recorder.setDevice(settings.audioDevice);
let hotkey = null; // evdev-слушатель
let evdevAvailable = false;

async function startRecording() {
  if (recorder.recording) return { recording: true, already: true };
  await recorder.start();
  return { recording: true };
}

async function stopAndTranscribe() {
  const t = Date.now();
  const buf = await recorder.stop();
  const text = transcribeBuffer(buf);
  const ms = Date.now() - t;

  let injected = null;
  if (text && !NO_INJECT) injected = await injectText(text);
  if (text) {
    console.log(`[voiceog] → ${text}${injected && injected.ok ? '  [вставлено]' : ''}`);
  }
  return { recording: false, text, ms, injected };
}

async function toggleDictation() {
  return recorder.recording ? stopAndTranscribe() : startRecording();
}

// Что делает хоткей — зависит от режима: toggle дёргает тумблер, hold пишет, пока держишь.
function onHotkeyDown() {
  if (settings.mode === 'hold') return startRecording();
  return toggleDictation();
}

async function onHotkeyUp() {
  if (settings.mode === 'hold' && recorder.recording) await stopAndTranscribe();
}

function startHotkey() {
  if (hotkey) hotkey.stop();
  hotkey = new HotkeyListener({
    hotkey: settings.hotkey,
    onDown: onHotkeyDown,
    onUp: onHotkeyUp,
  });
  evdevAvailable = hotkey.start();
  return evdevAvailable;
}

// Запасной хоткей средствами ОС (GNOME на Linux; на Windows — no-op). Если наш
// собственный слушатель работает, гасим запасной, чтоб не дублировалось.
async function applyFallbackBinding() {
  try {
    if (evdevAvailable) {
      await disableFallbackBinding();
    } else if (settings.mode === 'toggle') {
      await setFallbackBinding(settings.hotkey);
    } else {
      // hold без собственного слушателя невозможен — не оставляем «залипшую» запись
      await disableFallbackBinding();
    }
  } catch (e) {
    console.log(`[voiceog] запасной хоткей: ${e && e.message}`);
  }
}

function settingsState() {
  return {
    hotkey: settings.hotkey,
    mode: settings.mode,
    theme: settings.theme,
    hotkeyActive: evdevAvailable,
    backend: hotkeyBackend,
    audioDevice: settings.audioDevice,
    devices: hotkey ? hotkey.devices : [],
  };
}

function json(res, code, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(code, {
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    req.on('data', (c) => {
      size += c.length;
      if (size > MAX_BODY) {
        reject(new Error('аудио слишком большое'));
        req.destroy();
        return;
      }
      chunks.push(c);
    });
    req.on('end', () => resolve(Buffer.concat(chunks)));
    req.on('error', reject);
  });
}

// WAV или сырой PCM 16 кГц — разбираем по факту.
function transcribeBuffer(buf) {
  if (!buf || buf.length < 4) return '';
  const isWav = buf.toString('latin1', 0, 4) === 'RIFF';
  return isWav ? transcribeWav(recognizer, buf) : transcribePcm16(recognizer, buf);
}

// --- Whisper-совместимый вход (для Telegram-бота и прочих клиентов) ---

// Минимальный разбор multipart/form-data: достаём первый файл-парт.
function firstFilePart(buf, contentType) {
  const m = /boundary=(?:"([^"]+)"|([^;]+))/i.exec(contentType || '');
  const boundary = m ? (m[1] || m[2]).trim() : null;
  if (!boundary) return null;

  const sep = Buffer.from(`--${boundary}`);
  let start = buf.indexOf(sep);
  while (start !== -1) {
    const next = buf.indexOf(sep, start + sep.length);
    if (next === -1) break;
    let part = buf.subarray(start + sep.length, next);
    if (part[0] === 13 && part[1] === 10) part = part.subarray(2); // срезаем CRLF
    const headerEnd = part.indexOf('\r\n\r\n');
    if (headerEnd !== -1) {
      const headers = part.subarray(0, headerEnd).toString('latin1');
      if (/filename=/i.test(headers)) {
        let body = part.subarray(headerEnd + 4);
        if (body.length >= 2 && body[body.length - 2] === 13 && body[body.length - 1] === 10) {
          body = body.subarray(0, body.length - 2);
        }
        return body;
      }
    }
    start = next;
  }
  return null;
}

// Любой аудиоформат (ogg/opus/mp3/m4a/…) → PCM s16le 16 кГц моно через ffmpeg.
function toPcm16k(buf) {
  return new Promise((resolve, reject) => {
    const p = spawn(
      'ffmpeg',
      ['-hide_banner', '-loglevel', 'error', '-i', 'pipe:0', '-f', 's16le', '-ac', '1', '-ar', '16000', 'pipe:1'],
      { stdio: ['pipe', 'pipe', 'pipe'] },
    );
    const out = [];
    const err = [];
    p.stdout.on('data', (d) => out.push(d));
    p.stderr.on('data', (d) => err.push(d));
    p.on('error', reject);
    p.on('close', (code) =>
      code === 0
        ? resolve(Buffer.concat(out))
        : reject(new Error('ffmpeg: ' + Buffer.concat(err).toString().slice(0, 200))),
    );
    p.stdin.end(buf);
  });
}

// Любой вход → текст. Контейнеры гоняем через ffmpeg, иначе считаем сырым PCM 16k.
async function transcribeAny(buf) {
  if (buf.toString('latin1', 0, 4) === 'RIFF') return transcribeWav(recognizer, buf);
  try {
    const pcm = await toPcm16k(buf);
    return transcribeSamples(recognizer, pcm16ToFloat32(pcm));
  } catch {
    return transcribePcm16(recognizer, buf);
  }
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, `http://${HOST}`);

  try {
    if (req.method === 'GET' && (url.pathname === '/' || url.pathname === '/index.html')) {
      const html = fs.readFileSync(INDEX);
      res.writeHead(200, {
        'Content-Type': 'text/html; charset=utf-8',
        'Cache-Control': 'no-store',
      });
      res.end(html);
      return;
    }

    if (req.method === 'GET' && url.pathname === '/health') {
      json(res, 200, { ok: true, model: info.name });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/state') {
      json(res, 200, {
        recording: recorder.recording,
        inject: injectionStatus(),
        model: info.name,
        ...settingsState(),
      });
      return;
    }

    if (req.method === 'GET' && url.pathname === '/api/settings') {
      json(res, 200, settingsState());
      return;
    }

    // Список микрофонов (Windows) — для выбора в морде.
    if (req.method === 'GET' && url.pathname === '/api/devices') {
      json(res, 200, { devices: await listAudioDevices(), current: recorder.device || settings.audioDevice || '' });
      return;
    }

    if (req.method === 'POST' && url.pathname === '/api/settings') {
      const body = await readBody(req);
      let patch = {};
      try {
        patch = JSON.parse(body.toString('utf8') || '{}');
      } catch {
        /* мусор — оставим как есть */
      }
      // битые значения не принимаем, чтоб не сбросить текущие
      if (patch.hotkey != null && !isValidCombo(patch.hotkey)) delete patch.hotkey;
      if (patch.mode != null && patch.mode !== 'toggle' && patch.mode !== 'hold') delete patch.mode;
      if (patch.theme != null && !['auto', 'dark', 'light'].includes(patch.theme)) delete patch.theme;
      if (patch.audioDevice != null && typeof patch.audioDevice !== 'string') delete patch.audioDevice;
      const next = saveSettings({ ...settings, ...patch });
      const hotkeyChanged = next.hotkey !== settings.hotkey;
      const modeChanged = next.mode !== settings.mode;
      settings = next;
      recorder.setDevice(settings.audioDevice);
      if (hotkeyChanged) startHotkey();
      if (hotkeyChanged || modeChanged) await applyFallbackBinding();
      json(res, 200, settingsState());
      return;
    }

    // Глобальный хоткей: первый вызов — старт записи, второй — стоп + расшифровка + вставка.
    if (req.method === 'POST' && url.pathname === '/toggle') {
      json(res, 200, await toggleDictation());
      return;
    }

    // Whisper-совместимо: POST /v1/audio/transcriptions (multipart) → {"text": "..."}
    // Сюда смотрит Telegram-бот (STT_API_URL) — и голосовые распознаёт наш Parakeet.
    if (req.method === 'POST' && url.pathname === '/v1/audio/transcriptions') {
      const raw = await readBody(req);
      const ct = req.headers['content-type'] || '';
      let data = raw;
      if (/multipart\/form-data/i.test(ct)) {
        const part = firstFilePart(raw, ct);
        if (part) data = part;
      }
      if (!data || data.length < 4) {
        json(res, 400, { error: 'нет аудио' });
        return;
      }
      const t = Date.now();
      const text = await transcribeAny(data);
      json(res, 200, { text, ms: Date.now() - t });
      return;
    }

    // Браузерный путь: готовый PCM/WAV прислали сюда.
    if (req.method === 'POST' && url.pathname === '/transcribe') {
      const body = await readBody(req);
      if (!body || body.length < 4) {
        json(res, 400, { error: 'пустое аудио' });
        return;
      }
      const t = Date.now();
      const isWav = body.toString('latin1', 0, 4) === 'RIFF';
      const text = transcribeBuffer(body);
      json(res, 200, { text, ms: Date.now() - t, format: isWav ? 'wav' : 'pcm16' });
      return;
    }

    json(res, 404, { error: 'не найдено' });
  } catch (e) {
    json(res, 500, { error: String(e && e.message ? e.message : e) });
  }
});

server.listen(PORT, HOST, () => {
  console.log(`[voiceog] слушаю http://${HOST}:${PORT}`);
  console.log('[voiceog] браузер — кнопка; хоткей — «voiceog toggle»');

  startHotkey();
  applyFallbackBinding();
});
