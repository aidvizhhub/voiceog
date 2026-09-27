#!/usr/bin/env bash
# run-window.sh — одна кнопка: «запусти пульт VOICEog».
#
# По-человечески, что тут происходит по шагам:
#   1. Смотрим, живо ли ядро VOICEog на $BASE/health (тот же адрес, что у окна).
#   2. Живо — НЕ трогаем. Может, его поднял systemd или ты сам в другом окне.
#   3. Мертво — поднимаем сервер в фоне и ждём, пока он откликнется. Пока он
#      грузит модель, ответа нет, это нормально (пара секунд).
#   4. Открываем нативное окно window/target/release/voiceog-window.
#   5. Окно закрыли — гасим ТОЛЬКО тот сервер, который подняли сами. Чужой
#      (systemd, ручной) не трогаем никогда — иначе погасили бы его кому-то.
#
# Запускать можно сколько угодно раз: второй раз ничего не сломает и второго
# окна не откроет.
#
#   scripts/run-window.sh
#
# Ручки на случай отладки:
#   VOICEOG_PORT=7777             — порт сервера (по умолчанию 7777)
#   VOICEOG_URL=http://...        — адрес морды для окна (перебивает порт)
#   VOICEOG_WINDOW_ALLOW_MULTI=1  — снимает только pgrep-проверку лончера;
#                                   zbus-защита бинаря независима — на живом
#                                   D-Bus второго окна всё равно не будет
#
# Адрес на всех один: окно, health-чек и подъём сервера смотрят на ОДНУ базу.
#   • только VOICEOG_PORT     → база http://127.0.0.1:$PORT, сервер наш.
#   • VOICEOG_URL с локальным хостом (127.0.0.1 / localhost) → и проверяем,
#     и поднимаем сервер на порту из URL, и окно открываем туда же.
#   • VOICEOG_URL с чужим хостом → сервером не управляем, просто открываем окно.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
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

BIN="$ROOT/window/target/release/voiceog-window"

log()  { printf '[voiceog] %s\n' "$*"; }
die()  { printf '[voiceog] ОШИБКА: %s\n' "$*" >&2; exit 1; }

# Сервер отвечает? Тихий короткий запрос, чтоб не ждать впустую.
server_up() { curl -sf -m 2 "$BASE/health" >/dev/null 2>&1; }

# Ждём, пока сервер проснётся. $1 — сколько попыток по полсекунды.
wait_health() {
  local tries="${1:-120}"
  local i
  for ((i = 0; i < tries; i++)); do
    server_up && return 0
    sleep 0.5
  done
  return 1
}

# PID сервера, который подняли МЫ. Пусто — значит ничего своего нет,
# и гасить на выходе нечего.
SPID=""

# Гасим ровно свой сервер. Мягко (SIGTERM), потом ждём, потом добиваем.
# shellcheck disable=SC2329  # зовётся из trap, статике не видно
cleanup() {
  [ -n "$SPID" ] || return 0
  if kill -0 "$SPID" 2>/dev/null; then
    log "окно закрыто — гашу сервер, который поднял сам (PID $SPID)."
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

# --- окно должно быть собрано ---
if [ ! -x "$BIN" ]; then
  die "окно не собрано. Собери один раз:  cd '$ROOT/window' && cargo build --release"
fi

# --- не плодим второе окно и второй трей ---
if [ -z "${VOICEOG_WINDOW_ALLOW_MULTI:-}" ] && pgrep -x voiceog-window >/dev/null 2>&1; then
  log "окно уже открыто — второй пульт не поднимаю."
  log "Надо всё равно ещё одно: запусти с VOICEOG_WINDOW_ALLOW_MULTI=1"
  exit 0
fi

# --- нативный движок sherpa-onnx лежит в node_modules: даём ему путь (как ./voiceog) ---
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

# Поднять сервер своими руками и дождаться, пока откликнется.
start_own_server() {
  # Зависимости и модель обычно уже на месте. Если нет — зовём ./voiceog,
  # он сам поставит npm-пакеты и скачает модель, а потом станет тем же сервером.
  local dep="$ROOT/node_modules/sherpa-onnx-node"
  local model="$ROOT/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8/tokens.txt"
  if [ -d "$dep" ] && [ -f "$model" ]; then
    log "сервер не отвечает — поднимаю его в фоне."
    ( cd "$ROOT" && exec node src/server.mjs ) &
  else
    log "нет зависимостей или модели — поднимаю через ./voiceog (доставит и скачает)."
    ( cd "$ROOT" && exec "$ROOT/voiceog" ) &
  fi
  SPID=$!

  log "жду, пока сервер проснётся (грузит модель)…"
  if ! wait_health 120; then
    log "сервер так и не поднялся. Глянь глазами:  ./voiceog"
    exit 1
  fi
  log "сервер готов: $BASE"
}

# Юнит voiceog.service всегда слушает стандартный 7777. Если мы на этом же
# порту и юнит уже активен (или как раз стартует на входе в систему) —
# сервер поднимет он, а мы просто подождём. Так нет гонки «два сервера на
# один порт». На другом порту или при неактивном юните поднимаем сами.
if [ "$MANAGE_SERVER" = 0 ]; then
  log "адрес чужой ($BASE) — сервером не управляю, просто открываю окно."
else
  unit_state="$(systemctl --user is-active voiceog.service 2>/dev/null || true)"
  prefer_systemd=0
  if [ "$PORT" = "7777" ]; then
    case "$unit_state" in
      active|activating|reloading) prefer_systemd=1 ;;
    esac
  fi

  if server_up; then
    log "сервер уже работает на $BASE — не трогаю его."
  elif [ "$prefer_systemd" = 1 ]; then
    log "сервер поднимает systemd (voiceog.service: $unit_state) — жду до 60 с."
    if wait_health 120; then
      log "сервер готов: $BASE"
    else
      log "systemd не поднял — поднимаю сам."
      start_own_server
    fi
  else
    start_own_server
  fi
fi

# WebKitGTK на Wayland падает с «Error 71», когда включён DMABUF-рендерер.
# Сам бинарь это уже гасит; страхуемся, если снаружи переменную обнулили.
export WEBKIT_DISABLE_DMABUF_RENDERER="${WEBKIT_DISABLE_DMABUF_RENDERER:-1}"

log "открываю окно…"
rc=0
"$BIN" || rc=$?
if [ "$rc" -eq 0 ]; then
  log "окно закрыто."
else
  log "окно завершилось с кодом $rc."
fi
exit "$rc"
