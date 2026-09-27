# CI релизов VOICEog

Один workflow: `.github/workflows/release.yml`. Собирает пакеты под Linux и
Windows и по тегу приклеивает их к GitHub Release.

## Что собирается

| Job | Раннер | Итог |
|-----|--------|------|
| `linux` | `ubuntu-22.04` | `voiceog-window_*.deb`, `voiceog-window-*.rpm`, `voiceog-window-*-x86_64.AppImage`, портативный `VOICEog-*-linux-x86_64.tar.zst` (если `zstd` нет — `.tar.gz`) |
| `windows` | `windows-latest` | `VOICEog-setup.exe` (+ голый `voiceog-window.exe`) |
| `release` | `ubuntu-latest` | те же файлы в GitHub Release (только по тегу) |

## Как выпустить релиз

Тегом. Всё остальное сделает workflow:

```bash
git tag v0.1.0
git push origin v0.1.0
```

- Тег должен начинаться с `v` (`v0.1.0`, `v1.2.3`), иначе job `release` не сработает.
- Хочешь погонять без релиза — вкладка **Actions → release → Run workflow**
  (`workflow_dispatch`): соберёт артефакты, но `release` пропустится, потому что
  это не тег.
- Артефакты лежат в конце страницы запуска: `linux-packages` и `windows-setup`.

Секреты не нужны: `GITHUB_TOKEN` выдаётся автоматически, job `release` просит
`contents: write`.

## Почему AppImage собирается на ubuntu-22.04

Не из вредности. AppImage кладёт внутрь себя системные библиотеки, а бинарник
линкуется с той `glibc`, что стоит на сборочной машине. `glibc` совместима
только «вперёд»: собранный на новом дистре образ не заведётся на старом.

- `ubuntu-24.04` → `glibc 2.39` → на Debian 12 / Ubuntu 22.04 / Fedora 39 **не запустится**.
- `ubuntu-22.04` → `glibc 2.35` → запускается везде, куда нам надо (Debian 12, Ubuntu 22.04+, Fedora).

Тот же старый раннер выгоден и для `.deb`/`.rpm` — пакеты получаются
совместимее. Поэтому весь `linux`-job сидит на 22.04, а не только AppImage.

## Откуда берутся win-node_modules

Нативные модули (`sherpa-onnx-node`, `uiohook-napi`, `ffmpeg-static`) содержат
бинарники и собираются/скачиваются **под конкретную ОС**. На Linux `npm ci`
даст linux-бинарник — в Windows-установщике он не заработает.

Поэтому job `windows` не делает `npm ci` в корне проекта, а гоняет те же
sidecar-скрипты, что и локальная сборка:

- `window/packaging/windows/sidecar/provision.sh` — качает `win-x64/node.exe`
  (сверяет sha256) в `window/target/win-sidecar/`;
- `window/packaging/windows/sidecar/build-node-modules.ps1` — на `windows-latest`
  делает `npm ci --omit=dev`, проверяет PE-нативники и зеркалит их плюс сервер
  (`src`, `public`, `scripts`, `package.json`) в тот же sidecar.

Дальше `build-installer.sh` берёт `node.exe` и серверный каталог из sidecar — CI
передаёт их явно (`VOICEOG_NODE_EXE`, `VOICEOG_SERVER_DIR=window/target/win-sidecar`
— путь относительно корня проекта).

- `package.json`/`package-lock.json` должны быть в репе — иначе не соберутся
  win-`node_modules`.
- Модель (`models/`, ~641 МБ на диске; скачиваемый архив — ~487 МБ) в репу не
  кладём, она в `.gitignore`. Установщик
  собирается с `-DWITH_MODEL=0` — модель качается при первом старте.
- Нужен офлайн-установщик с моделью — добавь в job шаг с кэшем модели и
  поставь `-DWITH_MODEL=1`.

## Что ещё не готово

- `window/` должен целиком лежать в репе. Проверка перед запуском CI:
  `git ls-files window` не пусто. Если его нет в чекауте, job `windows`
  падает уже на шаге `provision.sh` (скрипт не найден) — `hashFiles`-guard стоит
  только у шага портативного бандла, у sidecar и NSIS его нет. А `release` идёт
  с `needs: [linux, windows]`, поэтому релиз **не выйдет вообще** — это не
  «просто без `setup.exe`».
- Установщик `window/packaging/windows/voiceog.nsi` собирается через
  `build-installer.sh`; `continue-on-error` у шага NSIS нет.
- macOS в конвейере нет — окно под него пока не собирается.

## Ручная пересборка локально

То же самое, что делает CI, но на своей машине (Fedora):

```bash
# Linux-пакеты
cd window
cargo build --release
cargo deb
cargo generate-rpm
bash packaging/appimage/build.sh
SKIP_BUILD=1 bash packaging/bundle/make-bundle.sh   # портативный tar.zst (бинарник уже собран)

# Windows-установщик (нужен makensis + win-модули + exe)
window/packaging/windows/build-installer.sh
```
