// platform/win/hotkey.mjs — глобальный хоткей на Windows через uiohook-napi.
//
// uiohook даёт keydown И keyup — значит режим удержания (hold) работает так же,
// как evdev на Linux. Модификаторы берём из флагов события (ctrlKey/altKey/…),
// а не считаем руками.

import { uIOhook } from 'uiohook-napi';
import { parseCombo } from '../../keys.mjs';
import { keyToCode, MOD_FLAG } from './keymap.mjs';

// uiohook — один глобальный хук на процесс: стартуем один раз, гасим когда
// слушателей не осталось.
let running = false;
let users = 0;

export class HotkeyListener {
  constructor({ hotkey, onDown, onUp, log = console.log } = {}) {
    this.log = log;
    this.onDown = onDown || (() => {});
    this.onUp = onUp || (() => {});
    this.available = false;
    this.devices = [];
    this.pressed = false; // наша клавиша зажата
    this.armed = false; // комбо сработало и ждёт отпускания
    this._attached = false;
    this._flags = null; // последние флаги модификаторов (ctrl/alt/shift/meta)
    this._kd = (e) => this._key(e, true);
    this._ku = (e) => this._key(e, false);
    this.setCombo(hotkey);
  }

  // Переключить комбо без перезапуска процесса.
  setCombo(hotkey) {
    const { mods, key } = parseCombo(hotkey);
    this.modsWanted = mods;
    this.keyCode = key != null ? keyToCode(key) : null;
  }

  start() {
    this.stop();
    if (this.keyCode == null) {
      this.log('[voiceog] в комбо нет клавиши — хоткей не поставлен');
      return false;
    }
    try {
      if (!running) {
        uIOhook.start();
        running = true;
      }
      users++;
      uIOhook.on('keydown', this._kd);
      uIOhook.on('keyup', this._ku);
      this._attached = true;
    } catch (e) {
      this.log(`[voiceog] uiohook не стартовал: ${e && e.message}`);
      return false;
    }
    this.available = true;
    this.devices = ['глобальная клавиатура (uiohook)'];
    this.log('[voiceog] хоткей через uiohook (глобальный)');
    return true;
  }

  stop() {
    if (this._attached) {
      try {
        uIOhook.off('keydown', this._kd);
        uIOhook.off('keyup', this._ku);
      } catch {
        /* пусто */
      }
      this._attached = false;
      if (users > 0) users--;
      if (users === 0 && running) {
        try {
          uIOhook.stop();
        } catch {
          /* пусто */
        }
        running = false;
      }
    }
    this.available = false;
    this.pressed = false;
    this.armed = false;
  }

  // Зажаты ли сейчас модификаторы нашего комбо (нужно, чтобы не вставлять текст,
  // пока пользователь ещё держит Ctrl/Alt — иначе Ctrl+V станет Ctrl+Alt+V).
  modsDown() {
    if (!this._flags) return false;
    return this.modsWanted.some((m) => !!this._flags[MOD_FLAG[m]]);
  }

  _key(e, down) {
    // Снимок модификаторов на каждое событие (не только по нашей клавише).
    this._flags = { ctrlKey: e.ctrlKey, altKey: e.altKey, shiftKey: e.shiftKey, metaKey: e.metaKey };

    if (e.keycode !== this.keyCode) return;

    if (down) {
      // автоповтор при зажатой клавише — пропускаем
      if (this.pressed) return;
      this.pressed = true;
      const ok = this.modsWanted.every((m) => !!e[MOD_FLAG[m]]);
      if (!ok) return;
      this.armed = true;
      this._safe(this.onDown, 'onDown');
      return;
    }

    this.pressed = false;
    if (this.armed) {
      this.armed = false;
      this._safe(this.onUp, 'onUp');
    }
  }

  _safe(fn, what) {
    try {
      fn();
    } catch (e) {
      this.log(`[voiceog] ${what} упал: ${e && e.message}`);
    }
  }
}
