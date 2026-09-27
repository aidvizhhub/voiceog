#!/usr/bin/env bash
# run.sh — «скачал → распаковал → запустил».
#
# Что делает по шагам:
#   1. Проверяет, что рядом лежит окно voiceog-window и есть node.
#   2. Подсказывает нативному движку sherpa-onnx, где его .so (в node_modules).
#   3. Если модели нет — качает её (scripts/download-model.sh; скачать ~487 МБ →
#      распакуется в ~641 МБ, один раз).
#   4. Поднимает локальный сервер, ждёт ответа /health.
#   5. Открывает окно-пульт.
#   6. Окно закрыли — гасит ТОЛЬКО свой сервер. Чужой (systemd/ручной) не трогает.
#
# Ручки для отладки:
#   VOICEOG_PORT=7998    — порт сервера (по умолчанию 7777)
#   VOICEOG_URL=http://… — адрес морды для окна (перебивает порт)
#   VOICEOG_MODEL=/путь  — своя папка с моделью (иначе ./models/…)
#
# Адрес на всех один: окно, health-чек и подъём сервера смотрят на ОДНУ базу.
#   • только VOICEOG_PORT     → база http://127.0.0.1:$PORT, сервер наш.
#   • VOICEOG_URL с локальным хостом (127.0.0.1 / localhost) → и проверяем,
#     и поднимаем сервер на порту из URL, и окно открываем туда же.
#   • VOICEOG_URL с чужим хостом → сервером не управляем, просто открываем окно.
set -euo pipefail

ROOT="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
cd "$ROOT"

PORT="${VOICEOG_PORT:-7777}"

# Разобрать URL на host и port. Печатает "host<TAB>port" (port пустой, если нет).
parse_host_port() {
  local rest hostport host port
  rest="${1#*://}"
  hostport="${rest%%[/?#]*}"
  host="${hostport%%:*}"
  if [ "$hostport" != "$host" ]; then
    port="${hostport#*:}"
  else
    port=""
  fi
  printf '%s\t%s\n' "$host" "$port"
}

# База — ровно как у окна: VOICEOG_URL, иначе http://127.0.0.1:$VOICEOG_PORT.
# Хвостовой слэш срезаем, чтоб не клеить //health.
if [ -n "${VOICEOG_URL:-}" ]; then
  BASE="${VOICEOG_URL%/}"
  IFS=$'\t' read -r BASE_HOST BASE_PORT < <(parse_host_port "$BASE")
  if [ -n "$BASE_PORT" ]; then
    PORT="$BASE_PORT"          # порт из URL главнее — сервер слушает именно его
  else
    BASE="http://${BASE_HOST}:$PORT"
  fi
else
  BASE_HOST="127.0.0.1"
  BASE="http://127.0.0.1:$PORT"
fi

# Своим сервером управляем только на локальном адресе. Чужой хост — не наша
# забота: окно открываем, сервер не поднимаем и не гасим.
case "$BASE_HOST" in
  127.0.0.1|localhost) MANAGE_SERVER=1 ;;
  *)                   MANAGE_SERVER=0 ;;
esac

BIN="$ROOT/voiceog-window"

log() { printf '[voiceog] %s\n' "$*"; }
die() { printf '[voiceog] ОШИБКА: %s\n' "$*" >&2; exit 1; }

# --- 1. окружение -----------------------------------------------------------
command -v node >/dev/null 2>&1 || die "нет node в PATH. Поставь Node.js 20+ (см. README.txt)."
[ -e "$BIN" ] || die "нет voiceog-window рядом с run.sh — архив распакован не целиком?"
[ -x "$BIN" ] || chmod +x "$BIN" 2>/dev/null || true
[ -x "$BIN" ] || die "voiceog-window не исполняемый: chmod +x '$BIN'"

# --- 2. нативный движок sherpa-onnx лежит в node_modules: даём ему путь ------
case "$(uname -m)" in
  x86_64)  LIB="sherpa-onnx-linux-x64" ;;
  aarch64) LIB="sherpa-onnx-linux-arm64" ;;
  *)       LIB="sherpa-onnx-linux-$(uname -m)" ;;
esac
if [ -d "$ROOT/node_modules/$LIB" ]; then
  export LD_LIBRARY_PATH="$ROOT/node_modules/$LIB:${LD_LIBRARY_PATH:-}"
fi

if [ "$MANAGE_SERVER" = 1 ]; then
  export VOICEOG_PORT="$PORT"
  export VOICEOG_URL="$BASE"
fi

# --- 3. модель (в бандл не входит — слишком большая) ------------------------
MODEL_DIR="${VOICEOG_MODEL:-$ROOT/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8}"
if [ ! -f "$MODEL_DIR/tokens.txt" ]; then
  log "модели нет — качаю (скачать ~487 МБ → распакуется в ~641 МБ, только в первый раз)…"
  # Папку передаём явно: своя VOICEOG_MODEL — скачаем ровно туда, а не в ./models.
  VOICEOG_MODEL="$MODEL_DIR" bash "$ROOT/scripts/download-model.sh"
fi

# --- 4. сервер --------------------------------------------------------------
server_up() { curl -sf -m 2 "$BASE/health" >/dev/null 2>&1; }
wait_health() {
  local tries="${1:-240}" i
  for ((i = 0; i < tries; i++)); do
    server_up && return 0
    sleep 0.5
  done
  return 1
}

# PID сервера, который подняли МЫ. Пусто — гасить нечего.
SPID=""
# shellcheck disable=SC2329  # зовётся из trap, статике не видно
cleanup() {
  [ -n "$SPID" ] || return 0
  if kill -0 "$SPID" 2>/dev/null; then
    log "гашу сервер, который поднял сам (PID $SPID)."
    kill "$SPID" 2>/dev/null || true
    local i
    for ((i = 0; i < 40; i++)); do
      kill -0 "$SPID" 2>/dev/null || return 0
      sleep 0.25
    done
    log "сервер не сдался по-хорошему — добиваю."
    kill -9 "$SPID" 2>/dev/null || true
  fi
}
# shellcheck disable=SC2329  # зовётся из trap, статике не видно
on_signal() { exit 130; }
trap cleanup EXIT
trap on_signal INT TERM

if [ "$MANAGE_SERVER" = 0 ]; then
  log "адрес чужой ($BASE) — сервером не управляю, просто открываю окно."
elif server_up; then
  log "сервер уже работает на $BASE — не трогаю его."
else
  log "поднимаю сервер на $BASE…"
  node "$ROOT/src/server.mjs" &
  SPID=$!
  log "жду готовности (грузит модель)…"
  if ! wait_health 240; then
    log "сервер так и не поднялся. Проверь вручную: node src/server.mjs"
    exit 1
  fi
  log "сервер готов: $BASE"
fi

# --- 5. окно ----------------------------------------------------------------
# Рендер окна выбирает сам бинарь: на NVIDIA+Wayland включает GPU через
# __NV_DISABLE_EXPLICIT_SYNC, иначе оставляет дефолт WebKit. Мы НЕ навязываем
# WEBKIT_DISABLE_DMABUF_RENDERER — иначе убиваем GPU-фикс. Аварийный CPU-режим:
# VOICEOG_DISABLE_DMABUF=1 (см. window/src/platform/linux.rs). Если задал
# пользователь снаружи — переменная унаследуется сама.

log "открываю окно…"
rc=0
"$BIN" || rc=$?
log "окно закрыто (код $rc)."
exit "$rc"
