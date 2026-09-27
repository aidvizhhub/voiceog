#!/usr/bin/env bash
# =============================================================================
# build-bookworm.sh — собрать voiceog-window.AppImage в контейнере
# debian:bookworm (glibc 2.36), чтобы образ заводился на старых glibc
# (Debian 12 и, после вырезания CUPS, даже Ubuntu 22.04 с glibc 2.35).
#
# ЗАЧЕМ ЭТО ВООБЩЕ:
#   AppImage надо собирать на САМОЙ СТАРОЙ целевой системе. Fedora 44 тащит
#   glibc 2.43 — такой образ на Debian 12 не запустится (словит «version
#   `GLIBC_2.43' not found»). Поэтому бинарник и все системные либы собираем в
#   контейнере с bookworm, а не на текущей системе. Обычный build.sh (сборка
#   на хосте) остаётся как есть — этот скрипт его не трогает и на хосте ничего
#   не ставит.
#
# ЧТО ДЕЛАЕТ:
#   Поднимает bookworm (podman/docker), ставит тулчейн и системные зависимости
#   wry/gtk, ставит rustup, копирует исходники в /work/window, гоняет РОДНОЙ
#   packaging/appimage/build.sh и вытаскивает готовый .AppImage в target/appimage.
#
# КАК ЗАПУСКАТЬ:
#   ./packaging/appimage/build-bookworm.sh
#   (или из любого cwd: bash /путь/к/VOICEog/window/packaging/appimage/build-bookworm.sh)
#
#   DRY_RUN=1 ./packaging/appimage/build-bookworm.sh   # печатает команды, не запускает контейнер
#
# НАСТРОЙКИ ЧЕРЕЗ ENV:
#   PROJECT_DIR  — каталог window (по умолчанию вычисляется от самого скрипта)
#   OUT_DIR      — куда класть готовый .AppImage (по умолчанию target/appimage)
#   IMAGE        — образ контейнера (docker.io/library/debian:bookworm)
#   NAME         — имя контейнера (voiceog-bookworm-build)
#   RT           — runtime: podman или docker (по умолчанию ищется сам)
#   ARCH/SUFFIX  — архитектура и суффикс имени файла
# =============================================================================
set -euo pipefail

# --- где мы, что собираем ----------------------------------------------------
# Корень проекта считаем от самого скрипта, без абсолютных путей: скрипт можно
# положить в любой каталог и звать из любого cwd.
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$SCRIPT_DIR/../.." && pwd)}"   # .../window
OUT_DIR="${OUT_DIR:-$PROJECT_DIR/target/appimage}"
IMAGE="${IMAGE:-docker.io/library/debian:bookworm}"
NAME="${NAME:-voiceog-bookworm-build}"
VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$PROJECT_DIR/Cargo.toml" | head -1)"
VERSION="${VERSION:-0.0.0}"
ARCH="${ARCH:-x86_64}"
SUFFIX="${SUFFIX:-bookworm}"
DRY_RUN="${DRY_RUN:-0}"

# podman в приоритете, docker — запасной. В dry-run не падаем, если рантайма
# нет: нам важно только напечатать команды.
RT="${RT:-$(command -v podman || command -v docker || true)}"
if [ -z "$RT" ]; then
    if [ "$DRY_RUN" = 1 ]; then RT="podman"; else echo "нет podman/docker" >&2; exit 1; fi
fi

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }

# Обёртка над рантаймом: при DRY_RUN печатает команду, иначе исполняет.
run_rt() {
    if [ "$DRY_RUN" = 1 ]; then
        printf '  [dry-run] %s' "$RT"
        printf ' %q' "$@"
        printf '\n'
    else
        "$RT" "$@"
    fi
}

cleanup() { "$RT" rm -f "$NAME" >/dev/null 2>&1 || true; }
[ "$DRY_RUN" = 1 ] || trap cleanup EXIT

log "поднимаю $IMAGE как $NAME (runtime: $RT)"
run_rt rm -f "$NAME"
run_rt run -d --name "$NAME" "$IMAGE" sleep infinity

log "apt: системные зависимости сборки (webkit2gtk-4.1, gtk3, appindicator, soup3)"
APT_SCRIPT='
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -qq
  apt-get install -y --no-install-recommends \
    libwebkit2gtk-4.1-dev libgtk-3-dev libayatana-appindicator3-dev \
    libsoup-3.0-dev libjavascriptcoregtk-4.1-dev pkg-config build-essential \
    clang lld curl file wget ca-certificates libfuse2 libxdo-dev \
    libgdk-pixbuf2.0-bin xz-utils
  # Debian кладёт gdk-pixbuf-query-loaders вне PATH — linuxdeploy-plugin-gtk
  # ищет его по имени, поэтому даём symlink.
  ln -sf /usr/lib/x86_64-linux-gnu/gdk-pixbuf-2.0/gdk-pixbuf-query-loaders \
         /usr/local/bin/gdk-pixbuf-query-loaders
'
run_rt exec "$NAME" bash -c "$APT_SCRIPT"

log "rustup (свежий Rust для edition 2024 / wry 0.57)"
RUSTUP_SCRIPT='
  curl -fsSL https://sh.rustup.rs -o /tmp/rustup-init.sh
  sh /tmp/rustup-init.sh -y --profile minimal --default-toolchain stable >/dev/null
'
run_rt exec "$NAME" bash -c "$RUSTUP_SCRIPT"

log "копирую исходники в контейнер (без target/)"
run_rt exec "$NAME" mkdir -p /work/window
for item in Cargo.toml Cargo.lock src packaging; do
    [ -e "$PROJECT_DIR/$item" ] || { echo "нет $PROJECT_DIR/$item" >&2; exit 1; }
    run_rt cp "$PROJECT_DIR/$item" "$NAME:/work/window/"
done

log "сборка AppImage (cargo build + linuxdeploy + appimagetool)"
# $HOME должен раскрыться В НУТРИ контейнера, а не на хосте — поэтому кавычки
# одинарные, и shellcheck тут ругается зря.
# shellcheck disable=SC2016
run_rt exec "$NAME" bash -lc 'source $HOME/.cargo/env; cd /work/window && ./packaging/appimage/build.sh'

log "вытаскиваю .AppImage"
OUT="$OUT_DIR/voiceog-window-${VERSION}-${ARCH}-${SUFFIX}.AppImage"
if [ "$DRY_RUN" = 1 ]; then
    printf '  [dry-run] mkdir -p %q\n' "$OUT_DIR"
    printf '  [dry-run] cp %s:%s %q\n' "$NAME" \
        "/work/window/target/appimage/voiceog-window-${VERSION}-${ARCH}.AppImage" "$OUT"
else
    mkdir -p "$OUT_DIR"
    "$RT" cp "$NAME:/work/window/target/appimage/voiceog-window-${VERSION}-${ARCH}.AppImage" "$OUT"
fi

log "готово: $OUT"
[ "$DRY_RUN" = 1 ] || ls -la "$OUT"
