#!/usr/bin/env bash
# Даёт VOICEog доступ к железу ввода — один раз, потом живёт само.
#
#   bash scripts/install-input-access.sh
#
# Два разных доступа:
#   /dev/input/event* — читать клавиатуру. Нужен хоткею и режиму удержания
#                       (держишь — говоришь — отпустил).
#   /dev/uinput       — слать синтетические нажатия. Нужен ydotool/dotool,
#                       чтобы нажать Ctrl+V при вставке текста.
#
# Идемпотентно: чего уже есть — не трогаем, недостающее дописываем.
# Требует sudo (один раз).
set -euo pipefail

RULE=/etc/udev/rules.d/70-voiceog-input.rules

echo "[voiceog] доступ к устройствам ввода..."

need_input=1
need_uinput=1
if [ -f "$RULE" ]; then
  grep -q 'KERNEL=="event\*"' "$RULE" && need_input=0
  grep -q 'KERNEL=="uinput"' "$RULE" && need_uinput=0
fi

if [ "$need_input" = 0 ] && [ "$need_uinput" = 0 ]; then
  echo "[voiceog] правила уже есть: $RULE"
else
  sudo tee "$RULE" >/dev/null <<'EOF'
# VOICEog: можно читать клавиатуру (хоткей, режим удержания).
SUBSYSTEM=="input", KERNEL=="event*", TAG+="uaccess"

# VOICEog: можно слать синтетические нажатия (ydotool/dotool, вставка Ctrl+V).
KERNEL=="uinput", SUBSYSTEM=="misc", OPTIONS+="static_node=uinput", GROUP="input", MODE="0660", TAG+="uaccess"
EOF
  sudo udevadm control --reload-rules
  sudo udevadm trigger --subsystem-match=input
  sudo udevadm trigger --subsystem-match=misc
  echo "[voiceog] правила поставлены: $RULE"
fi

# Группа input — страховка на случай, если uaccess не сработал.
if id -nG "$USER" | tr ' ' '\n' | grep -qx input; then
  echo "[voiceog] $USER уже в группе input"
else
  sudo usermod -aG input "$USER"
  echo "[voiceog] $USER добавлен в группу input (подхватится после перелогина)"
fi

echo "[voiceog] готово — хоткей и удержание доступны."
