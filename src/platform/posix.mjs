// posix.mjs — адаптер Linux.
//
// Ядро проекта (сервер, распознавание, морда) ничего не знает про то, как тут
// всё устроено. Оно дёргает этот фасад, а фасад отдаёт то, что реально нашлось
// в системе: см. linux/recorder.mjs и linux/inject.mjs.
//
// Хоткей — evdev напрямую из /dev/input: он читает ядро, поэтому работает
// одинаково на X11 и Wayland и на любом десктопе. Запасной вариант — биндинг
// средствами GNOME (когда прав на /dev/input нет).

export { Recorder, listAudioDevices, recordingBackend } from './linux/recorder.mjs';
export { injectText, injectionStatus, injectionBackend } from './linux/inject.mjs';
export { HotkeyListener } from '../evdev.mjs';
export {
  setGnomeBinding as setFallbackBinding,
  disableGnomeBinding as disableFallbackBinding,
} from '../gnome.mjs';

export const hotkeyBackend = 'evdev';
