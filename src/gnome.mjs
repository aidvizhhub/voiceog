// gnome.mjs — управление GNOME-биндингом из нашего кода.
//
// GNOME-хоткей нужен как запасной путь, когда evdev недоступен (нет прав на
// /dev/input). Когда evdev работает — GNOME-биндинг отключаем, иначе будет
// двойное срабатывание.

import path from 'node:path';
import { execFile } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { toGnomeBinding } from './keys.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const COMMAND = `${ROOT}/voiceog toggle`;

const SCHEMA = 'org.gnome.settings-daemon.plugins.media-keys';
const KEY = '/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voiceog/';
const SLOT = `${SCHEMA}.custom-keybinding:${KEY}`;

function gs(args) {
  return new Promise((resolve, reject) => {
    execFile('gsettings', args, (err, stdout) => (err ? reject(err) : resolve(stdout.trim())));
  });
}

export async function gnomeAvailable() {
  try {
    await gs(['get', SCHEMA, 'custom-keybindings']);
    return true;
  } catch {
    return false;
  }
}

// Прописать наш слот в список custom-keybindings, если его там нет.
async function ensureSlot() {
  const cur = await gs(['get', SCHEMA, 'custom-keybindings']);
  if (cur.includes(KEY)) return;
  let next;
  if (cur === '@as []' || cur === '[]') next = `['${KEY}']`;
  else next = `${cur.replace(/\]$/, '')}, '${KEY}']`;
  await gs(['set', SCHEMA, 'custom-keybindings', next]);
}

// Поставить комбинацию и команду.
export async function setGnomeBinding(combo) {
  if (!(await gnomeAvailable())) return false;
  await ensureSlot();
  await gs(['set', SLOT, 'name', 'VOICEog — диктовка']);
  await gs(['set', SLOT, 'command', COMMAND]);
  await gs(['set', SLOT, 'binding', toGnomeBinding(combo)]);
  return true;
}

// Выключить биндинг (пустая комбинация), не удаляя слот.
export async function disableGnomeBinding() {
  if (!(await gnomeAvailable())) return false;
  await ensureSlot();
  await gs(['set', SLOT, 'binding', '']);
  return true;
}
