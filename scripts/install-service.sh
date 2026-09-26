#!/usr/bin/env bash
# Ставит VOICEog автозапуском (systemd --user), чтобы хоткей работал всегда.
#   bash scripts/install-service.sh
# Снять:  systemctl --user disable --now voiceog
#
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
NODE="$(command -v node)"
UNIT_DIR="$HOME/.config/systemd/user"
UNIT="$UNIT_DIR/voiceog.service"

case "$(uname -m)" in
  x86_64) LIB="sherpa-onnx-linux-x64" ;;
  aarch64) LIB="sherpa-onnx-linux-arm64" ;;
  *) LIB="sherpa-onnx-linux-$(uname -m)" ;;
esac

mkdir -p "$UNIT_DIR"
cat >"$UNIT" <<EOF
[Unit]
Description=VOICEog — локальный голосовой ввод
After=graphical-session.target pipewire.service
PartOf=graphical-session.target

[Service]
Type=simple
WorkingDirectory=$ROOT
Environment=LD_LIBRARY_PATH=$ROOT/node_modules/$LIB
ExecStart=$NODE $ROOT/src/server.mjs
Restart=on-failure

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now voiceog
sleep 1
systemctl --user --no-pager status voiceog | head -12

echo
echo "Для режима удержания (hold) нужен доступ к клавиатуре — один раз:"
echo "  bash scripts/install-input-access.sh"
