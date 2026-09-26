// doctor.mjs — «что у меня в системе». Ничего не меняет, только рассказывает.
//
// Запусти на своей машине и сразу видно, что готово, а чего не хватает.
//    ./voiceog doctor
//
// Зависимостей нет — ни модели, ни npm. Чистые возможности системы.

import fs from 'node:fs';
import path from 'node:path';
import { session, desktop, inputAccess, uinputAccess, which, configHome } from './platform/linux/detect.mjs';
import { pickRecorder } from './platform/linux/recorder.mjs';
import { injectionStatus } from './platform/linux/inject.mjs';

const yes = (b) => (b ? 'да' : 'НЕТ');
const or = (...xs) => xs.find(Boolean);

const s = session();
const rec = pickRecorder();
const inj = injectionStatus();
const input = inputAccess();
const uinput = uinputAccess();

function autostart() {
  const desktopFile = path.join(configHome(), 'autostart', 'voiceog.desktop');
  const serviceFile = path.join(configHome(), 'systemd', 'user', 'voiceog.service');
  if (fs.existsSync(desktopFile)) return 'да (XDG .desktop)';
  if (fs.existsSync(serviceFile)) return 'да (systemd --user)';
  return 'нет — bash scripts/install-autostart.sh';
}

function micTool() {
  return or(which('pactl') && 'pactl', which('arecord') && 'arecord') || '—';
}

console.log('');
console.log('  VOICEog — доктор. Что есть на этой машине:');
console.log('');
console.log(`  сессия:      ${s}${desktop() !== '?' ? '  (' + desktop() + ')' : ''}`);
console.log(`  запись:      ${rec ? rec.name : 'НЕТ — ни pw-record, ни parec, ни arecord, ни ffmpeg'}`);
console.log(`  микрофоны:   ${micTool()}${micTool() === '—' ? ' (список будет пустой)' : ''}`);
console.log(`  вставка:     ${inj.ready ? inj.backend : 'НЕТ — ' + inj.missing.join(', ')}`);
console.log(`  /dev/input:  ${yes(input)}   ${input ? '(хоткей и удержание работают)' : '(нет прав — bash scripts/install-input-access.sh)'}`);
console.log(`  /dev/uinput: ${yes(uinput)}   ${uinput ? '(dotool может слать нажатия)' : '(нужен dotool; ydotool обходится своим демоном)'}`);
console.log(`  автозапуск:  ${autostart()}`);
console.log('');

if (!inj.ready) {
  console.log('  Вставка не готова. Что поставить (по одной из строк):');
  if (s === 'x11') console.log('    фид: xclip  или  xsel   •   паста: xdotool  или  ydotool');
  else console.log('    фид: wl-clipboard (wl-copy)   •   паста: ydotool');
  console.log('  Подробности — в README, раздел «Диктовка по хоткею».');
  console.log('');
}
