# VOICEog

Мини-локальный голосовой ввод. Жмёшь кнопку (или хоткей) — говоришь — текст падает
куда надо. Без облака, без аккаунтов, без агентов. Речь → текст на своей машине.

## Что внутри

- **Модель:** NVIDIA Parakeet TDT 0.6B v3 INT8 (25 языков, включая русский и украинский,
  язык определяется сам, пунктуация своя). Это STT/ASR, не LLM — для расшифровки
  большая языковая модель не нужна.
- **Движок:** `sherpa-onnx` (Node-аддон, CPU, int8).
- **UI:** одна HTML-страница, микрофон через Web Audio, отправка PCM 16 кГц моно.
  Тема — **авто / тёмная / светлая**, переключается прямо в шапке и запоминается
  (палитра в духе opencode.ai).
- **Диктовка:** глобальный хоткей, запись в фоне (`pw-record`), автовставка текста
  в активное окно (`wl-copy` + `ydotool` Ctrl+V).

```
два пути ввода:

1) браузер:  микрофон → 16 кГц моно PCM → POST /transcribe → textarea
2) хоткей:   pw-record (в демоне) → POST /toggle → STT → wl-copy + Ctrl+V → активное окно
```

## Запуск

```bash
./voiceog
```

Первый запуск сам поставит зависимости и скачает модель (~487 МБ).
Дальше открываешь http://127.0.0.1:7777, жмёшь микрофон, говоришь, жмёшь ещё раз.

## Windows

Проект работает и под Windows. Ядро (распознавание, страница, HTTP-API)
кроссплатформенное, а системная обвязка вынесена в `src/platform/` — под Windows
это отдельные адаптеры, Linux-путь не тронут.

Что чем заменено на Windows:

| Задача | Linux | Windows |
|---|---|---|
| запись с микрофона | `pw-record` | `ffmpeg` (`-f dshow`), бинарь идёт в комплекте (`ffmpeg-static`) |
| вставка в окно | `wl-copy` + `ydotool` | `Set-Clipboard` + `SendKeys('^v')` (PowerShell) |
| глобальный хоткей | `evdev` | `uiohook-napi` (`keydown`+`keyup`, работает режим *hold*) |
| запасной хоткей ОС | GNOME `gsettings` | не нужен |

Запуск и управление (двойной клик или из консоли):

```bat
voiceog.cmd            :: старт сервера (поставит зависимости и модель)
voiceog.cmd toggle     :: старт/стоп записи (это же дёргает хоткей)
voiceog.cmd status     :: состояние
```

Требования: Node 18+ и PowerShell (есть в любой Windows). FFmpeg тащить
отдельно не надо — он уже в зависимостях.

> **Важно про npm.** Свежие npm (11+) по умолчанию блокируют install-скрипты
> пакетов, а `uiohook-napi` и `ffmpeg-static` без них не поставят свои бинарники.
> Если после `npm install` хоткей/запись не работают — выполни один раз:
>
> ```bat
> npm rebuild uiohook-napi ffmpeg-static
> ```

Микрофон: по умолчанию voiceog **сам выбирает устройство со звуком** (перебирает
аудио-устройства и берёт то, где реальный сигнал — иначе легко нарваться на
«мёртвый» микрофон и писать тишину). Своё устройство можно задать в морде, блок
**[4] Микрофон**, или переменной `VOICEOG_AUDIO_DEVICE` (имя как в списке
DirectShow). Свой ffmpeg — `VOICEOG_FFMPEG`.

Автозапуск при входе (сервер поднимается **скрытно**, без окна консоли):

```powershell
powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
# снять:
powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove
```

Задача в автозагрузке зовёт `scripts\run-hidden.vbs`, а тот тихо запускает
`voiceog.cmd` — окно не мигает. Это per-user, **без прав администратора**.

Ограничения, честно: текст вставляется через буфер обмена (текущий буфер
перезапишется), и в окна, запущенные от имени администратора, вставка не пройдёт
(защита UIPI) — запускай VOICEog тем же уровнем прав, что и целевое окно.

## Диктовка по хоткею (GNOME/Wayland)

Три шага:

```bash
# 1. авто-вставка: ydotool (нужен один раз, требует sudo)
sudo dnf install -y ydotool
sudo mkdir -p /etc/systemd/system/ydotool.service.d
sudo tee /etc/systemd/system/ydotool.service.d/override.conf >/dev/null <<'EOF'
[Unit]
After=user-runtime-dir@1000.service

[Service]
ExecStart=
ExecStart=/usr/bin/ydotoold --socket-path=/run/user/1000/.ydotool_socket --socket-perm=0600 --socket-own=1000:1000
EOF
sudo systemctl daemon-reload && sudo systemctl enable --now ydotool

# 2. сам хоткей (по умолчанию Ctrl+Alt+V)
bash scripts/setup-hotkey.sh

# 3. (по желанию) автозапуск демона при входе
bash scripts/install-service.sh
```

После этого: нажал **Ctrl+Alt+V** → заговорил → нажал ещё раз → текст сам
вставился в то окно, которое активно.

> Почему так: на GNOME/Wayland набрать текст «по клавишам» нельзя — раскладку не
> обойти, кириллица не наберётся. Поэтому текст кладётся в буфер обмена и
> вставляется через Ctrl+V. `ydotool` — единственный рабочий способ эмулировать
> нажатия на GNOME/Wayland (через `/dev/uinput`).

## Хоткей и режимы — из веб-морды

В морде (`http://127.0.0.1:7777`) есть блок **[3] Хоткей**:

- **Комбинация** — жмёшь поле и набираешь своё сочетание, оно ловится и сохраняется.
- **Режим**:
  - *нажал — говоришь — нажал* (`toggle`) — как было: первое нажатие старт, второе стоп.
  - *держишь — говоришь — отпустил* (`hold`, push-to-talk) — пишет, пока держишь комбо.
- Настройки лежат в `voiceog.config.json` рядом с проектом и подхватываются сами.
- **Тема** — кнопки в шапке: *авто* (как в системе), *тёмная*, *светлая*. Тоже
  сохраняется в конфиг, а для мгновенного применения дублируется в `localStorage`.

Для режима **hold** нужен доступ к клавиатуре напрямую: GNOME-хоткей умеет только
«нажал», а «отпустил» — нет. Один раз:

```bash
sudo usermod -aG input "$USER"       # доступ к /dev/input/event* (нужен перелогин)
# и/или udev-правило uaccess — работает сразу, без перелогина:
sudo tee /etc/udev/rules.d/70-voiceog-input.rules >/dev/null <<'EOF'
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"
EOF
sudo udevadm control --reload-rules && sudo udevadm trigger --subsystem-match=input
```

Всё это делает один скрипт (идемпотентно):

```bash
bash scripts/install-input-access.sh
```

Когда доступ есть — хоткей читает клавиатуру сам (evdev), а GNOME-биндинг гасится,
чтобы не срабатывало дважды. Нет доступа — работает как раньше, через GNOME (только
режим *toggle*), а морда честно об этом пишет.

## Ручками

```bash
npm install            # зависимости
npm run model          # только скачать модель
npm start              # сервер
./voiceog toggle       # старт/стоп записи (это и дёргает хоткей)
./voiceog status       # состояние: пишет ли, готова ли вставка
```

Переменные:

- `VOICEOG_PORT` — порт (по умолчанию 7777)
- `VOICEOG_HOST` — адрес (по умолчанию 127.0.0.1, наружу не торчит)
- `VOICEOG_THREADS` — число потоков CPU (по умолчанию 4)
- `VOICEOG_MODEL` — путь к папке модели, если положил в другое место
- `VOICEOG_RECORDER` — команда записи (по умолчанию `pw-record`)
- `VOICEOG_NO_INJECT=1` — не вставлять текст в окно (серверный режим)

## HTTP

- `GET /` — морда
- `GET /health` — `{ok, model}`
- `GET /state` — `{recording, inject, model}`
- `POST /toggle` — старт/стоп записи; на стопе отдаёт `{recording:false, text, ms, injected}`
- `POST /transcribe` — принять WAV или сырой PCM 16 кГц моно, вернуть `{text, ms}`
- `POST /v1/audio/transcriptions` — **Whisper-совместимо** (multipart `file`), любой формат
  (ogg/opus/mp3/m4a/wav) → `{text}`. Сюда можно направить любой клиент, ждущий Whisper-API.

### Локальный STT для Telegram-бота

VOICEog умеет прикинуться Whisper-API — тогда голосовые в Телеге распознаются локально,
без облака. В `.env` бота:

```
STT_API_URL=http://127.0.0.1:7777/v1
STT_API_KEY=local
STT_MODEL=parakeet-tdt-0.6b-v3
```

## Проверка без браузера

```bash
curl -s http://127.0.0.1:7777/health
curl -s --data-binary @sample.wav http://127.0.0.1:7777/transcribe   # WAV
```

Сервер понимает и WAV (`RIFF`), и сырой PCM 16 кГц моно.

## Файлы

```
src/stt.mjs        обёртка над sherpa-onnx (загрузка модели, декод, разбор WAV)
src/server.mjs     http-сервер: /, /health, /state, /toggle, /transcribe, /api/settings
src/keys.mjs       раскладка: комбинация ↔ evdev-коды и GNOME-строка (плюс общий парсер)
src/settings.mjs   настройки (хоткей, режим) в voiceog.config.json
src/platform/      фасад под ОС: linux/* (pw-record, wl-copy, evdev, gsettings)
                   и win/* (ffmpeg dshow, Set-Clipboard + SendKeys, uiohook)
src/recorder.mjs   запись в демоне на Linux (pw-record)     ─┐ Linux-адаптеры,
src/inject.mjs     вставка на Linux (wl-copy + ydotool)       │ подключаются через
src/evdev.mjs      слушатель клавиатуры Linux (/dev/input)    │ src/platform/posix.mjs
src/gnome.mjs      GNOME-биндинг (запасной путь)            ─┘
public/index.html  морда: кнопка, статус, textarea, настройки хоткея
scripts/           download-model(.sh/.mjs), install-service, install-input-access,
                   setup-hotkey, install-autostart.ps1, run-hidden.vbs
voiceog            лаунчер + CLI для Linux (toggle / status)
voiceog.cmd        лаунчер + CLI для Windows
models/            модель (в git не летит)
```