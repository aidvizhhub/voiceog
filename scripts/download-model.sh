#!/usr/bin/env bash
# Качает локальную модель распознавания (Parakeet TDT 0.6B v3 INT8, ~487 МБ).
set -euo pipefail
cd "$(dirname "$0")/.."

NAME="sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
URL="https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models/${NAME}.tar.bz2"
DEST="models";

mkdir -p "$DEST"
cd "$DEST"

if [ -d "$NAME" ] && [ -f "$NAME/tokens.txt" ]; then
  echo "уже на месте: $DEST/$NAME"
  exit 0
fi

echo "качаю $NAME (~487 МБ)..."
curl -L --progress-bar -C - -o "${NAME}.tar.bz2" "$URL"

echo "распаковываю..."
tar xjf "${NAME}.tar.bz2"
rm -f "${NAME}.tar.bz2"

echo "готово: $DEST/$NAME"
