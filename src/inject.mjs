// inject.mjs — вставка текста в активное окно на GNOME/Wayland.
//
// Тонкость: набрать кириллицу по клавишам через ydotool нельзя (раскладка).
// Поэтому кладём текст в буфер обмена (wl-copy) и жмём Ctrl+V (ydotool).
// Так вставляется что угодно, в любом языке.

import { execFile, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';

function which(cmd) {
  for (const dir of (process.env.PATH || '').split(':')) {
    if (dir && existsSync(`${dir}/${cmd}`)) return `${dir}/${cmd}`;
  }
  return null;
}

export function injectionStatus() {
  return {
    ydotool: !!which('ydotool'),
    wlCopy: !!which('wl-copy'),
    ready: !!which('ydotool') && !!which('wl-copy'),
  };
}

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ydotool keycodes: LEFTCTRL=29, V=47. Формат нажатий: код:1 (вниз), код:0 (вверх).
const PASTE = ['key', '29:1', '47:1', '47:0', '29:0'];

function exec(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const p = execFile(cmd, args, (err) => (err ? reject(err) : resolve()));
    if (input != null) p.stdin.end(input);
  });
}

// wl-copy уходит в фон обслуживать буфер и может не завершиться — не ждём его.
function spawnDetached(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const p = spawn(cmd, args, { stdio: ['pipe', 'ignore', 'ignore'], detached: true });
    p.on('error', reject);
    if (input != null) p.stdin.end(input);
    p.unref();
    setTimeout(resolve, 200);
  });
}

export async function injectText(text) {
  const st = injectionStatus();
  if (!st.ready) {
    const missing = [!st.wlCopy && 'wl-copy', !st.ydotool && 'ydotool'].filter(Boolean).join(', ');
    return { ok: false, reason: `нет: ${missing}` };
  }

  await spawnDetached('wl-copy', ['--type', 'text/plain'], text);
  await sleep(120);
  await exec('ydotool', PASTE);
  return { ok: true };
}
