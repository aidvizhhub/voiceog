// platform/index.mjs — фасад над ОС-спецификой VOICEog.
//
// Ядро (server/stt/settings/UI) ничего не знает про Linux или Windows: оно
// дёргает этот фасад, а фасад подсовывает нужный адаптер по process.platform.
//
// Linux   — как было: pw-record, wl-copy + ydotool, evdev, GNOME-биндинг.
// Windows — новые адаптеры: ffmpeg (dshow), Set-Clipboard + SendKeys, uiohook.
//
// Никакую логику ядра это не меняет — только точки входа.

import * as posix from './posix.mjs';
import * as win from './win/index.mjs';

export const IS_WINDOWS = process.platform === 'win32';
export const PLATFORM = process.platform;

const impl = IS_WINDOWS ? win : posix;

export const Recorder = impl.Recorder;
export const listAudioDevices = impl.listAudioDevices;
export const injectText = impl.injectText;
export const injectionStatus = impl.injectionStatus;
export const HotkeyListener = impl.HotkeyListener;

// Запасной хоткей средствами ОС (GNOME gsettings на Linux; на Windows — нет).
export const setFallbackBinding = impl.setFallbackBinding;
export const disableFallbackBinding = impl.disableFallbackBinding;

// Человеко-читаемые имена движков — для логов и морды.
export const hotkeyBackend = impl.hotkeyBackend;
export const injectionBackend = impl.injectionBackend;
export const recordingBackend = impl.recordingBackend;
