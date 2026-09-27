#!/usr/bin/env bash
# Ставит ОКНО VOICEog в автозапуск при входе в систему.
#
#   bash scripts/install-window-autostart.sh          — поставить
#   bash scripts/install-window-autostart.sh --remove — снять
#
# Почему .desktop, а не systemd: файл в ~/.config/autostart понимают все
# основные рабочие столы (GNOME, KDE, XFCE и т.д.) и на X11, и на Wayland,
# и он не требует systemd. Запускаем через scripts/run-window.sh — тот сам
# поднимет сервер, если его ещё нет, и погасит только свой.
#
# Есть также systemd-вариант — см. docs/voiceog-window.service (нет env-грабель).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DIR="${XDG_CONFIG_HOME:-$HOME/.config}/autostart"
FILE="$DIR/voiceog-window.desktop"
OLD="$DIR/voiceog.desktop"

# Иконка: сначала из упаковки, потом запасная из assets.
ICON="$ROOT/window/packaging/icon-256.png"
[ -f "$ICON" ] || ICON="$ROOT/assets/morda-light.png"

if [ "${1:-}" = "--remove" ]; then
  rm -f "$FILE"
  echo "[voiceog] автозапуск окна снят: $FILE"
  exit 0
fi

mkdir -p "$DIR"
cat >"$FILE" <<EOF
[Desktop Entry]
Type=Application
Name=VOICEog
Comment=Окно-пульт VOICEog: покажет морду и поднимет сервер, если он не запущен
Exec=$ROOT/scripts/run-window.sh
Icon=$ICON
Terminal=false
Categories=Utility;
X-GNOME-Autostart-enabled=true
EOF

echo "[voiceog] автозапуск окна поставлен: $FILE"

# Если стоит старый автозапуск только сервера (voiceog.desktop), при входе будет
# гонка: и он, и run-window.sh кинутся поднимать сервер на один порт. Один упадёт.
# Не удаляем молча — предупреждаем.
if [ -f "$OLD" ]; then
  echo
  echo "[voiceog] ВНИМАНИЕ: есть ещё автозапуск только сервера: $OLD"
  echo "[voiceog] Вместе они при входе могут толкаться за порт. Лучше снять старый:"
  echo "           bash scripts/install-autostart.sh --remove"
fi

echo "[voiceog] снять: bash scripts/install-window-autostart.sh --remove"
