#!/usr/bin/env bash
# Ставит VOICEog в автозапуск при входе — способом XDG (.desktop).
#
#   bash scripts/install-autostart.sh
# Снять:  bash scripts/install-autostart.sh --remove
#
# Почему так, а не только systemd: .desktop в ~/.config/autostart понимают
# ВСЕ основные десктопы (GNOME, KDE, XFCE, MATE, Cinnamon и др.) и на X11, и на
# Wayland, и он не требует systemd. Значит работает и на Void, Alpine, Artix.
# Хочешь service с перезапуском — он отдельно: scripts/install-service.sh.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
FILE="$DIR/voiceog.desktop"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$FILE"
  echo "[voiceog] автозапуск снят: $FILE"
  exit 0
fi

mkdir -p "$DIR"
cat >"$FILE" <<EOF
[Desktop Entry]
Type=Application
Name=VOICEog
Comment=Локальный голосовой ввод
Exec=$ROOT/voiceog
Terminal=false
X-GNOME-Autostart-enabled=true
EOF

echo "[voiceog] автозапуск поставлен: $FILE"
echo "[voiceog] снять: bash scripts/install-autostart.sh --remove"
