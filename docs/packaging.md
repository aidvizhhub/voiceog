# Как собрать и раздать VOICEog

Этот файл — короткая шпаргалка по упаковке окна `voiceog-window`: что за файл,
одной командой, что получится на выходе. Подробности по каждой платформе — в
соседних файлах (`docs/window.md`, `window/packaging/windows/README.md`,
`window/packaging/ci/README.md`), тут всё в одном месте.

Важно держать в голове: раздача бывает двух сортов. **Системные пакеты**
(`.deb`, `.rpm`, AppImage) ставят **только окно** — сервер VOICEog (Node) они
внутрь не кладут, его ставят отдельно из исходников проекта. А **портативный
Linux-бандл и Windows-`setup.exe`** тащат сервер **с собой**: в бандле рядом с
окном лежат `src/`, `public/` и prod-`node_modules`, в установщик попадают
`node.exe` и серверные файлы. То есть юзер получает «поставил → запустил», без
отдельной сборки сервера. Само окно — рамка с иконкой в трее, показывает морду
сервера.

---

## Linux

Собираем из папки `window/`. Сначала — release-бинарник, потом упаковка.

```bash
cd ~/Projects/VOICEog/window
cargo build --release
```

Готовый бинарник: `window/target/release/voiceog-window` (~5.5 МБ; окно
потяжелело после перехода на `zbus` для single-instance — размер может немного
гулять между сборками).

### .deb — для Debian / Ubuntu / Mint

```bash
cd ~/Projects/VOICEog/window
cargo deb
# → window/target/debian/voiceog-window_0.1.0-1_amd64.deb
```

Что это: обычный пакет, который ставится в систему (`sudo apt install ./файл.deb`),
кладёт окно в меню приложений. Зависимости (`webkit2gtk-4.1`, `gtk3`,
`libappindicator`) подтянутся сами. **Сервер внутрь не входит** — `.deb` ставит
только окно, Node-сервер нужен отдельно (если хочешь сервер «в комплекте» —
бери портативный бандл или Windows-установщик).

Нужен установленный `cargo-deb` (ставится один раз: `cargo install cargo-deb`).

### .rpm — для Fedora / RHEL / openSUSE

```bash
cd ~/Projects/VOICEog/window
cargo build --release
cargo generate-rpm
# → window/target/generate-rpm/voiceog-window-0.1.0-1.x86_64.rpm
```

Ставится через `sudo dnf install ./файл.rpm`. **Сервер сюда тоже не входит** —
только окно (аналог `.deb`). `generate-rpm` отдельной сборки не делает — он берёт
уже собранный бинарник, поэтому `cargo build --release` идёт первым. Нужен
`cargo-generate-rpm` (`cargo install cargo-generate-rpm`).

### AppImage — «один файл, любой Linux»

```bash
cd ~/Projects/VOICEog/window
bash packaging/appimage/build.sh
# → window/target/appimage/voiceog-window-*.AppImage
```

Скрипт сам соберёт бинарник, скачает `linuxdeploy` и `appimagetool` в
`window/target/appimage/tools`, соберёт AppDir, подложит хелперы WebKit и
упакует всё в один `.AppImage`. Сеть нужна только в первый раз. Запуск у юзера:
`chmod +x файл.AppImage && ./файл.AppImage` — ничего в систему не ставится.
Как и `.deb`/`.rpm`, образ несёт **только окно** — сервер отдельно. Хочешь «всё
в одном файле» — смотри портативный бандл ниже.

Имя файла AppImage зависит от того, чем его собрали:

| Файл | Чем собран | Потолок glibc | Размер | Куда пойдёт |
|---|---|---|---|---|
| `voiceog-window-0.1.0-x86_64.AppImage` | CI, `ubuntu-22.04` (`build.sh`) | `2.35` | ~90 МБ | Debian 12, Ubuntu 22.04+, Fedora 39+ |
| `voiceog-window-0.1.0-x86_64-bookworm.AppImage` | локально, `build-bookworm.sh` (контейнер Debian 12) | `2.35` | ~90 МБ | то же самое |

Суффикс `-bookworm` даёт именно локальный `build-bookworm.sh`: он гоняет тот же
`build.sh` внутри контейнера `debian:bookworm` и только на выходе приписывает
суффикс к имени. CI зовёт `build.sh` напрямую, поэтому его файл — без суффикса.
Обе сборки сидят на `glibc 2.35`, так что по совместимости они эквивалентны:
юзеру разницы нет, отличается только имя. Fedora-вариант (хостовая сборка,
`glibc 2.39`, ~106 МБ) не раздаётся; `build.sh` на текущей системе по-прежнему
умеет его собрать — это локальный прогон под новые дистры, не релизный артефакт.

Локально сейчас лежит bookworm-именованный файл; в CI-релиз приезжает имя без
суффикса. Это один и тот же образ по совместимости.

**Почему glibc и «собирать на старой системе».** Бинарник линкуется с той
`glibc`, что стоит на сборочной машине, и совместимость работает только
«вперёд»: собранное на новом дистре не заведётся на старом. Поэтому AppImage
собирают на **старой** системе (в CI — `ubuntu-22.04`, glibc 2.35), чтобы он
пошёл и на Debian 12, и на Ubuntu 22.04+, и на Fedora. Соберёшь на свежем
Ubuntu 24.04 (glibc 2.39) — на старых дистрах он просто не запустится.

### Портативный бандл (Linux) — «скачал → распаковал → запустил»

Ничего не ставит в систему: распаковал архив и запустил. Собирается скриптом:

```bash
cd ~/Projects/VOICEog
bash window/packaging/bundle/make-bundle.sh
# → window/target/bundle/VOICEog-0.1.0-linux-x86_64.tar.zst   (~12 МБ)
```

Ручки:

- `SKIP_BUILD=1` — взять уже собранный `voiceog-window`, `cargo` не звать (CI или
  когда окно собирают отдельно);
- `KEEP_FFMPEG_STATIC=1` — не выкидывать `ffmpeg-static`. По умолчанию его режут:
  ~77 МБ, нужен только windows-слою (запись через dshow), в linux-бандле это балласт.

Что внутри (`window/target/bundle/VOICEog/`):

- `voiceog-window` — окно (~5.5 МБ, из-за `zbus`/single-instance);
- `src/`, `public/`, `package.json`, `package-lock.json` — сервер; windows-слой
  `src/platform/win` из бандла вырезается;
- `node_modules/` — прод-зависимости под linux-x64 с нативником
  `sherpa-onnx-linux-x64` (или `-arm64` на ARM); `ffmpeg-static` выкинут;
- `run.sh` + `README.txt`.

Что докладывает `run.sh` по шагам: проверяет, что рядом лежит `voiceog-window` и
есть `node` в `PATH`; подсказывает sherpa путь к `.so` (кладут
`node_modules/sherpa-onnx-linux-x64` в `LD_LIBRARY_PATH`); если модели нет —
качает её (`scripts/download-model.sh`, архив ~487 МБ, один раз); поднимает сервер,
ждёт `/health`; открывает окно; когда окно закрыли — гасит **только свой** сервер
(чужой не трогает). Ручки отладки: `VOICEOG_PORT` (по умолч. 7777),
`VOICEOG_URL`, `VOICEOG_MODEL`.

Цифры с живой сборки: распаковано ~40 МБ, `node_modules` ~35 МБ, архив
`tar.zst` ~12 МБ. **Модель в архив не входит** — качается при первом запуске.

Что нужно на целевой машине (тоже не входит, ставит юзер):

- Node.js 20+;
- `webkit2gtk-4.1`, `gtk3`, `libayatana-appindicator3` — иначе окно/трей не заведутся;
- для самой диктовки: микрофон (`pw-record` / `parec` / `arecord`), буфер
  (`wl-copy` / `xclip` / `xsel`), Ctrl+V (`ydotool` / `dotool` / `wtype` / `xdotool`),
  доступ к `/dev/input` (см. `scripts/install-input-access.sh`); `curl` + `tar` для модели.

Полный список с командами установки лежит в `window/packaging/bundle/README.txt`
— этот файл кладётся внутрь архива рядом с `run.sh`.

### Где что лежит

| Артефакт | Путь |
|---|---|
| release-бинарник | `window/target/release/voiceog-window` |
| .deb | `window/target/debian/*.deb` |
| .rpm | `window/target/generate-rpm/*.rpm` |
| AppImage | `window/target/appimage/*.AppImage` |
| скачанные тулзы AppImage | `window/target/appimage/tools/` |
| портативный бандл | `window/target/bundle/VOICEog-*.tar.zst` (или `.tar.gz`) |
| распакованное дерево бандла | `window/target/bundle/VOICEog/` |

`target/` — сборный мусор, в git не едет (`window/.gitignore`).

---

## Windows

Окно — нативное (tao + wry + tray-icon) и кросс-компилируется из-под Linux
через `cargo-xwin` (MSVC-тулчейн скачивается сам):

```bash
cd ~/Projects/VOICEog/window
cargo xwin build --release --target x86_64-pc-windows-msvc
# → window/target/x86_64-pc-windows-msvc/release/voiceog-window.exe
```

В exe окна **статически прилинкован только `WebView2Loader`** — поэтому отдельных
DLL рядом не надо. А **bootstrapper** (`MicrosoftEdgeWebview2Setup.exe`) — отдельный
файл: он попадает в установщик, только если лежит рядом (`voiceog.nsi:100-102`).
Сам движок — системный WebView2 (Edge/Chromium), свой браузер не тащим. На свежих
Windows 10/11 он уже стоит; установщик умеет его доставить.

### Windows: sidecar и установщик

Сервер живёт **отдельным процессом** рядом с окном — «sidecar». Собирается в три
шага, потому что нативные модули — per-OS. Порядок такой:

**1. node.exe — на Linux.**

```bash
cd ~/Projects/VOICEog
window/packaging/windows/sidecar/provision.sh
# → window/target/win-sidecar/node.exe
```

Скрипт качает официальный `win-x64/node.exe` закреплённой версии (**v22.23.3**,
LTS «Jod»), сверяет sha256 из `SHASUMS256.txt` и кладёт в sidecar. Если хеш не
сошёлся — файл удаляется, а скрипт падает (битый node не поедет). Ручки:
`VOICEOG_NODE_VER`, `VOICEOG_SIDECAR_DIR` (по умолч. `window/target/win-sidecar`),
`VOICEOG_CACHE` (по умолч. `/tmp/voiceog-win`). Это единственная часть,
которую можно собрать на Linux.

**2. win-`node_modules` и сервер — только на Windows/CI.**

```powershell
cd ~/Projects/VOICEog
powershell -ExecutionPolicy Bypass -File window\packaging\windows\sidecar\build-node-modules.ps1
```

Скрипт делает `npm ci --omit=dev` (на Linux он специально падает: нативники
встанут не под ту ОС), проверяет, что нативники реально PE (`MZ`):
`sherpa-onnx-win-x64/sherpa-onnx.node` + `onnxruntime.dll`,
`uiohook-napi/prebuilds/win32-x64/*.node`, `ffmpeg-static/ffmpeg.exe`, — и
зеркалит их плюс `src`, `public`, `scripts`, `package.json` в
`window/target/win-sidecar/`. Если в корне проекта есть `models/`, кладёт её в
`win-sidecar/models/` — это то, что нужно для сборки с `WITH_MODEL=1`
(в репе модели нет, `models/` в `.gitignore`). Ручки: `-RepoRoot`, `-SidecarDir`,
`-SkipNpmCi`.

**3. Проверка.**

```bash
cd ~/Projects/VOICEog
window/packaging/windows/sidecar/verify-sidecar.sh
# можно указать папку: verify-sidecar.sh /путь/к/win-sidecar
```

Печатает `[ok]` / `[нет]` по каждому файлу и возвращает код 1, если есть дыры.
На Linux нативников нет — это норма, они появляются только после шага 2.
Модель проверяется отдельно: при `WITH_MODEL=0` её отсутствие — не дыра
(скачается при первом старте), при `WITH_MODEL=1` — уже падение, как и у
`build-installer.sh`.

### Установщик setup.exe (NSIS)

```bash
cd ~/Projects/VOICEog
window/packaging/windows/build-installer.sh
# → window/target/VOICEog-setup.exe
```

Скрипт проверяет `makensis` и exe окна, берёт `node.exe` и серверный каталог из
sidecar (`window/target/win-sidecar/`), при `VOICEOG_DOWNLOAD_NODE=1` зовёт
`provision.sh`, затем зовёт `makensis` с путями через `-D`.

Env-ручки: `VOICEOG_NODE_EXE` (по умолч. `<sidecar>/node.exe`),
`VOICEOG_WIN_EXE`, `VOICEOG_SERVER_DIR` (по умолч. sidecar),
`WITH_MODEL` (`1` по умолч. — класть модель ~641 МБ на диске; `0` — качать при первом
старте), `OUT_FILE`, `VOICEOG_SIDECAR_DIR`, `VOICEOG_DOWNLOAD_NODE=1`,
`VOICEOG_CACHE`.

Установщик per-user, без прав администратора, ставит в
`%LOCALAPPDATA%\VOICEog`. Артефакт по умолчанию — `window/target/VOICEog-setup.exe`.

Расхождения с CI больше нет: **и локально, и в CI** `build-installer.sh` берёт
`node.exe` и серверный каталог из sidecar (`window/target/win-sidecar/`). CI
готовит sidecar теми же скриптами (`provision.sh` + `build-node-modules.ps1` +
`verify-sidecar.sh`) и явно передаёт пути через `VOICEOG_NODE_EXE` /
`VOICEOG_SERVER_DIR=window/target/win-sidecar` (путь относительно корня проекта).

NSIS на Fedora: `sudo dnf install -y mingw-nsis-base mingw64-nsis mingw32-nsis`
(нужен именно `mingw32-nsis` — он даёт 32-битные стабы, без них `makensis`
падает с «error setting default stub»).

---

## CI: релиз по тегу

Один workflow — `.github/workflows/release.yml`. Триггер: пуш тега `v*`
(напр. `v0.1.0`), плюс ручной запуск без релиза.

**Как выпустить релиз** — тегом:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Всё остальное workflow сделает сам. Секреты не нужны: `GITHUB_TOKEN` выдаётся
автоматически, job `release` отдельно просит `contents: write`.

| Job | Раннер | Что делает | Итог |
|---|---|---|---|
| `linux` | ubuntu-22.04 | ставит dev-пакеты (webkit2gtk-4.1, gtk3, soup3, appindicator, libfuse2, patchelf…), `cargo install cargo-deb cargo-generate-rpm`, `cargo build --release`, `cargo deb`, `cargo generate-rpm`, `window/packaging/appimage/build.sh`, `window/packaging/bundle/make-bundle.sh` (`SKIP_BUILD=1`) | `.deb`, `.rpm`, `.AppImage`, портативный `tar.zst` (окно + сервер) |
| `windows` | windows-latest | `provision.sh` (качает `node.exe`) → sidecar, `build-node-modules.ps1` (win-нативники) → sidecar, `verify-sidecar.sh` (`WITH_MODEL=0` — проверка, что sidecar собран целиком), `cargo build --release`, ставит NSIS (`choco install nsis`) и зовёт `build-installer.sh` c `VOICEOG_SERVER_DIR=window/target/win-sidecar` и `WITH_MODEL=0` | `VOICEog-setup.exe` + голый `voiceog-window.exe` |
| `release` | ubuntu-latest | скачивает артефакты (`actions/download-artifact`) и приклеивает к GitHub Release | файлы в Release (только по тегу) |

Нюансы:

- `linux` сидит на **ubuntu-22.04** (glibc 2.35) нарочно — см. про glibc выше и
  в хвостах: соберёшь на свежем дистре, пакет не заведётся на старом.
- `windows`-job **гоняет sidecar теми же скриптами, что и локально**:
  `provision.sh` качает `node.exe`, `build-node-modules.ps1` собирает
  win-`node_modules`, `verify-sidecar.sh` с `WITH_MODEL=0` проверяет, что sidecar
  собран целиком (без модели — её в репе нет). Дальше `build-installer.sh` берёт
  `node.exe` и серверный каталог из sidecar (`VOICEOG_NODE_EXE`,
  `VOICEOG_SERVER_DIR=window/target/win-sidecar`).
  Никакого `npm ci` в корне проекта нет — раньше было, от этого ушли.
- `hashFiles`-guard стоит **только** у шага портативного бандла
  (`make-bundle.sh`): если скрипта в чекауте нет (неполный чекаут) — шаг
  скипается. У шага NSIS `continue-on-error` нет. Поэтому перед запуском CI
  убедись, что `window/` в репе (`git ls-files window` не пусто) — иначе
  `provision.sh` не найдётся, job `windows` упадёт, а так как `release` требует
  `needs: [linux, windows]`, релиз не стартует (см. «Известные хвосты и риски»).
- **Воспроизводимость упаковок.** В workflow задан `SOURCE_DATE_EPOCH`
  (workflow-level `env`, по умолчанию `1700000000` = 2023-11-14T22:13:20Z;
  переопределяется Repository variable `SOURCE_DATE_EPOCH`). Он снимает «гуляние»
  метаданных: `.rpm` (`BUILDTIME`), `.deb` (mtime в ar/tar) и портативный
  tar-бандл (mtime файлов) при тех же исходниках дают одинаковые байты. Это
  значение попадает во **все** шаги обоих сборочных job'ов, а не только в
  упаковочные. `.exe` всё равно может отличаться: PE `TimeDateStamp` и случайный
  PDB GUID при линковке — MSVC-линкер недетерминирован здесь даже при заданном
  `SOURCE_DATE_EPOCH`. Это ожидаемо и задокументировано в самом workflow.
- Ручной запуск (`Actions → release → Run workflow`) собирает артефакты, но
  релиз не создаёт: job `release` требует тега.

---

## Известные хвосты и риски

- **glibc: локальные пакеты из Fedora 44 слишком свежие.** Бинарник, собранный на
  этой машине, тянет максимум `GLIBC_2.39` (проверено `objdump -T` и `rpm -qpR`).
  Значит, локальный `.rpm` не встанет на Debian 12 (2.36) и Ubuntu 22.04 (2.35) —
  ему нужны дистры со glibc ≥ 2.39 (Fedora 40+, Ubuntu 24.04+). Поэтому **релизные пакеты
  собирает CI на `ubuntu-22.04`** (glibc 2.35), а локальная сборка .deb/.rpm —
  только для проверки на этом же Fedora.
- **AppImage и трей.** `window/packaging/appimage/build.sh` теперь сам находит
  `libayatana-appindicator3.so.1`, отдаёт её linuxdeploy через `--library` (тот
  подтянет зависимости) и делает symlink по SONAME — раньше библиотеки в образе
  не было, и трей работал только там, где она стояла в системе. Осталось
  требование к **сборочной** машине: dev-пакет `libayatana-appindicator3-dev`
  должен стоять (в CI в списке apt он есть), иначе скрипт честно падает, а не
  собирает образ без трея.
- **Порт 7777 больше не зашит в белый список.** Навигация считается от
  фактического адреса морды: `VOICEOG_PORT` / `VOICEOG_URL` меняют и origin, и
  разрешение вместе (`window/src/main.rs`, `with_navigation_handler`). Хардкода
  нет — при смене порта морда грузится.
- **Нативные node-модули per-OS.** `node_modules` для Windows и Linux — разные
  (`sherpa-onnx-node`, `uiohook-napi`, `ffmpeg-static` тащат бинарники под ОС).
  В Windows-установщик кладётся только win-сборка (через sidecar), в Linux-бандл
  — только linux. Кросс-сборкой не лечится: win-`node_modules` собираются
  исключительно на Windows/CI.
- **`window/` должна лежать в репе — это предусловие релиза.** Проверка перед
  запуском CI: `git ls-files window` не пусто (в `.gitignore` её нет). Если её
  нет в чекауте, job `windows` падает на шаге `provision.sh` (скрипт не найден)
  — `hashFiles`-guard есть только у шага портативного бандла, у sidecar и NSIS
  его нет. `release` идёт с `needs: [linux, windows]`, поэтому **релиз не выйдет
  совсем** — а не «выйдет без `setup.exe`». Перед первым релизом убедись, что
  `window/` закоммичен.
