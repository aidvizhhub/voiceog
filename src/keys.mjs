// keys.mjs — раскладка клавиш: человеческая комбинация ↔ evdev-коды и GNOME-строка.
//
// Комбо у нас — простая строка: "ctrl+alt+v", "super+shift+f9" и т.п.
// Порядок модификаторов: ctrl, alt, shift, super. Ключ — последний.
//
// Здесь же перевод в linux/input-event-codes (для evdev) и в формат gsettings
// (для GNOME custom keybinding).

// Модификаторы: имя → коды левой и правой клавиши.
export const MOD_CODES = {
  ctrl: [29, 97],
  alt: [56, 100],
  shift: [42, 54],
  super: [125, 126],
};

// Обычные клавиши: каноническое имя → evdev-код.
export const KEY_CODES = {
  escape: 1,
  '1': 2, '2': 3, '3': 4, '4': 5, '5': 6, '6': 7, '7': 8, '8': 9, '9': 10, '0': 11,
  minus: 12, equal: 13, backspace: 14, tab: 15,
  q: 16, w: 17, e: 18, r: 19, t: 20, y: 21, u: 22, i: 23, o: 24, p: 25,
  bracketleft: 26, bracketright: 27, enter: 28,
  a: 30, s: 31, d: 32, f: 33, g: 34, h: 35, j: 36, k: 37, l: 38,
  semicolon: 39, quote: 40, backquote: 41, backslash: 43,
  z: 44, x: 45, c: 46, v: 47, b: 48, n: 49, m: 50,
  comma: 51, period: 52, slash: 53,
  space: 57,
  f1: 59, f2: 60, f3: 61, f4: 62, f5: 63, f6: 64, f7: 65, f8: 66, f9: 67, f10: 68,
  f11: 87, f12: 88,
  f13: 183, f14: 184, f15: 185, f16: 186, f17: 187, f18: 188, f19: 189, f20: 190,
  f21: 191, f22: 192, f23: 193, f24: 194,
  home: 102, up: 103, pageup: 104, left: 105, right: 106, end: 107, down: 108,
  pagedown: 109, insert: 110, delete: 111,
};

export const MOD_ORDER = ['ctrl', 'alt', 'super', 'shift'];

// evdev-код → каноническое имя (для модификаторов и клавиш).
const CODE_NAMES = new Map();
for (const [name, code] of Object.entries(KEY_CODES)) CODE_NAMES.set(code, name);
for (const [mod, codes] of Object.entries(MOD_CODES)) {
  for (const code of codes) CODE_NAMES.set(code, mod);
}

export function codeName(code) {
  return CODE_NAMES.get(code) || null;
}

// Разбирает "ctrl+alt+v" → { mods:[...], key:"v" }. Бросает при мусоре.
export function parseCombo(str) {
  if (typeof str !== 'string' || !str.trim()) throw new Error('пустая комбинация');
  const parts = str
    .toLowerCase()
    .split('+')
    .map((p) => p.trim())
    .filter(Boolean);

  const mods = [];
  let key = null;
  for (const p of parts) {
    if (MOD_ORDER.includes(p)) {
      if (!mods.includes(p)) mods.push(p);
    } else if (KEY_CODES[p] != null) {
      key = p;
    } else {
      throw new Error(`неизвестная клавиша: ${p}`);
    }
  }
  if (!key && mods.length === 0) throw new Error('пустая комбинация');
  mods.sort((a, b) => MOD_ORDER.indexOf(a) - MOD_ORDER.indexOf(b));
  return { mods, key };
}

// Собирает строку в стабильном порядке (модификаторы по MOD_ORDER).
export function formatCombo(combo) {
  const mods = MOD_ORDER.filter((m) => combo.mods.includes(m));
  return [...mods, ...(combo.key ? [combo.key] : [])].join('+');
}

// Проверка, что комбинация валидна (для API).
export function isValidCombo(str) {
  try {
    parseCombo(str);
    return true;
  } catch {
    return false;
  }
}

// GNOME-имена клавиш (не всё совпадает с нашими).
const GNOME_KEY = {
  escape: 'Escape', backspace: 'BackSpace', tab: 'Tab', enter: 'Return',
  space: 'space', delete: 'Delete', insert: 'Insert', home: 'Home', end: 'End',
  pageup: 'Page_Up', pagedown: 'Page_Down',
  up: 'Up', down: 'Down', left: 'Left', right: 'Right',
  minus: 'minus', equal: 'equal', comma: 'comma', period: 'period', slash: 'slash',
  semicolon: 'semicolon', quote: 'apostrophe', backquote: 'grave',
  backslash: 'backslash', bracketleft: 'bracketleft', bracketright: 'bracketright',
};

// "ctrl+alt+v" → "<Control><Alt>v" (формат gsettings).
export function toGnomeBinding(str) {
  const { mods, key } = parseCombo(str);
  const modName = { ctrl: 'Control', alt: 'Alt', shift: 'Shift', super: 'Super' };
  let out = '';
  for (const m of mods) out += `<${modName[m]}>`;
  if (key) {
    if (/^[a-z]$/.test(key) || /^[0-9]$/.test(key)) out += key;
    else if (/^f\d{1,2}$/.test(key)) out += key.toUpperCase();
    else out += GNOME_KEY[key] || key;
  }
  return out;
}
