// pcm-worklet.js — захват микрофона в audio-потоке.
//
// Зачем: нативный WebKitGTK MediaRecorder отдаёт пустой аудиоблоб (encodebin
// поверх GStreamer ломается), а decodeAudioData(webm/opus) там же врёт. Поэтому
// пишем сами: ворклет получает Float32 со входа и отдаёт куски Int16 (s16le),
// а страница клеит из них WAV. Живём в audio-потоке, поэтому UI не роняет сэмплы.

class PcmCapture extends AudioWorkletProcessor {
  process(inputs) {
    // inputs[0][0] — первый канал (нам моно). Пусто — просто ждём дальше.
    const ch = inputs[0] && inputs[0][0];
    if (!ch || !ch.length) return true;

    const out = new Int16Array(ch.length);
    for (let i = 0; i < ch.length; i++) {
      const s = Math.max(-1, Math.min(1, ch[i]));
      out[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
    }

    // буфер передаём без копии (transfer) — ворклету он больше не нужен
    this.port.postMessage(out, [out.buffer]);
    return true; // жить, пока узел не отключат
  }
}

registerProcessor('pcm-capture', PcmCapture);
