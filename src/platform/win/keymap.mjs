// platform/win/keymap.mjs — канонические имена клавиш (как в keys.mjs) →
// коды uiohook-napi (UiohookKey). Нужно и для валидации комбо, и для хоткея.

import { UiohookKey } from 'uiohook-napi';

// Именованные клавиши: наше имя → код uiohook.
const NAMED = {
  escape: UiohookKey.Escape,
  backspace: UiohookKey.Backspace,
  tab: UiohookKey.Tab,
  enter: UiohookKey.Enter,
  space: UiohookKey.Space,
  minus: UiohookKey.Minus,
  equal: UiohookKey.Equal,
  bracketleft: UiohookKey.BracketLeft,
  bracketright: UiohookKey.BracketRight,
  backslash: UiohookKey.Backslash,
  semicolon: UiohookKey.Semicolon,
  quote: UiohookKey.Quote,
  backquote: UiohookKey.Backquote,
  comma: UiohookKey.Comma,
  period: UiohookKey.Period,
  slash: UiohookKey.Slash,
  home: UiohookKey.Home,
  up: UiohookKey.ArrowUp,
  pageup: UiohookKey.PageUp,
  left: UiohookKey.ArrowLeft,
  right: UiohookKey.ArrowRight,
  end: UiohookKey.End,
  down: UiohookKey.ArrowDown,
  pagedown: UiohookKey.PageDown,
  insert: UiohookKey.Insert,
  delete: UiohookKey.Delete,
};

for (let i = 1; i <= 24; i++) NAMED['f' + i] = UiohookKey['F' + i];
for (const c of 'abcdefghijklmnopqrstuvwxyz') NAMED[c] = UiohookKey[c.toUpperCase()];
for (const d of '0123456789') NAMED[d] = UiohookKey[d];

// Каноническое имя → код uiohook (или null, если имя нам неизвестно).
export function keyToCode(name) {
  return NAMED[name] ?? null;
}

// Наши модификаторы → флаги события uiohook.
export const MOD_FLAG = {
  ctrl: 'ctrlKey',
  alt: 'altKey',
  shift: 'shiftKey',
  super: 'metaKey',
};
