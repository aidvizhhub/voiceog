#!/usr/bin/env bash
# =============================================================================
# make-bundle.sh — портативный Linux-бандл VOICEog (x86_64).
#
# Рецепт «скачал tarball → распаковал → запустил ./run.sh».
# Внутри: окно voiceog-window, Node-сервер (src/, public/), prod-зависимости
# под linux-x64 (sherpa-onnx / uiohook / ffmpeg), run.sh и README.txt.
#
# Модель (скачать ~487 МБ → распакуется в ~641 МБ) НЕ вкладываем — run.sh качает
# её при первом запуске.
# Ничего не ставит в систему: системные пакеты (webkit2gtk-4.1/gtk3/
# appindicator) на целевой машине всё равно нужны окну — про них в README.txt.
#
# Запуск:
#   window/packaging/bundle/make-bundle.sh
# Результат:
#   window/target/bundle/VOICEog/                    — распакованное дерево
#   window/target/bundle/VOICEog-<в>-linux-x86_64.tar.zst  (или .tar.gz)
#
# Сборка идемпотентна: площадка каждый раз чистится с нуля, node_modules
# ставится заново через `npm ci --omit=dev`.
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"   # .../window/packaging/bundle
WINDOW_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"                  # .../window
ROOT="$(cd "$WINDOW_DIR/.." && pwd)"                           # корень проекта

VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$WINDOW_DIR/Cargo.toml" | head -1)"
VERSION="${VERSION:-0.0.0}"
ARCH="$(uname -m)"

OUT="$WINDOW_DIR/target/bundle"
STAGE="$OUT/VOICEog"
BIN="$WINDOW_DIR/target/release/voiceog-window"
NAME="VOICEog-${VERSION}-linux-${ARCH}"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
ok()  { printf '    \033[1;32m%s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!!! %s\033[0m\n' "$*" >&2; exit 1; }

# --- 0. инструменты сборки ---------------------------------------------------
log "проверяю инструменты сборки"
for t in node npm cargo; do
  command -v "$t" >/dev/null 2>&1 || die "нет '$t' в PATH"
done
[ "$ARCH" = "x86_64" ] || log "предупреждение: собираю на $ARCH, а бандл задуман под x86_64"

# --- 1. окно -----------------------------------------------------------------
# SKIP_BUILD=1 — упаковать уже собранный бинарник, cargo не звать. Полезно,
# когда окно собирают отдельно (CI) или параллельно правят исходники.
if [ "${SKIP_BUILD:-}" = "1" ]; then
  log "SKIP_BUILD=1 — беру уже собранный voiceog-window, cargo не зову"
else
  log "собираю окно (cargo build --release)"
  ( cd "$WINDOW_DIR" && cargo build --release )
fi
[ -x "$BIN" ] || die "нет бинарника $BIN (собери: cd '$WINDOW_DIR' && cargo build --release)"
ok "$(du -h "$BIN" | cut -f1)  voiceog-window"

# --- 2. чистая площадка ------------------------------------------------------
log "чищу площадку $STAGE"
rm -rf "$STAGE"
mkdir -p "$STAGE/src" "$STAGE/public" "$STAGE/scripts"

# --- 3. окно + исходники сервера --------------------------------------------
log "кладу окно и сервер"
cp -a "$BIN" "$STAGE/voiceog-window"
chmod 755 "$STAGE/voiceog-window"
cp -a "$ROOT/src/." "$STAGE/src/"
rm -rf "$STAGE/src/platform/win"        # windows-слой в linux-бандле не нужен
cp -a "$ROOT/public/." "$STAGE/public/"
cp -a "$ROOT/package.json" "$ROOT/package-lock.json" "$STAGE/"
cp -a "$ROOT/scripts/download-model.sh" "$STAGE/scripts/"
chmod 755 "$STAGE/scripts/download-model.sh"
ok "src/, public/, package*.json, scripts/download-model.sh"

# --- 4. prod-зависимости под linux-x64 (нативники — готовые бинари) ----------
log "ставлю prod-зависимости (npm ci --omit=dev)"
( cd "$STAGE" && npm ci --omit=dev --no-audit --no-fund )
[ -d "$STAGE/node_modules/sherpa-onnx-node" ] || die "sherpa-onnx-node не встал"
case "$ARCH" in
  x86_64) NEED="sherpa-onnx-linux-x64" ;;
  aarch64) NEED="sherpa-onnx-linux-arm64" ;;
  *) NEED="sherpa-onnx-linux-$ARCH" ;;
esac
[ -d "$STAGE/node_modules/$NEED" ] || die "нет нативника node_modules/$NEED — бандл не заведётся"

# ffmpeg-static весит ~77 МБ и нужен ТОЛЬКО windows-слою
# (src/platform/win/recorder.mjs), которого в linux-бандле нет. На Linux
# запись идёт через pw-record/parec/arecord, а если совсем никак — берётся
# системный ffmpeg из PATH (см. src/platform/linux/recorder.mjs). Значит, в
# linux-бандле это чистый балласт. Оставляем, только если явно попросили:
#   KEEP_FFMPEG_STATIC=1 make-bundle.sh
if [ -z "${KEEP_FFMPEG_STATIC:-}" ] && [ -d "$STAGE/node_modules/ffmpeg-static" ]; then
  rm -rf "$STAGE/node_modules/ffmpeg-static"
  ok "выкинул ffmpeg-static (windows-only, ~77 МБ)"
fi

ok "node_modules: $(du -sh "$STAGE/node_modules" | cut -f1)"

# --- 5. run.sh + README.txt --------------------------------------------------
log "кладу run.sh и README.txt"
cp -a "$SCRIPT_DIR/run.sh" "$STAGE/run.sh"
cp -a "$SCRIPT_DIR/README.txt" "$STAGE/README.txt"
chmod 755 "$STAGE/run.sh"
bash -n "$STAGE/run.sh" || die "run.sh не проходит bash -n"

# --- 6. упаковка -------------------------------------------------------------
log "упаковываю архив"
mkdir -p "$OUT"
rm -f "$OUT"/"$NAME".tar.zst "$OUT"/"$NAME".tar.gz
if command -v zstd >/dev/null 2>&1; then
  ARCHIVE="$OUT/$NAME.tar.zst"
  tar --zstd -cf "$ARCHIVE" -C "$OUT" VOICEog
  COMPRESSOR="zstd"
else
  ARCHIVE="$OUT/$NAME.tar.gz"
  tar -czf "$ARCHIVE" -C "$OUT" VOICEog
  COMPRESSOR="gzip"
fi

# --- 7. итог -----------------------------------------------------------------
log "готово"
printf '    дерево:  %s\n' "$STAGE"
printf '    архив:   %s  (%s)\n' "$ARCHIVE" "$COMPRESSOR"
printf '    распак.: %s\n' "$(du -sh "$STAGE" | cut -f1)"
printf '    сжато:   %s\n' "$(du -h "$ARCHIVE" | cut -f1)"
printf '\n    Модель не вложена — run.sh скачает её при первом запуске (скачать ~487 МБ → распакуется в ~641 МБ).\n'
