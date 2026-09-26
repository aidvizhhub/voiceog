// evdev.mjs — слушатель клавиатуры напрямую через /dev/input/event*.
//
// Зачем: GNOME-хоткей знает только «нажал», а «отпустил» — нет. А для режима
// удержания (держишь — говоришь — отпустил) нужно именно отпускание.
//
// Читаем event-устройства клавиатуры, разбираем input_event (24 байта на
// 64-битной системе) и зовём onDown/onUp на нашем комбо.
//
// Виртуальные устройства (ydotoold, UInput, fake-mouse) ИСКЛЮЧАЕМ — иначе наша
// же вставка текста начнёт дёргать хоткей по кругу.

import fs from 'node:fs';
import path from 'node:path';
import { MOD_CODES, KEY_CODES, parseCombo, codeName } from './keys.mjs';

const EVENT_SIZE = 24; // struct input_event на x86_64
const EV_KEY = 0x01;

// Устройства, которые не должны нас триггерить: это синтетика/виртуалка.
const EXCLUDE = [/ydotoold/i, /uinput/i, /fake/i, /virtual/i, /rustdesk.*keyboard/i];

function sysName(ev) {
  try {
    return fs.readFileSync(`/sys/class/input/${ev}/device/name`, 'utf8').trim();
  } catch {
    return '';
  }
}

// Какие event-устройства нам доступны и не виртуальные.
export function listDevices() {
  let entries = [];
  try {
    entries = fs.readdirSync('/dev/input').filter((d) => /^event\d+$/.test(d));
  } catch {
    return [];
  }
  entries.sort((a, b) => parseInt(a.slice(5), 10) - parseInt(b.slice(5), 10));

  return entries.map((ev) => {
    const p = path.join('/dev/input', ev);
    const name = sysName(ev);
    let readable = false;
    try {
      const fd = fs.openSync(p, fs.constants.O_RDONLY | fs.constants.O_NONBLOCK);
      fs.closeSync(fd);
      readable = true;
    } catch {
      /* нет прав или устройства нет */
    }
    return { ev, path: p, name, readable, excluded: EXCLUDE.some((re) => re.test(name)) };
  });
}

// Отбираем, что реально слушать: доступные клавиатуры, без виртуалки.
// Consumer/System Control — это медиа-клавиши того же устройства, нам не нужны.
function pickDevices() {
  const all = listDevices();
  const ok = all.filter((d) => d.readable && !d.excluded);
  const realKbd = ok.filter(
    (d) => /keyboard/i.test(d.name) && !/consumer control|system control/i.test(d.name),
  );
  if (realKbd.length) return realKbd;
  const keyboards = ok.filter((d) => /keyboard/i.test(d.name));
  return keyboards.length ? keyboards : ok;
}

export class HotkeyListener {
  constructor({ hotkey, onDown, onUp, log = console.log } = {}) {
    this.log = log;
    this.onDown = onDown || (() => {});
    this.onUp = onUp || (() => {});
    this.streams = [];
    this.pressed = new Set(); // коды клавиш, зажатых сейчас
    this.mods = new Set(); // активные модификаторы
    this.armed = false; // комбо нажато и ещё не отпущено
    this.leftover = Buffer.alloc(0);
    this.available = false;
    this.devices = [];
    this.setCombo(hotkey);
  }

  // Переключить комбо без перезапуска процесса.
  setCombo(hotkey) {
    const { mods, key } = parseCombo(hotkey);
    this.modsWanted = mods;
    this.keyCode = key != null ? KEY_CODES[key] : null;
  }

  start() {
    this.stop();
    const devices = pickDevices();
    this.devices = devices.map((d) => d.name || d.ev);
    for (const d of devices) {
      try {
        const stream = fs.createReadStream(d.path);
        stream.on('data', (chunk) => this.feed(chunk));
        stream.on('error', () => this._drop(stream));
        stream.on('close', () => this._drop(stream));
        this.streams.push(stream);
      } catch {
        /* не открылось — пропускаем */
      }
    }
    this.available = this.streams.length > 0;
    this.log(
      this.available
        ? `[voiceog] хоткей через evdev: ${devices.map((d) => d.name || d.ev).join(', ')}`
        : '[voiceog] evdev недоступен — нет прав на /dev/input (нужна группа input)',
    );
    return this.available;
  }

  stop() {
    for (const s of this.streams) {
      try {
        s.destroy();
      } catch {
        /* пусто */
      }
    }
    this.streams = [];
    this.available = false;
    this.pressed.clear();
    this.mods.clear();
    this.armed = false;
    this.leftover = Buffer.alloc(0);
  }

  _drop(stream) {
    this.streams = this.streams.filter((s) => s !== stream);
    this.available = this.streams.length > 0;
  }

  // Разбираем поток input_event. Возможны неполные записи — копим остаток.
  feed(chunk) {
    const buf = this.leftover.length ? Buffer.concat([this.leftover, chunk]) : chunk;
    let off = 0;
    while (buf.length - off >= EVENT_SIZE) {
      const type = buf.readUInt16LE(off + 16);
      const code = buf.readUInt16LE(off + 18);
      const value = buf.readInt32LE(off + 20);
      if (type === EV_KEY) this._key(code, value);
      off += EVENT_SIZE;
    }
    this.leftover = buf.subarray(off);
  }

  _key(code, value) {
    const name = codeName(code);

    // модификаторы
    if (name && MOD_CODES[name]) {
      if (value === 0) this.mods.delete(name);
      else this.mods.add(name);
    }

    if (code !== this.keyCode) return;

    if (value === 0) {
      // отпустили нашу клавишу
      this.pressed.delete(code);
      if (this.armed) {
        this.armed = false;
        this._safe(this.onUp, 'onUp');
      }
      return;
    }

    // value 1 — нажали, 2 — автоповтор. Автоповтор игнорируем.
    if (value === 2 || this.pressed.has(code)) return;
    this.pressed.add(code);

    if (!this.modsWanted.every((m) => this.mods.has(m))) return;

    this.armed = true;
    this._safe(this.onDown, 'onDown');
  }

  _safe(fn, what) {
    try {
      fn();
    } catch (e) {
      this.log(`[voiceog] ${what} упал: ${e && e.message}`);
    }
  }
}
