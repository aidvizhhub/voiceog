#!/usr/bin/env bash
# verify-sidecar.sh — проверить, что Windows-sidecar собран целиком.
#
# Смотрит на папку win-sidecar и говорит, чего не хватает:
#   * node.exe            — портативный Node, обязан быть PE32+ (не Linux-ELF);
#   * нативники win32-x64 — sherpa (sherpa-onnx.node + onnxruntime.dll),
#                           uiohook (prebuilds/win32-x64/*.node), ffmpeg.exe;
#   * серверные файлы     — src/server.mjs, public/index.html, package.json;
#   * модель              — models/sherpa-...-int8/tokens.txt. Необязательна:
#                           при WITH_MODEL=0 её и не должно быть (качается при
#                           первом старте), поэтому отсутствие модели — обычно
#                           предупреждение, а не дыра. Дырой оно становится
#                           только при явном WITH_MODEL=1.
#
# Ничего не качает и не собирает — только проверяет. Код возврата: 0 = всё ок,
# 1 = есть дыры (список в отчёте). Предупреждения код не меняют.
#
# Ручки:
#   первый аргумент или VOICEOG_SIDECAR_DIR=<путь>  — что проверять
#   (по умолчанию window/target/win-sidecar)
#   WITH_MODEL=1 — считать отсутствие модели дырой (по умолчанию — только warn)
#
# Запуск:  window/packaging/windows/sidecar/verify-sidecar.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
PROJECT="$(cd "$HERE/../../../.." && pwd)"
SIDECAR="${1:-${VOICEOG_SIDECAR_DIR:-$PROJECT/window/target/win-sidecar}}"

if [ -t 1 ]; then G=$'\033[32m'; R=$'\033[31m'; Y=$'\033[33m'; N=$'\033[0m'; else G=""; R=""; Y=""; N=""; fi

OK=0
MISSING=()
BROKEN=()
WARN=()

ok()     { printf '  %s[ok]%s  %s\n' "$G" "$N" "$*"; OK=$((OK + 1)); }
absent() { printf '  %s[нет]%s %s\n' "$R" "$N" "$*"; MISSING+=("$*"); }
suspect(){ printf '  %s[!!]%s  %s\n' "$Y" "$N" "$*"; BROKEN+=("$*"); }
warn()   { printf '  %s[!]%s  %s\n' "$Y" "$N" "$*"; WARN+=("$*"); }

# Первые два байта «MZ» = PE-файл (exe/dll/node-аддон под Windows).
is_pe() { [ -f "$1" ] && [ "$(head -c2 "$1" 2>/dev/null)" = "MZ" ]; }

rel() { printf '%s' "${1#"$SIDECAR"/}"; }

printf '[sidecar] проверяю: %s\n\n' "$SIDECAR"
if [ ! -d "$SIDECAR" ]; then
  printf '  %s[нет]%s %s\n' "$R" "$N" "папки нет вообще"
  echo
  echo "sidecar не собран. На Linux сначала: provision.sh, потом на Windows: build-node-modules.ps1"
  exit 1
fi

# --- node.exe --------------------------------------------------------------
echo "node.exe:"
NODE="$SIDECAR/node.exe"
if [ -f "$NODE" ]; then
  if is_pe "$NODE"; then
    if command -v file >/dev/null 2>&1; then
      DESC="$(file -b "$NODE")"
      case "$DESC" in
        *PE32*) ok "node.exe — $DESC ($(du -h "$NODE" | cut -f1))" ;;
        *)      suspect "node.exe — не PE32+: $DESC" ;;
      esac
    else
      ok "node.exe — PE-заголовок MZ ($(du -h "$NODE" | cut -f1))"
    fi
  else
    suspect "node.exe есть, но это НЕ PE-файл (не начинается с MZ)"
  fi
else
  absent "node.exe — прогони provision.sh"
fi

# --- нативники -------------------------------------------------------------
echo
echo "нативные модули (win32-x64):"

check_native() {
  local p="$1" label="$2"
  if [ ! -e "$p" ]; then absent "$(rel "$p")  — $label"; return; fi
  if is_pe "$p"; then ok "$(rel "$p")  — $label"; else suspect "$(rel "$p") — не PE (собран не под Windows?)"; fi
}

check_native "$SIDECAR/node_modules/sherpa-onnx-win-x64/sherpa-onnx.node"      "распознавание речи"
check_native "$SIDECAR/node_modules/sherpa-onnx-win-x64/onnxruntime.dll"       "ONNX Runtime рядом с sherpa"
check_native "$SIDECAR/node_modules/ffmpeg-static/ffmpeg.exe"                  "запись микрофона (dshow)"

UIO="$SIDECAR/node_modules/uiohook-napi/prebuilds/win32-x64"
UIO_NODE="$(find "$UIO" -maxdepth 1 -name '*.node' -print -quit 2>/dev/null)"
if [ -n "$UIO_NODE" ]; then
  if is_pe "$UIO_NODE"; then ok "$(rel "$UIO_NODE")  — глобальный хоткей"; else suspect "$(rel "$UIO_NODE") — не PE"; fi
else
  absent "node_modules/uiohook-napi/prebuilds/win32-x64/*.node  — глобальный хоткей"
fi

# --- серверные файлы --------------------------------------------------------
echo
echo "сервер:"
SRV=(
  "src/server.mjs|точка входа сервера"
  "src/stt.mjs|обвязка распознавания"
  "public/index.html|морда"
  "package.json|манифест (type: module)"
)
for item in "${SRV[@]}"; do
  p="${item%%|*}"; label="${item#*|}"
  if [ -f "$SIDECAR/$p" ]; then ok "$p  — $label"; else absent "$p  — $label"; fi
done

# --- модель (необязательна) -------------------------------------------------
# В репу модель не входит (models/ в .gitignore, ~641 МБ). В sidecar её кладёт
# build-node-modules.ps1, если models/ есть в корне проекта. Для сборки с
# WITH_MODEL=1 она обязана быть; при WITH_MODEL=0 не нужна (скачается при первом
# старте). Поэтому тут предупреждение, а ошибкой отсутствие модели становится
# только при явном WITH_MODEL=1.
echo
echo "модель распознавания:"
MODEL="$SIDECAR/models/sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
if [ -f "$MODEL/tokens.txt" ]; then
  ok "models/$(basename "$MODEL")  — $(du -sh "$MODEL" 2>/dev/null | cut -f1)"
elif [ "${WITH_MODEL:-}" = "1" ]; then
  absent "models/$(basename "$MODEL")  — WITH_MODEL=1, а модели в sidecar нет"
else
  warn "модели нет — ок для WITH_MODEL=0 (скачается при старте); для WITH_MODEL=1 положи models/ в корень проекта и прогони build-node-modules.ps1"
fi

# --- итог ------------------------------------------------------------------
echo
printf '[sidecar] итог: ок=%d, не хватает=%d, подозрительных=%d, предупреждений=%d\n' "$OK" "${#MISSING[@]}" "${#BROKEN[@]}" "${#WARN[@]}"

if [ "${#MISSING[@]}" -gt 0 ]; then
  echo
  echo "Чего не хватает:"
  for m in "${MISSING[@]}"; do echo "  - $m"; done
fi
if [ "${#BROKEN[@]}" -gt 0 ]; then
  echo
  echo "Подозрительное (не PE — похоже, собрано не на Windows):"
  for b in "${BROKEN[@]}"; do echo "  - $b"; done
fi
if [ "${#WARN[@]}" -gt 0 ]; then
  echo
  echo "Предупреждения (на сборку не влияют):"
  for w in "${WARN[@]}"; do echo "  - $w"; done
fi

if [ "${#MISSING[@]}" -gt 0 ] || [ "${#BROKEN[@]}" -gt 0 ]; then
  echo
  echo "Sidecar НЕ готов к упаковке. На Linux нет win-нативников — это норма;"
  echo "их собирает build-node-modules.ps1 на Windows/CI."
  exit 1
fi

echo
echo "Sidecar готов: node.exe + win-нативники + серверные файлы на месте."
