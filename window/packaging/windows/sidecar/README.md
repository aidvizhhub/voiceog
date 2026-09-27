# Windows-sidecar: сборка переносимого Node + нативных модулей

Этот каталог — про то, как собрать **sidecar** для NSIS-установщика VOICEog:
портативный `node.exe` + `node_modules` с нативными модулями под **win32-x64** +
серверные файлы. Установщик кладёт всё это рядом с окном в
`%LOCALAPPDATA%\VOICEog`.

## Что такое sidecar и зачем он

Сервер (`src/server.mjs`) живёт **отдельным процессом** рядом с окном — окно
только рисует морду, а распознавание речи, запись микрофона и глобальный хоткей
делает Node. Такой «прицеп» к окну и называют sidecar.

Зависимости сервера частично **нативные** — это не JS, а собранные под
конкретную ОС бинарники:

| Пакет | Что даёт | Почему per-OS |
|-------|----------|----------------|
| `sherpa-onnx-node` + `sherpa-onnx-win-x64` | распознавание Parakeet | `sherpa-onnx.node` + `onnxruntime.dll` собраны под платформу |
| `uiohook-napi` | глобальный хоткей | префабр `prebuilds/win32-x64/uiohook-napi.node` |
| `ffmpeg-static` | запись микрофона (dshow) | `ffmpeg.exe` вместо линуксового `ffmpeg` |

## Почему нативники собираются только на Windows

`npm ci` тянет/собирает бинарники **под ту ОС, на которой запущен**. Запустишь на
Linux — получишь `sherpa-onnx-linux-x64` и ELF-бинарник `ffmpeg`; на Windows
такой sidecar упадёт при загрузке sherpa. Кросс-сборкой это не лечится (MSVC +
prebuilds + postinstall `ffmpeg-static`), поэтому win-`node_modules` собирает
**Windows-машина или CI-раннер `windows-latest`**.

Что можно сделать на Linux — только скачать портативный `node.exe`. Это и делает
`provision.sh`.

## Файлы

| Файл | Где запускать | Что делает |
|------|---------------|------------|
| `provision.sh` | Linux | качает `node.exe` (закреплённая LTS), сверяет sha256 из официального `SHASUMS256.txt`, кладёт в `win-sidecar/` |
| `build-node-modules.ps1` | **Windows/CI** | `npm ci --omit=dev`, проверяет нативники (PE), копирует `node_modules` + `src` + `public` + `scripts` + `package.json` в `win-sidecar/`, а также `models/` — если она есть в корне проекта |
| `verify-sidecar.sh` | Linux и Windows (Git Bash) | проверяет структуру sidecar, печатает «чего не хватает», код возврата 1 при дырах; модель — предупреждением |

## Порядок сборки

### 1. Linux — node.exe

```bash
window/packaging/windows/sidecar/provision.sh
# → window/target/win-sidecar/node.exe
```

Закреплена версия **v22.23.3** (LTS «Jod»). Перебить:
`VOICEOG_NODE_VER=v22.23.3 provision.sh`. Кэш загрузок — `/tmp/voiceog-win`
(`VOICEOG_CACHE`), папка sidecar — `window/target/win-sidecar` (`VOICEOG_SIDECAR_DIR`).

Если sha256 не сходится — скрипт удаляет файл и падает, чтобы не поехал битый
node.

### 2. Windows — node_modules и сервер

```powershell
powershell -ExecutionPolicy Bypass -File window\packaging\windows\sidecar\build-node-modules.ps1
```

Скрипт сам вычисляет корень проекта от своего местоположения. Ручки: `-RepoRoot`,
`-SidecarDir`, `-SkipNpmCi`. Если нативников нет или они не PE (собраны не на
Windows) — печатает список и падает с кодом 1.

Если в корне проекта есть `models/`, скрипт заодно кладёт модель в
`win-sidecar/models/` — тогда установщик с `WITH_MODEL=1` соберётся. Модели нет —
не падает, только предупреждает в сводке: собирай установщик с `WITH_MODEL=0`
(модель скачается при первом старте) или положи `models/` и повтори.

### 3. Проверка

```bash
bash window/packaging/windows/sidecar/verify-sidecar.sh
# можно указать папку: verify-sidecar.sh /путь/к/win-sidecar
```

На Linux всё честно: `node.exe` — `[ok]`, нативники — `[нет]` (их тут неоткуда
взять), код возврата 1. На Windows после шага 2 — всё `[ok]`.

Модель проверяется отдельно и **не роняет проверку**: без неё — жёлтое
предупреждение, `[ok]`-строки и код не меняются. Только при явном `WITH_MODEL=1`
отсутствие модели считается дырой (`[нет]`, код 1) — тогда её и правда обязана
быть.

## Что получается в sidecar

```
window/target/win-sidecar/
├─ node.exe                 портативный Node (PE32+)
└─ node_modules/
   ├─ sherpa-onnx-node/           JS-обвязка
   ├─ sherpa-onnx-win-x64/        sherpa-onnx.node + onnxruntime.dll
   ├─ uiohook-napi/prebuilds/win32-x64/uiohook-napi.node
   └─ ffmpeg-static/ffmpeg.exe
├─ src/                     server.mjs и вся обвязка
├─ public/                  index.html, pcm-worklet.js
├─ scripts/                 download-model.mjs (докачка модели)
├─ models/                  модель распознавания — если models/ есть в корне
│                           проекта (в репе её нет; build-node-modules.ps1
│                           копирует при наличии)
├─ package.json             type: module
```

`launch.vbs` перед стартом сервера добавляет
`server\node_modules\sherpa-onnx-win-x64` в `PATH` — оттуда sherpa грузит DLL.

## Встраивание в CI

Отдельного «CI-рецепта» больше нет: job `windows` в
`.github/workflows/release.yml` **гоняет те же скрипты, что и локальная сборка**.
Никакого ручного `curl node.exe` и никакого `npm ci` в корне джобы — всё делает
`provision.sh` (качает `node.exe`) и `build-node-modules.ps1` (сам зовёт
`npm ci --omit=dev` на Windows-раннере и собирает sidecar). Порядок шагов в job:

```yaml
# 1. node.exe в sidecar — тянет provision.sh (Linux-часть, sha256 сверяется).
- name: node.exe для sidecar (provision.sh)
  shell: bash
  run: bash window/packaging/windows/sidecar/provision.sh

# 2. node_modules с win-нативниками + серверные файлы (+ models/, если есть).
- name: node-модули под Windows (build-node-modules.ps1)
  shell: pwsh
  run: pwsh -NoProfile -ExecutionPolicy Bypass -File window/packaging/windows/sidecar/build-node-modules.ps1

# 3. Структурная проверка sidecar. WITH_MODEL=0 — как у установщика ниже:
#    модели в репе нет, её отсутствие тут не ошибка.
- name: Проверка sidecar (verify-sidecar.sh)
  shell: bash
  env:
    WITH_MODEL: '0'
  run: bash window/packaging/windows/sidecar/verify-sidecar.sh
```

Дальше job собирает окно (`cargo build --release`) и зовёт `build-installer.sh`,
который берёт `node.exe` и серверный каталог из `window/target/win-sidecar`.
`WITH_MODEL=0` — модель в репе не лежит (`models/` в `.gitignore`), её в CI не
кладут: скачается при первом старте у юзера.

Именно потому, что `npm ci` теперь зовётся **внутри** `build-node-modules.ps1` на
том же `windows-latest`, нативники собираются под win32-x64 — это и есть смысл
всего sidecar.

## Что осталось для Windows-раннера

- `npm ci --omit=dev` внутри `build-node-modules.ps1` на `windows-latest` —
  единственное место, где появляются `sherpa-onnx-win-x64` и `ffmpeg.exe`;
- прогнать `build-node-modules.ps1` + `verify-sidecar.sh` и убедиться, что
  `verify` выходит с кодом 0 (в CI это уже отдельный шаг);
- модель: либо `WITH_MODEL=0` (CI так и делает), либо положить `models/` перед
  шагом 2, чтобы `build-node-modules.ps1` закинул её в sidecar;
- отдать `win-sidecar` установщику: `-DSERVER_DIR=<...>\win-sidecar`
  `-DNODE_EXE=<...>\win-sidecar\node.exe`;
- живая проверка на Windows: сервер стартует, модель грузится, микрофон и
  хоткей работают.

Портативный `node.exe` из `provision.sh` от ОС не зависит — один и тот же файл
годится, что для Linux-подготовки, что для CI.
