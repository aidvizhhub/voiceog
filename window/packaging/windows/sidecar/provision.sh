#!/usr/bin/env bash
# provision.sh — заготовка Windows-sidecar'а на Linux-машине.
#
# Сервер VOICEog живёт отдельным процессом рядом с окном («sidecar»). На Windows
# его запускает портативный node.exe из папки установки. Этот скрипт берёт ровно
# ту часть, которую МОЖНО подготовить на Linux: сам node.exe. Всё остальное
# (node_modules с нативниками под win32-x64) собирается только на Windows — это
# делает build-node-modules.ps1.
#
# Что делает:
#   1. Качает SHASUMS256.txt для закреплённой версии Node.
#   2. Берёт из него официальный sha256 для win-x64/node.exe.
#   3. Качает node.exe (в кэш) и проверяет sha256.
#   4. Кладёт проверенный node.exe в win-sidecar/.
#
# Ручки (env):
#   VOICEOG_NODE_VER=<vX.Y.Z>     — версия Node (по умолч. v22.23.3, LTS «Jod»)
#   VOICEOG_SIDECAR_DIR=<путь>    — куда класть node.exe
#                                   (по умолч. window/target/win-sidecar)
#   VOICEOG_CACHE=<папка>         — кэш загрузок (по умолч. /tmp/voiceog-win)
#
# Запуск:  window/packaging/windows/sidecar/provision.sh
set -euo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
# .../sidecar → windows → packaging → window → корень проекта
PROJECT="$(cd "$HERE/../../../.." && pwd)"

NODE_VER="${VOICEOG_NODE_VER:-v22.23.3}"
SIDECAR_DIR="${VOICEOG_SIDECAR_DIR:-$PROJECT/window/target/win-sidecar}"
CACHE="${VOICEOG_CACHE:-/tmp/voiceog-win}"
BASE="https://nodejs.org/dist/$NODE_VER"

log() { printf '[sidecar] %s\n' "$*"; }
die() { printf '[sidecar] ОШИБКА: %s\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "нет curl — поставь: sudo dnf install -y curl"
command -v sha256sum >/dev/null 2>&1 || die "нет sha256sum (пакет coreutils)"

mkdir -p "$CACHE" "$SIDECAR_DIR"

# --- 1. официальные контрольные суммы -------------------------------------
SUMS="$CACHE/SHASUMS256-$NODE_VER.txt"
log "качаю контрольные суммы: $BASE/SHASUMS256.txt"
curl -fsSL --retry 3 -o "$SUMS" "$BASE/SHASUMS256.txt" \
  || die "не скачался SHASUMS256.txt для $NODE_VER — версия существует?"

WANT="$(awk '$2 == "win-x64/node.exe" { print $1 }' "$SUMS")"
[ -n "$WANT" ] || die "в SHASUMS256.txt нет строки win-x64/node.exe — версия $NODE_VER битая?"
log "официальный sha256 (win-x64/node.exe): $WANT"

# --- 2. качаем node.exe в кэш ---------------------------------------------
EXE="$CACHE/node-$NODE_VER-win-x64.exe"
if [ -f "$EXE" ] && [ "$(sha256sum "$EXE" | awk '{print $1}')" = "$WANT" ]; then
  log "node.exe уже в кэше и совпадает по sha256 — не качаю"
else
  log "качаю: $BASE/win-x64/node.exe"
  curl -fL --retry 3 -o "$EXE.part" "$BASE/win-x64/node.exe" \
    || die "не скачался node.exe"
  mv "$EXE.part" "$EXE"
fi

# --- 3. проверка sha256 ----------------------------------------------------
GOT="$(sha256sum "$EXE" | awk '{print $1}')"
if [ "$GOT" != "$WANT" ]; then
  rm -f "$EXE"
  die "sha256 НЕ сошёлся!
  ожидали: $WANT
  получили: $GOT
  файл удалён, попробуй ещё раз"
fi
log "sha256 сошёлся ✔"

# --- 4. кладём в sidecar ---------------------------------------------------
install -m 0755 "$EXE" "$SIDECAR_DIR/node.exe"

log "готово: $SIDECAR_DIR/node.exe"
if command -v file >/dev/null 2>&1; then
  printf '[sidecar] file:   %s\n' "$(file -b "$SIDECAR_DIR/node.exe")"
fi
printf '[sidecar] размер: %s\n' "$(du -h "$SIDECAR_DIR/node.exe" | cut -f1)"
printf '[sidecar] sha256: %s\n' "$(sha256sum "$SIDECAR_DIR/node.exe" | awk '{print $1}')"
log "дальше — build-node-modules.ps1 на Windows/CI (нативники под win32-x64 на Linux не собрать)"
