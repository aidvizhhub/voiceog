// inject.mjs — вставить готовый текст в активное окно.
//
// Кириллицу «по клавишам» не набрать (раскладка), поэтому как все нормальные
// диктовки: кладём текст в буфер обмена и жмём Ctrl+V. Так вставится любой язык.
//
// Два независимых выбора, оба — по возможностям системы, а не по десктопу:
//   буфер — wl-copy (Wayland) | xclip или xsel (X11)
//   паста — ydotool | dotool | wtype (Wayland) | xdotool (X11)
//
// ydotool и dotool шлют нажатия через uinput, поэтому работают на ЛЮБОМ
// композиторе и на X11. wtype умеет печатать Unicode сам, но только на wlroots
// (Sway/Hyprland/River/Niri) — GNOME и KDE этот протокол не реализуют.
//
// Если буфера нет, но есть wtype — печатаем текст напрямую, без Ctrl+V.

import { execFile, spawn } from 'node:child_process';
import { existsSync } from 'node:fs';
import { which, session } from './detect.mjs';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

// ydotool сам ищет сокет в $XDG_RUNTIME_DIR, но если не нашёл — подскажем.
// Никаких захардкоженных UID: это и ломало «другой Linux».
function hintYdotoolSocket() {
  if (process.env.YDOTOOL_SOCKET) return;
  const rt = process.env.XDG_RUNTIME_DIR;
  const found = [rt && `${rt}/.ydotool_socket`, '/tmp/.ydotool_socket'].find(
    (p) => p && existsSync(p),
  );
  if (found) process.env.YDOTOOL_SOCKET = found;
}
hintYdotoolSocket();

// --- что кладём в буфер ---
const BUFFERS = {
  wayland: [{ name: 'wl-copy', args: ['--type', 'text/plain'] }],
  x11: [
    { name: 'xclip', args: ['-selection', 'clipboard', '-i'] },
    { name: 'xsel', args: ['-ib'] },
  ],
};

// --- чем жмём Ctrl+V ---
const YDOTOOL_PASTE = ['key', '29:1', '47:1', '47:0', '29:0'];
const PASTES = {
  wayland: [
    { name: 'ydotool', run: () => exec('ydotool', YDOTOOL_PASTE) },
    { name: 'dotool', run: () => exec('dotool', [], 'key ctrl+v\n') },
    // wtype: -M нажать модификатор, -k нажать+отпустить клавишу, -m отпустить
    { name: 'wtype', run: () => exec('wtype', ['-M', 'ctrl', '-k', 'v', '-m', 'ctrl']) },
  ],
  x11: [
    { name: 'xdotool', run: () => exec('xdotool', ['key', '--clearmodifiers', 'ctrl+v']) },
    { name: 'ydotool', run: () => exec('ydotool', YDOTOOL_PASTE) },
    { name: 'dotool', run: () => exec('dotool', [], 'key ctrl+v\n') },
  ],
};

function pickBuffer(s) {
  return (BUFFERS[s] || []).find((b) => which(b.name)) || null;
}

function pickPaste(s) {
  return (PASTES[s] || []).find((p) => which(p.name)) || null;
}

// Прямой набор (только wlroots + wtype): буфера нет, а текст вставить надо.
function canTypeDirect(s) {
  return s === 'wayland' && !pickBuffer(s) && !!which('wtype');
}

export function injectionStatus() {
  const s = session();
  const buffer = pickBuffer(s);
  const paste = pickPaste(s);
  const direct = canTypeDirect(s);

  const ready = direct || (!!buffer && !!paste);
  const missing = [];
  if (!ready) {
    if (!buffer && !direct) missing.push(s === 'x11' ? 'xclip' : 'wl-copy');
    if (!paste && !direct) missing.push('ydotool');
  }

  return {
    ready,
    session: s,
    buffer: buffer ? buffer.name : null,
    paste: paste ? paste.name : null,
    direct,
    backend: direct
      ? 'wtype (набор)'
      : buffer && paste
        ? `${buffer.name} + ${paste.name}`
        : null,
    missing,
  };
}

// Человекочитаемое имя пути вставки — для логов и морды.
export const injectionBackend = injectionStatus().backend || 'не готова';

function exec(cmd, args, input) {
  return new Promise((resolve, reject) => {
    const p = execFile(cmd, args, (err) => (err ? reject(err) : resolve()));
    if (input != null) p.stdin.end(input);
  });
}

// wl-copy/xclip уходят в фон держать буфер — не ждём их завершения.
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
  const s = session();
  const buffer = pickBuffer(s);
  const paste = pickPaste(s);
  const st = injectionStatus();

  if (st.direct) {
    await exec('wtype', ['-d', '2', '-'], text);
    return { ok: true, via: 'wtype (набор)' };
  }

  if (!buffer || !paste) {
    return { ok: false, reason: `нет: ${st.missing.join(', ') || 'инструментов вставки'}` };
  }

  await spawnDetached(buffer.name, buffer.args, text);
  await sleep(150);
  await paste.run();
  return { ok: true, via: st.backend };
}
