#!/usr/bin/env bash
# Даёт VOICEog доступ к клавиатуре напрямую (/dev/input) — нужно для режима
# удержания: GNOME-хоткей «отпускание» не отдаёт, а evdev отдаёт.
#
#   bash scripts/install-input-access.sh
#
# Идемпотентно: если правило и группа уже на месте — просто скажет об этом.
# Требует sudo (один раз).
set -euo pipefail

RULE=/etc/udev/rules.d/70-voiceog-input.rules

echo "[voiceog] доступ к /dev/input..."

# 1) udev-правило uaccess: даёт читать event-устройства активной сессии.
#    Работает сразу, без перелогина.
if [ ! -f "$RULE" ]; then
  sudo tee "$RULE" >/dev/null <<'EOF'
# VOICEog: доступ к клавиатурным event-устройствам для активной сессии.
# Нужно для режима удержания и хоткея через evdev.
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=input
  echo "[voiceog] правило поставлено: $RULE"
else
  echo "[voiceog] правило уже есть: $RULE"
fi

# 2) группа input — страховка (на случай, если uaccess почему-то не сработал).
if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
  echo "[voiceog] $USER уже в группе input"
else
  sudo usermod -aG input "$USER"
  echo "[voiceog] $USER добавлен в группу input (подхватится после перелогина)"
fi

echo "[voiceog] готово — режим удержания доступен."
