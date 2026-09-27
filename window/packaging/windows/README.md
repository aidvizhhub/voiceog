# Установщик VOICEog для Windows

NSIS-скрипт, который собирает `VOICEog-setup.exe` — per-user установщик без прав
администратора. Ставит окно-пульт, портативный Node и сервер в
`%LOCALAPPDATA%\VOICEog`.

## Порядок сборки (для Windows-релиза)

Три шага, каждый на своей машине — потому что нативные модули под Windows на
Linux не собрать.

**1. `node.exe` — на Linux**

```bash
window/packaging/windows/sidecar/provision.sh
# → window/target/win-sidecar/node.exe  (качает LTS, сверяет sha256)
```

**2. `node_modules` + сервер — на Windows или CI-раннере (`windows-latest`)**

```powershell
powershell -ExecutionPolicy Bypass -File window\packaging\windows\sidecar\build-node-modules.ps1
# → window/target/win-sidecar/{node_modules,src,public,scripts,package.json}
#   + models/ — если models/ есть в корне проекта (модель не в репе, см. ниже)
```

Только Windows: `npm ci` тянет бинарники под текущую ОС, на Linux выйдут
linux-ELF и на Windows не заведутся.

**3. Установщик — там, где есть `makensis` (Linux тоже годится)**

```bash
window/packaging/windows/build-installer.sh
# → window/target/VOICEog-setup.exe
```

Скрипт по умолчанию берёт `node.exe` и серверный каталог из
`window/target/win-sidecar/`. Проверить, что sidecar собран целиком, можно так
(тот же шаг прогоняется в CI, job `windows`):

```bash
bash window/packaging/windows/sidecar/verify-sidecar.sh
# код 1 → чего-то не хватает, покажет список
```

### Модель и `WITH_MODEL`

Модель распознавания (~641 МБ распакованной) в репу не входит — `models/` в
`.gitignore`, и CI собирает установщик с `WITH_MODEL=0`.

- `WITH_MODEL=1` (по умолчанию) — модель должна лежать в
  `win-sidecar/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8`. Туда её
  кладёт `build-node-modules.ps1`, **если `models/` есть в корне проекта**. Нет
  `models/` — собирай с `WITH_MODEL=0`.
- `WITH_MODEL=0` — модель в установщик не кладём: `launch.vbs` скачает и
  распакует её при первом старте (~487 МБ).

`verify-sidecar.sh` про модель предупреждает, а не падает: при `WITH_MODEL=0`
её и не должно быть. Обязательной она становится только при явном
`WITH_MODEL=1` — тогда `build-installer.sh` честно падает и подсказывает, где
взять модель.

## Файлы

| Файл | Что это |
|------|---------|
| `voiceog.nsi` | сам скрипт установщика (NSIS 3.x) |
| `app.ico` | иконка (16–256 px), сделана из `../icon-256.png` |
| `launch.vbs` | тихий запуск: поднимает сервер и открывает окно (его зовут ярлыки) |
| `voiceog-console.cmd` | то же, но с видимой консолью — для отладки |
| `build-installer.sh` | обёртка над `makensis`: проверки + пути через `-D` |
| `sidecar/provision.sh` | Linux: качает Windows `node.exe`, сверяет sha256 |
| `sidecar/build-node-modules.ps1` | Windows/CI: win-`node_modules` + серверные файлы в sidecar |
| `sidecar/verify-sidecar.sh` | проверяет структуру sidecar, печатает «чего не хватает»; модель — предупреждением |
| `sidecar/README.md` | подробности про sidecar, версию Node и CI |

## Как собрать exe окна

Окно — нативный пульт на tao+wry+tray. Собирается под Windows из-под Linux
через `cargo-xwin` (кросс-компиляция, MSVC-тулчейн качается сам):

```bash
cd window
cargo xwin build --release --target x86_64-pc-windows-msvc
# → target/x86_64-pc-windows-msvc/release/voiceog-window.exe
```

Загрузчик WebView2 вшит в exe статически — отдельные DLL рядом не нужны,
движок берётся из системы (см. ниже).

## Ручки: env-переменные

`build-installer.sh` читает их из окружения:

| Переменная | Смысл | По умолчанию |
|------------|-------|--------------|
| `VOICEOG_WIN_EXE` | exe окна | `window/target/x86_64-pc-windows-msvc/release/voiceog-window.exe` |
| `VOICEOG_NODE_EXE` | готовый Windows `node.exe` | `window/target/win-sidecar/node.exe` |
| `VOICEOG_SERVER_DIR` | корень сервера (`src`, `public`, `node_modules`, `models`) | `window/target/win-sidecar` |
| `VOICEOG_SIDECAR_DIR` | общий склад sidecar (отсюда берутся node.exe и сервер по умолчанию) | `window/target/win-sidecar` |
| `VOICEOG_DOWNLOAD_NODE=1` | нет `node.exe` → позвать `sidecar/provision.sh` (скачает и сверит sha256) | выкл |
| `VOICEOG_CACHE` | кэш загрузок | `/tmp/voiceog-win` |
| `WITH_MODEL` | `1` — класть модель (на диске ~641 МБ), `0` — качать при первом старте (архив ~487 МБ) | `1` |
| `OUT_FILE` | куда положить установщик | `window/target/VOICEog-setup.exe` |

`VOICEOG_SIDECAR_DIR` задаёт папку, а `VOICEOG_NODE_EXE`/`VOICEOG_SERVER_DIR`
вычисляются из неё. Явно заданные `NODE_EXE`/`SERVER_DIR` сильнее.

Те же значения можно передать прямо в `makensis` через `-D`:

```bash
makensis -DWIN_EXE=/path/voiceog-window.exe -DNODE_EXE=/path/node.exe \
         -DSERVER_DIR=/path/to/win-sidecar -DWITH_MODEL=0 \
         -DOUT_FILE=/path/VOICEog-setup.exe voiceog.nsi
```

| Флаг | Смысл | По умолчанию в `.nsi` |
|------|-------|------------------------|
| `-DWIN_EXE` | exe окна | `..\..\target\x86_64-pc-windows-msvc\release\voiceog-window.exe` |
| `-DNODE_EXE` | Windows `node.exe` | `..\..\target\win-sidecar\node.exe` |
| `-DSERVER_DIR` | каталог сервера | `..\..\target\win-sidecar` |
| `-DWITH_MODEL` | `1`/`0` — класть модель | `1` |
| `-DOUT_FILE` | путь к установщику | `..\..\target\VOICEog-setup.exe` |

Если чего-то не хватает, и скрипт, и `.nsi` падают с понятным текстом — что и
где взять.

## Где какой артефакт появляется

| Артефакт | Кто делает | Путь |
|----------|-----------|------|
| Windows `node.exe` | `sidecar/provision.sh` (Linux) | `window/target/win-sidecar/node.exe` |
| win-`node_modules` + серверные файлы | `sidecar/build-node-modules.ps1` (Windows/CI) | `window/target/win-sidecar/` |
| модель (при наличии `models/`) | `sidecar/build-node-modules.ps1` (Windows/CI) | `window/target/win-sidecar/models/` |
| exe окна (кросс из Linux) | `cargo xwin build` | `window/target/x86_64-pc-windows-msvc/release/voiceog-window.exe` |
| exe окна (нативная сборка) | `cargo build --release` | `window/target/release/voiceog-window.exe` |
| установщик | `build-installer.sh` | `window/target/VOICEog-setup.exe` |

`window/target/` — целиком в `.gitignore`, в репу ничего из этого не попадает.

## Что такое sidecar и почему нативные модули на Windows

Сервер (`src/server.mjs`) — это Node, который держит «ядро»: распознавание
речи и хоткей. Он живёт **отдельным процессом** рядом с окном — отсюда
«sidecar»: окно только показывает морду, а всю работу делает сервер.

Часть зависимостей — нативные бинарники, собранные под конкретную ОС:

| Пакет | Зачем | Почему per-OS |
|-------|-------|----------------|
| `sherpa-onnx-node` (+ `sherpa-onnx-win-x64`) | распознавание Parakeet | `sherpa-onnx.node` + `onnxruntime.dll` собраны под платформу |
| `uiohook-napi` | глобальный хоткей | префабр `prebuilds/win32-x64/*.node` |
| `ffmpeg-static` | запись микрофона (dshow) | `ffmpeg.exe` вместо линуксового `ffmpeg` |

Поэтому `node_modules` для Windows **нельзя** взять из Linux-сборки: его
ставит/собирает Windows-машина или CI (`npm ci` на win32). В установщик кладём
уже готовый win-`node_modules` + портативный `node.exe`.

`launch.vbs` перед стартом сервера добавляет
`server\node_modules\sherpa-onnx-win-x64` в `PATH` — оттуда sherpa грузит свои DLL.

## Грабли

- **Fedora и NSIS — три пакета.** Мало `mingw-nsis-base` и `mingw64-nsis`:
  базовый кладёт только 64-битные стабы, а `makensis` по умолчанию ищет
  32-битный `zlib-x86-unicode` и падает с «error setting default stub».

  ```bash
  sudo dnf install -y mingw-nsis-base mingw64-nsis mingw32-nsis
  ```

- **WebView2 (Evergreen).** Окно рендерит системный Edge/Chromium, свой браузер
  не тащим. На свежих Win10/11 он уже стоит. Установщик проверяет реестр в трёх
  местах; не нашёл — запускает Evergreen Bootstrapper. Положи его рядом с
  проектом как `MicrosoftEdgeWebview2Setup.exe`, тогда он попадёт внутрь
  установщика (иначе предложит скачать вручную). Проверить руками:

  ```powershell
  Get-ItemProperty 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}' | Select pv
  ```

- **Нативные модули — только под win32.** `sherpa-onnx-win-x64`, `uiohook-napi`
  и `ffmpeg.exe` появляются исключительно после `npm ci` на Windows. На Linux
  их не собрать — это нормально, `verify-sidecar.sh` там честно покажет `[нет]`
  и код 1. Собранные не на Windows нативники `.ps1` отсеет по PE-заголовку «MZ».

- **Модель: архив ~487 МБ, распаковано ~641 МБ на диске.**
  `models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8` лежит в установщике
  распакованной (LZMA её не жмёт — уже сжата). Хочешь лёгкий setup —
  `WITH_MODEL=0`, тогда `launch.vbs` докачает при первом старте архив (~487 МБ)
  и распакует в `models/` (~641 МБ). Есть `models/` в корне — её в sidecar
  заберёт `build-node-modules.ps1`, и `WITH_MODEL=1` соберётся.
  В CI так и делают (модели в репе нет).

## Что ставится и куда

```
%LOCALAPPDATA%\VOICEog\
├─ voiceog-window.exe     окно-пульт
├─ node.exe               портативный Node
├─ launch.vbs             тихий запуск (ярлыки зовут его)
├─ voiceog-console.cmd    запуск с логами
├─ app.ico
├─ uninstall.exe
└─ server\
   ├─ public\             морда (index.html, pcm-worklet.js)
   ├─ src\                server.mjs и обвязка
   ├─ node_modules\       win-модули (sherpa, uiohook, ffmpeg)
   ├─ models\             модель распознавания
   └─ scripts\            download-model.mjs и пр.
```

Ярлыки: Пуск → `VOICEog`, и на Рабочем столе — оба зовут
`wscript.exe launch.vbs` (без окна консоли). Запись для удаления лежит в
`HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\VOICEog`.

Порядок запуска: `launch.vbs` → если сервер уже отвечает на
`http://127.0.0.1:7777/health`, не трогает его → иначе поднимает
`node.exe server\src\server.mjs` в фоне и ждёт до 60 c → открывает окно →
когда окно закрыли («Выход» в трее), гасит **только свой** сервер.

## Что осталось для реальной Windows-сборки

- на Windows/CI: `provision.sh` → `build-node-modules.ps1` → `verify-sidecar.sh`
  (код 0);
- задать `VOICEOG_WIN_EXE` под свою сборку окна и прогнать `build-installer.sh`;
- (по желанию) положить рядом `MicrosoftEdgeWebview2Setup.exe`;
- живая проверка на Windows: ярлыки, трей, микрофон, хоткей, удаление.
