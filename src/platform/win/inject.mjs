// platform/win/inject.mjs — вставка текста в активное окно на Windows.
//
// Как и на Wayland, текст «по клавишам» набирать не надо: кладём его в буфер
// обмена и жмём Ctrl+V. Только средства другие:
//   буфер — Set-Clipboard (PowerShell, честный Unicode для кириллицы),
//   вставка — WScript.Shell.SendKeys('^v') в активное окно.
//
// Всё в одном вызове PowerShell, чтобы не дёргать его дважды.

import { spawn } from 'node:child_process';

const PS = process.env.VOICEOG_POWERSHELL || 'powershell';

export function injectionStatus() {
  return {
    ready: true, // PowerShell + SendKeys есть на любой Windows
    backend: 'Set-Clipboard + SendKeys',
    missing: [],
  };
}

// PowerShell: читает stdin как UTF-8, кладёт в буфер, затем Ctrl+V.
const SCRIPT = [
  'try { [Console]::InputEncoding=[System.Text.Encoding]::UTF8 } catch {}',
  '$t=[Console]::In.ReadToEnd()',
  'Set-Clipboard -Value $t',
  'Start-Sleep -Milliseconds 120',
  '$ws=New-Object -ComObject WScript.Shell',
  "$ws.SendKeys('^v')",
].join('; ');

export function injectText(text) {
  return new Promise((resolve) => {
    let proc;
    try {
      proc = spawn(PS, ['-NoProfile', '-NonInteractive', '-Command', SCRIPT], {
        stdio: ['pipe', 'ignore', 'pipe'],
        windowsHide: true,
      });
    } catch (e) {
      resolve({ ok: false, reason: e && e.message });
      return;
    }

    let err = '';
    proc.stderr.on('data', (d) => (err += d.toString('utf8')));
    proc.on('error', (e) => resolve({ ok: false, reason: e && e.message }));
    proc.on('close', (code) =>
      resolve(
        code === 0
          ? { ok: true }
          : { ok: false, reason: (err || `powershell код ${code}`).slice(0, 200) },
      ),
    );

    proc.stdin.end(Buffer.from(text, 'utf8'));
  });
}
