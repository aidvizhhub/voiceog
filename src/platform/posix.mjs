// platform/posix.mjs — адаптер Linux/macOS. Просто переиспользует текущие
// модули проекта без изменений, чтобы поведение на Linux осталось ровно прежним.

export { Recorder } from '../recorder.mjs';
export { injectText, injectionStatus } from '../inject.mjs';
export { HotkeyListener } from '../evdev.mjs';
export { setGnomeBinding as setFallbackBinding, disableGnomeBinding as disableFallbackBinding } from '../gnome.mjs';

// На Linux устройства ввода берёт сам pw-record (default), поэтому список пуст.
export const listAudioDevices = async () => [];

export const hotkeyBackend = 'evdev';
export const injectionBackend = 'wl-copy + ydotool';
export const recordingBackend = 'pw-record';
