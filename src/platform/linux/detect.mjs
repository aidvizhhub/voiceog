// detect.mjs — «что реально есть на этой машине».
//
// Тут нет ни одной проверки дистрибутива. Смысл в том, чтобы спрашивать не
// «какой у тебя Linux», а «что у тебя реально стоит»: какая сессия, есть ли
// звуковой сервер, есть ли чем вставлять текст, есть ли доступ к клавиатуре.
// Дальше каждый модуль берёт первый рабочий вариант из своей цепочки.
//
// Так делает весь живой опыт (Voxtype, nerd-dictation): возможностей меньше,
// чем комбинаций «дистрибутив × десктоп × сессия», и живут они дольше.

import fs from 'node:fs';
import path from 'node:path';

// Путь к исполняемому файлу или null. Свой мини-which: без шелла и зависимостей.
export function which(cmd) {
  for (const dir of (process.env.PATH || '').split(':')) {
    if (!dir) continue;
    const p = path.join(dir, cmd);
    try {
      fs.accessSync(p, fs.constants.X_OK);
      return p;
    } catch {
      // не тут — идём дальше
    }
  }
  return null;
}

// Wayland, X11 или вообще без графики (сервер/SSH). Этого хватает, чтобы
// выбрать, чем вставлять текст: набор инструментов у сессий разный.
export function session() {
  if (process.env.WAYLAND_DISPLAY || process.env.XDG_SESSION_TYPE === 'wayland') return 'wayland';
  if (process.env.DISPLAY) return 'x11';
  return 'unknown';
}

// Имя десктопа для отчёта доктора (GNOME, KDE, sway...). Не влияет на логику.
export function desktop() {
  const raw = process.env.XDG_CURRENT_DESKTOP || process.env.DESKTOP_SESSION || '';
  return raw.split(':')[0] || '?';
}

// Есть ли доступ читать клавиатуру через /dev/input. От этого зависит
// глобальный хоткей и режим удержания. Лечится: scripts/install-input-access.sh.
export function inputAccess() {
  let entries = [];
  try {
    entries = fs.readdirSync('/dev/input').filter((f) => /^event\d+$/.test(f));
  } catch {
    return false; // даже папки нет — не Linux-десктоп
  }
  for (const ev of entries) {
    try {
      const fd = fs.openSync(
        path.join('/dev/input', ev),
        fs.constants.O_RDONLY | fs.constants.O_NONBLOCK,
      );
      fs.closeSync(fd);
      return true; // хоть одно устройство читается — прав достаточно
    } catch {
      // нет прав на это устройство — пробуем следующее
    }
  }
  return false;
}

// Доступ на запись в /dev/uinput — через него ydotool и dotool шлют
// синтетические нажатия. Нужен только им, evdev-хоткею не нужен.
export function uinputAccess() {
  try {
    fs.accessSync('/dev/uinput', fs.constants.W_OK);
    return true;
  } catch {
    return false;
  }
}

// Куда система складывает настройки пользователя (XDG). Нужно для проверки
// автозапуска в докторе.
export function configHome() {
  return process.env.XDG_CONFIG_HOME || path.join(process.env.HOME || '/root', '.config');
}
