// settings.mjs — настройки VOICEog, которые меняются из веб-морды.
// Лежат простым JSON рядом с проектом (voiceog.config.json).

import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { isValidCombo, formatCombo, parseCombo } from './keys.mjs';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
export const CONFIG_PATH = path.join(ROOT, 'voiceog.config.json');

export const DEFAULTS = {
  hotkey: 'ctrl+alt+v',
  // toggle — нажал, говорю, нажал ещё раз. hold — держу, говорю, отпустил.
  mode: 'toggle',
  // auto — как в системе, либо принудительно dark/light.
  theme: 'auto',
  // имя микрофона (Windows); пусто — авто-выбор устройства со звуком.
  audioDevice: '',
};

export function loadSettings() {
  let raw = {};
  try {
    raw = JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8'));
  } catch {
    /* файла нет — берём дефолт */
  }
  return normalize(raw);
}

// Приводим что угодно к валидному виду: битое — в дефолт, но без падения.
export function normalize(raw = {}) {
  const out = { ...DEFAULTS };
  if (typeof raw.hotkey === 'string' && isValidCombo(raw.hotkey)) {
    out.hotkey = formatCombo(parseCombo(raw.hotkey));
  }
  if (raw.mode === 'toggle' || raw.mode === 'hold') out.mode = raw.mode;
  if (['auto', 'dark', 'light'].includes(raw.theme)) out.theme = raw.theme;
  if (typeof raw.audioDevice === 'string') out.audioDevice = raw.audioDevice;
  return out;
}

export function saveSettings(s) {
  const clean = normalize(s);
  fs.writeFileSync(CONFIG_PATH, JSON.stringify(clean, null, 2) + '\n');
  return clean;
}
