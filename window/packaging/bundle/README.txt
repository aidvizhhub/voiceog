VOICEog — портативный Linux-бандл (x86_64)
==========================================

Что это
-------
Локальный голосовой ввод: одна кнопка — и текст. Распознавание идёт на твоей
машине (Parakeet TDT 0.6B v3 INT8), без облака. Внутри: нативное окно-пульт,
локальный сервер и prod-зависимости под linux-x64.

Как запустить
-------------
1. Распаковать:
       tar --zstd -xf VOICEog-*.tar.zst      # если zstd
       tar -xzf     VOICEog-*.tar.gz         # если tar.gz
2. Запустить:
       cd VOICEog
       ./run.sh

run.sh сам поднимет сервер, дождётся его и откроет окно. При первом запуске
он скачает модель (см. ниже) — только один раз, дальше она уже на месте.
Закрыл окно — сервер погаснет сам (чужой сервер, если он был, не трогается).

Другой порт:      VOICEOG_PORT=7998 ./run.sh
Другой адрес:     VOICEOG_URL=http://127.0.0.1:7998 ./run.sh
Своя папка модели: VOICEOG_MODEL=/path/к/модели ./run.sh   # пустую папку run.sh докачает сюда же

Модель НЕ входит в архив
------------------------
Модель в архиве — слишком много. При первом запуске run.sh скачает её сам
(scripts/download-model.sh): скачать ~487 МБ → распакуется в ~641 МБ.
Кладёт в папку models/, а если задан VOICEOG_MODEL — ровно в неё. Можно заранее:
       ./scripts/download-model.sh
Для скачивания нужны curl и tar.

Что нужно на машине (пакеты — в бандл не входят)
------------------------------------------------
Обязательно, иначе окно не заведётся:
  • Node.js 20 или новее      — сервер
  • webkit2gtk-4.1            — движок окна
  • gtk3                      — само окно
  • libayatana-appindicator3  — значок в трее

  Fedora:
    sudo dnf install nodejs webkit2gtk4.1 gtk3 libayatana-appindicator-gtk3
  Debian/Ubuntu:
    sudo apt install nodejs libwebkit2gtk-4.1-0 libgtk-3-0 libayatana-appindicator3-1

Для самой диктовки (запись и вставка) — что-то из этого, по системе:
  • микрофон:  pw-record (PipeWire) | parec (PulseAudio) | arecord (ALSA)
  • буфер:     wl-copy (Wayland) | xclip или xsel (X11)
  • Ctrl+V:    ydotool | dotool | wtype (Wayland), xdotool (X11)
  • хоткей:    доступ к /dev/input (группа input) — см. scripts/install-input-access.sh
  • curl, tar: ими качается модель

Чего в системе не окажется — сервер честно скажет в логе при старте.

Подробности — в README.md проекта.
