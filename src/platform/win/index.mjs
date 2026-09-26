// platform/win/index.mjs — Windows-адаптер VOICEog.

export { Recorder, listAudioDevices } from './recorder.mjs';
export { injectText, injectionStatus } from './inject.mjs';
export { HotkeyListener } from './hotkey.mjs';

// На Windows системного «запасного» хоткея нет: глобальный хоткей ловит сам
// процесс через uiohook, поэтому заглушки.
export const setFallbackBinding = async () => false;
export const disableFallbackBinding = async () => false;

export const hotkeyBackend = 'uiohook';
export const injectionBackend = 'Set-Clipboard + SendKeys';
export const recordingBackend = 'ffmpeg (dshow)';
