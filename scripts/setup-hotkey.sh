#!/usr/bin/env bash
# Ставит глобальный хоткей в GNOME: нажатие → «voiceog toggle».
#
#   bash scripts/setup-hotkey.sh                 # Ctrl+Alt+V по умолчанию
#   bash scripts/setup-hotkey.sh '<Super><Alt>d' # своя комбинация
#
set -euo pipefail

BINDING="${1:-<Control><Alt>v}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CMD="$ROOT/voiceog toggle"

SCHEMA="org.gnome.settings-daemon.plugins.media-keys"
KEY="/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/voiceog/"

if ! command -v gsettings >/dev/null; then
  echo "нет gsettings — это не GNOME?" >&2
  exit 1
fi

existing="$(gsettings get "$SCHEMA" custom-keybindings)"
if [[ "$existing" != *"$KEY"* ]]; then
  if [[ "$existing" == "@as []" || "$existing" == "[]" ]]; then
    new="['$KEY']"
  else
    new="${existing%]}, '$KEY']"
  fi
  gsettings set "$SCHEMA" custom-keybindings "$new"
fi

gsettings set "$SCHEMA.custom-keybinding:$KEY" name 'VOICEog — диктовка'
gsettings set "$SCHEMA.custom-keybinding:$KEY" command "$CMD"
gsettings set "$SCHEMA.custom-keybinding:$KEY" binding "$BINDING"

echo "хоткей поставлен: $BINDING → $CMD"
echo "(изменить можно в Настройки → Клавиатура → Свои комбинации)"
