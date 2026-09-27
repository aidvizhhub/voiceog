#!/usr/bin/env bash
# build-installer.sh — собрать установщик VOICEog для Windows.
#
# Что делает:
#   1. Проверяет makensis (NSIS) и exe окна.
#   2. Берёт Windows-node.exe и серверный каталог из sidecar:
#      window/target/win-sidecar/  (node.exe + src/ + public/ + node_modules/).
#      Их готовят sidecar/provision.sh (node.exe) и sidecar/build-node-modules.ps1
#      (node_modules — только на Windows). Если node.exe нет и включён
#      VOICEOG_DOWNLOAD_NODE=1 — зовём provision.sh, он скачает и сверит sha256.
#   3. Зовёт makensis с путями через -D.
#
# Ручки (env):
#   VOICEOG_NODE_EXE=<путь к node.exe>   — готовый Windows-node.exe
#   VOICEOG_WIN_EXE=<путь к exe окна>    — перебить exe
#   VOICEOG_SERVER_DIR=<корень>          — папка с src/public/node_modules/models
#   WITH_MODEL=0|1                       — класть модель (~641 МБ на диске) или нет (по умолч. 1)
#   OUT_FILE=<путь к setup.exe>          — куда положить установщик
#   VOICEOG_DOWNLOAD_NODE=1              — нет node.exe → позвать sidecar/provision.sh
#   VOICEOG_SIDECAR_DIR=<папка>          — где искать/класть node.exe (по умолч. window/target/win-sidecar)
#   VOICEOG_CACHE=<папка>                — кэш загрузок (по умолч. /tmp/voiceog-win)
#   APP_VERSION=<x.y.z>                  — версия для setup.exe; по умолч. берётся
#                                          из window/Cargo.toml (единый источник)
#
# Запуск:  window/packaging/windows/build-installer.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/../../.." && pwd)"

export VOICEOG_CACHE="${VOICEOG_CACHE:-/tmp/voiceog-win}"

# Sidecar — общий склад для node.exe и серверных файлов. Готовят его
# sidecar/provision.sh (node.exe) и sidecar/build-node-modules.ps1 (node_modules).
SIDECAR_DIR="${VOICEOG_SIDECAR_DIR:-$PROJECT/window/target/win-sidecar}"

WIN_EXE="${VOICEOG_WIN_EXE:-$PROJECT/window/target/x86_64-pc-windows-msvc/release/voiceog-window.exe}"
NODE_EXE="${VOICEOG_NODE_EXE:-$SIDECAR_DIR/node.exe}"
SERVER_DIR="${VOICEOG_SERVER_DIR:-$SIDECAR_DIR}"
WITH_MODEL="${WITH_MODEL:-1}"
OUT_FILE="${OUT_FILE:-$PROJECT/window/target/VOICEog-setup.exe}"

# makensis (нативный) считает относительные пути от своей базы, а не от нашего
# cwd — поэтому относительный WIN_EXE/NODE_EXE/SERVER_DIR может не найтись.
# Приводим к абсолютным до проверок и до -D.
abs() { case "$1" in /*|[A-Za-z]:*) printf '%s' "$1" ;; *) printf '%s/%s' "$PWD" "$1" ;; esac; }
WIN_EXE="$(abs "$WIN_EXE")"
NODE_EXE="$(abs "$NODE_EXE")"
SERVER_DIR="$(abs "$SERVER_DIR")"
OUT_FILE="$(abs "$OUT_FILE")"

log() { printf '[voiceog] %s\n' "$*"; }
die() { printf '[voiceog] ОШИБКА: %s\n' "$*" >&2; exit 1; }

# --- версия установщика ---------------------------------------------------
# Единый источник — window/Cargo.toml (как у AppImage/бандла). Иначе после тега
# v0.1.1 setup.exe врал бы «0.1.0»: NSIS-версия жила в .nsi хардкодом.
# Можно перебить снаружи: APP_VERSION=0.2.0 build-installer.sh
if [ -n "${APP_VERSION:-}" ]; then
  log "APP_VERSION задана снаружи: $APP_VERSION"
else
  APP_VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$PROJECT/window/Cargo.toml" | head -1)"
  [ -n "$APP_VERSION" ] || die "не удалось вытащить version из $PROJECT/window/Cargo.toml
  задай вручную: APP_VERSION=<x.y.z> $0"
fi

# makensis — нативная Windows-программа. Под Git Bash на Windows абсолютные
# POSIX-пути (/d/...) она не поймёт, поэтому конвертим через cygpath. На Linux
# cygpath нет — пути уходят как есть, и mingw-nsis их ест. Пути сюда приходят
# уже абсолютными (см. abs выше): относительные makensis считал бы от своей
# базы, а не от нашего cwd, и мог не найти файл.
to_win() {
  case "$1" in
    /*)
      if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
      ;;
    *) printf '%s' "$1" ;;
  esac
}

command -v makensis >/dev/null 2>&1 || die "нет makensis. Fedora: sudo dnf install -y mingw-nsis-base mingw64-nsis mingw32-nsis"
[ -f "$WIN_EXE" ] || die "нет exe окна: $WIN_EXE
  собери: cd $PROJECT/window && cargo xwin build --release --target x86_64-pc-windows-msvc
  (или задай VOICEOG_WIN_EXE=<путь>)"

# --- node.exe для Windows ------------------------------------------------
if [ ! -f "$NODE_EXE" ]; then
  if [ "${VOICEOG_DOWNLOAD_NODE:-0}" = "1" ]; then
    provision="$HERE/sidecar/provision.sh"
    [ -f "$provision" ] || die "нет $provision — не могу скачать node.exe
  задай VOICEOG_NODE_EXE=<путь к node.exe> вручную"
    log "нет node.exe — зову sidecar/provision.sh (скачает и сверит sha256)"
    VOICEOG_SIDECAR_DIR="$(dirname "$NODE_EXE")" bash "$provision"
    [ -f "$NODE_EXE" ] || die "provision.sh отработал, но $NODE_EXE так и нет"
  else
    die "нет Windows node.exe: $NODE_EXE
  это sidecar. Подготовь его:
    bash $PROJECT/window/packaging/windows/sidecar/provision.sh   (скачает node.exe)
    (или разом: VOICEOG_DOWNLOAD_NODE=1 $0)
  либо задай VOICEOG_NODE_EXE=<путь к node.exe>"
  fi
fi

# --- серверный каталог ----------------------------------------------------
[ -f "$SERVER_DIR/src/server.mjs" ] || die "нет серверного кода: $SERVER_DIR/src/server.mjs
  собери sidecar (на Windows): bash .../sidecar/provision.sh && pwsh .../sidecar/build-node-modules.ps1
  либо задай VOICEOG_SERVER_DIR=<каталог с src/public/node_modules>"
[ -d "$SERVER_DIR/node_modules" ] || die "нет $SERVER_DIR/node_modules
  нативные модули под win32-x64 собираются только на Windows — прогони sidecar/build-node-modules.ps1
  либо задай VOICEOG_SERVER_DIR=<каталог с src/public/node_modules>"

# --- модель ---
if [ "$WITH_MODEL" = "1" ]; then
  model="$SERVER_DIR/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
  [ -d "$model" ] || die "нет модели: $model
  включи -DWITH_MODEL=0 / WITH_MODEL=0, или положи модель"
  log "модель найдётся: $(du -sh "$model" 2>/dev/null | cut -f1) — установщик будет тяжёлым"
else
  log "WITH_MODEL=0 — модель в установщик не кладём (скачается при первом старте)"
fi

log "exe окна:   $WIN_EXE"
log "node.exe:   $NODE_EXE"
log "server dir: $SERVER_DIR"
log "версия:     $APP_VERSION"
log "собираю makensis..."

mkdir -p "$(dirname "$OUT_FILE")"

makensis -V3 \
  -DAPP_VERSION="$APP_VERSION" \
  -DWIN_EXE="$(to_win "$WIN_EXE")" \
  -DNODE_EXE="$(to_win "$NODE_EXE")" \
  -DSERVER_DIR="$(to_win "$SERVER_DIR")" \
  -DWITH_MODEL="$WITH_MODEL" \
  -DOUT_FILE="$(to_win "$OUT_FILE")" \
  "$(to_win "$HERE/voiceog.nsi")"

[ -f "$OUT_FILE" ] || die "makensis отработал, но $OUT_FILE нет"
log "готово: $OUT_FILE ($(du -h "$OUT_FILE" | cut -f1))"
