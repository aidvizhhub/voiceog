#!/usr/bin/env bash
# Качает локальную модель распознавания (Parakeet TDT 0.6B v3 INT8).
# Качается ~487 МБ, на диске распакуется в ~641 МБ.
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${NAME}.tar.bz2"

# Куда класть модель — это папка, в которой должен оказаться tokens.txt.
#   без переменной        → models/<NAME>  (как велось и раньше)
#   VOICEOG_MODEL=/путь   → ровно эта папка (своя модель, см. run.sh)
DEST="${VOICEOG_MODEL:-models/$NAME}"
PARENT="$(dirname "$DEST")"

if [ -f "$DEST/tokens.txt" ]; then
  echo "уже на месте: $DEST"
  exit 0
fi

mkdir -p "$PARENT"
ARCHIVE="$PARENT/${NAME}.tar.bz2"

echo "качаю $NAME (~487 МБ, распакуется в ~641 МБ)..."
curl -L --progress-bar -C - -o "$ARCHIVE" "$URL"

echo "распаковываю..."
tar xjf "$ARCHIVE" -C "$PARENT"
rm -f "$ARCHIVE"

# Архив разворачивается в подпапку <NAME>/. Если DEST называется иначе —
# переносим содержимое туда, чтобы tokens.txt лёг ровно в DEST.
if [ ! -f "$DEST/tokens.txt" ] && [ -f "$PARENT/$NAME/tokens.txt" ]; then
  mkdir -p "$DEST"
  cp -a "$PARENT/$NAME/." "$DEST/"
  [ "$DEST" = "$PARENT/$NAME" ] || rm -rf "${PARENT:?}/$NAME"
fi

echo "готово: $DEST"
