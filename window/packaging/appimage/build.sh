#!/usr/bin/env bash
# =============================================================================
# build.sh — сборка AppImage для voiceog-window (tao + wry + tray-icon).
#
# Зачем AppImage: один файл, ничего не ставит в систему — скачал, chmod +x,
# запустил. Удобно раздавать «любому Linux», не возясь с менеджерами пакетов.
#
# Рецепт (тот же, что у Tauri):
#   1. linuxdeploy + linuxdeploy-plugin-gtk собирают AppDir (тянут GTK3 и
#      зависимости по ldd, кладут AppRun, иконку и .desktop).
#   2. Поверх докладываем хелпер-процессы WebKit (WebKitNetworkProcess,
#      WebKitWebProcess, WebKitGPUProcess) и injected-bundle — они лежат вне
#      бинарника, и без них WebView на старте падает.
#   3. Патчим в libwebkit2gtk «/usr» → «././»: WebKit ищет хелперы по
#      зашитым абсолютным путям (/usr/libexec/webkit2gtk-4.1 и
#      /usr/lib64/webkit2gtk-4.1/injected-bundle), а внутри AppImage их надо
#      резолвить относительно корня AppDir.
#   4. Добавляем AppRun-хук: WEBKIT_DISABLE_DMABUF_RENDERER=1 (лечит белое
#      окно на NVIDIA/Wayland) + cd в корень AppDir, чтобы относительные пути
#      из п.3 сошлись.
#   5. appimagetool упаковывает AppDir в единый .AppImage.
#
# Сеть нужна только на первом запуске (качаем linuxdeploy/appimagetool/
# плагин gtk в target/appimage/tools). Дальше всё локально.
#
# Использование:
#   ./packaging/appimage/build.sh
# Готовый файл: target/appimage/voiceog-window-<версия>-x86_64.AppImage
# Для старых glibc (Debian 12 / Ubuntu 22.04) собирай этим скриптом ВНУТРИ
# bookworm-контейнера: packaging/appimage/build-bookworm.sh (тот же рецепт,
# но glibc 2.36 вместо хостовой Fedora 2.43). Имя файла у него с суффиксом
# -bookworm — это рекомендованный к раздаче вариант.
# =============================================================================

set -euo pipefail

# --- где мы и что собираем ---------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"   # .../window
APP="voiceog-window"
VERSION="$(sed -n 's/^version[[:space:]]*=[[:space:]]*"\(.*\)".*/\1/p' "$PROJECT_DIR/Cargo.toml" | head -1)"
VERSION="${VERSION:-0.0.0}"
ARCH="${ARCH:-x86_64}"

WORK="$PROJECT_DIR/target/appimage"
APPDIR="$WORK/AppDir"
TOOLS="$WORK/tools"
BIN="$PROJECT_DIR/target/release/$APP"

# Каталог-песочница для сборки. Чистим AppDir с нуля — иначе хвосты прошлой
# сборки могут незаметно попасть в новый образ.
rm -rf "$APPDIR"
mkdir -p "$WORK" "$APPDIR" "$TOOLS"

log() { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
die() { printf '\n\033[1;31m!!! %s\033[0m\n' "$*" >&2; exit 1; }

# --- 0. инструменты (linuxdeploy + плагин gtk + appimagetool) ----------------
LINUXDEPLOY="$TOOLS/linuxdeploy-$ARCH.AppImage"
APPIMAGETOOL="$TOOLS/appimagetool-$ARCH.AppImage"
GTK_PLUGIN="$TOOLS/linuxdeploy-plugin-gtk.sh"

fetch() { # fetch <url> <файл>
    [ -s "$2" ] && return 0
    log "качаю $(basename "$2")"
    curl -fSL --retry 3 -o "$2" "$1" || die "не скачался $1"
    chmod +x "$2"
}

fetch "https://github.com/linuxdeploy/linuxdeploy/releases/download/continuous/linuxdeploy-$ARCH.AppImage" "$LINUXDEPLOY"
fetch "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-$ARCH.AppImage" "$APPIMAGETOOL"
fetch "https://raw.githubusercontent.com/linuxdeploy/linuxdeploy-plugin-gtk/master/linuxdeploy-plugin-gtk.sh" "$GTK_PLUGIN"

# linuxdeploy и appimagetool — сами AppImage. В песочницах без рабочего FUSE
# (или когда /dev/fuse не проброшен) их гоняем через extract-and-run.
export APPIMAGE_EXTRACT_AND_RUN=1

# --- 1. бинарник -------------------------------------------------------------
log "собираю release-бинарник"
( cd "$PROJECT_DIR" && cargo build --release )
[ -x "$BIN" ] || die "нет бинарника $BIN"

# --- 2. узнаём, где в системе WebKit ----------------------------------------
# На Fedora хелперы в /usr/libexec/webkit2gtk-4.1, на Debian/Ubuntu — в
# /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1. Ищем по факту наличия.
WEBKIT_EXEC_DIR=""
for d in /usr/libexec/webkit2gtk-4.1 /usr/lib64/webkit2gtk-4.1 \
         /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1 /usr/lib/webkit2gtk-4.1; do
    if [ -x "$d/WebKitWebProcess" ]; then WEBKIT_EXEC_DIR="$d"; break; fi
done

WEBKIT_INJECTED=""
for d in /usr/lib64/webkit2gtk-4.1/injected-bundle \
         /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle \
         /usr/lib/webkit2gtk-4.1/injected-bundle \
         /usr/libexec/webkit2gtk-4.1/injected-bundle; do
    if [ -f "$d/libwebkit2gtkinjectedbundle.so" ]; then WEBKIT_INJECTED="$d"; break; fi
done

[ -n "$WEBKIT_EXEC_DIR" ] || die "не нашёл WebKitWebProcess (поставь webkit2gtk4.1 / libwebkit2gtk-4.1-dev)"
[ -n "$WEBKIT_INJECTED" ] || die "не нашёл libwebkit2gtkinjectedbundle.so"

log "хелперы WebKit: $WEBKIT_EXEC_DIR"
log "injected-bundle: $WEBKIT_INJECTED"

# --- 2b. где libappindicator (библиотека трея) ------------------------------
# tray-icon грузит appindicator через dlopen (libappindicator-sys), поэтому в
# DT_NEEDED бинарника её нет — linuxdeploy сам её не видит и не утаскивает в
# AppDir. На хосте без этой либы в трее приложение падает на старте. Поэтому
# находим её и отдаём linuxdeploy через --library: он заодно подтянет её
# зависимости (libayatana-ido3, libdbusmenu-glib/gtk3) — и все они будут
# bookworm-овой сборки, совместимые с glib из AppDir.
APPINDICATOR_LIB=""
for d in /usr/lib/x86_64-linux-gnu /usr/lib64 /usr/lib; do
    for n in libayatana-appindicator3.so.1 libappindicator3.so.1; do
        if [ -e "$d/$n" ]; then APPINDICATOR_LIB="$(readlink -f "$d/$n")"; break 2; fi
    done
done
[ -n "$APPINDICATOR_LIB" ] || die "не нашёл libayatana-appindicator3 (поставь libayatana-appindicator3-dev)"
log "appindicator: $APPINDICATOR_LIB"

# --- 3. linuxdeploy: собираем AppDir (без упаковки) --------------------------
# NO_STRIP=true обязателен на свежих Fedora/Arch/Ubuntu: встроенный в
# linuxdeploy strip не понимает секцию .relr.dyn и валит сборку.
export NO_STRIP=true
export LINUXDEPLOY="$LINUXDEPLOY"
export DEPLOY_GTK_VERSION=3
export PATH="$TOOLS:$PATH"

log "linuxdeploy: раскладываю AppDir (GTK3 + зависимости)"
"$LINUXDEPLOY" --appdir "$APPDIR" --plugin gtk \
    --executable "$BIN" \
    --library "$APPINDICATOR_LIB" \
    --desktop-file "$SCRIPT_DIR/../voiceog-window.desktop" \
    --icon-file "$SCRIPT_DIR/../icon-256.png" \
    --icon-filename voiceog-window

# --- 4. хелперы WebKit + патч путей -----------------------------------------
# Куда класть хелперы: путь зашит в libwebkit2gtk ещё при сборке дистрибутива —
# /usr/libexec/webkit2gtk-4.1 на Fedora, /usr/lib/x86_64-linux-gnu/webkit2gtk-4.1
# на Debian/Ubuntu. Чуть ниже мы патчим в библиотеке /usr → ././, поэтому класть
# хелперы надо ровно по тому же относительному пути: отрезаем ведущий /usr и
# получаем $APPDIR/libexec/... (Fedora) или $APPDIR/lib/x86_64-linux-gnu/... (Debian).
WEBKIT_EXEC_REL="${WEBKIT_EXEC_DIR#/usr}"
WEBKIT_INJECTED_REL="${WEBKIT_INJECTED#/usr}"

log "кладу хелпер-процессы WebKit ($WEBKIT_EXEC_REL)"
mkdir -p "$APPDIR$WEBKIT_EXEC_REL"
for p in WebKitNetworkProcess WebKitWebProcess WebKitGPUProcess; do
    [ -f "$WEBKIT_EXEC_DIR/$p" ] && cp -a "$WEBKIT_EXEC_DIR/$p" "$APPDIR$WEBKIT_EXEC_REL/"
done

log "кладу injected-bundle ($WEBKIT_INJECTED_REL)"
mkdir -p "$APPDIR$WEBKIT_INJECTED_REL"
cp -a "$WEBKIT_INJECTED/libwebkit2gtkinjectedbundle.so" "$APPDIR$WEBKIT_INJECTED_REL/"

log "патчу /usr → ././ в libwebkit2gtk"
# Меняем ровно 4 байта на 4 байта — бинарник не съезжает.
mapfile -t WEBKIT_LIBS < <(find "$APPDIR" -name 'libwebkit2gtk-4.1.so*' -type f)
[ "${#WEBKIT_LIBS[@]}" -gt 0 ] || die "linuxdeploy не положил libwebkit2gtk в AppDir"
for f in "${WEBKIT_LIBS[@]}"; do
    sed -i 's|/usr|././|g' "$f"
    echo "    пропатчен: ${f#"$APPDIR"/}"
done

# --- 4b. выкидываем CUPS-бэкенд печати ---------------------------------------
# Зачем: linuxdeploy тянет libcups.so.2 как зависимость printbackend'а GTK.
# На Debian 12 libcups собран с arc4random и требует GLIBC_2.36 — ровно потолок
# bookworm. Ubuntu 22.04 сидит на glibc 2.35, и этот единственный символ ломает
# запуск. Печать в пульте не нужна, поэтому вырезаем бэкенд и его зависимость:
# максимум требуемой glibc падает до 2.35, и образ заводится и на 22.04.
log "вырезаю CUPS-бэкенд печати (тянет GLIBC_2.36 на ровном месте)"
find "$APPDIR" -name 'libprintbackend-cups.so' -delete
rm -f "$APPDIR/usr/lib/libcups.so.2"
rm -rf "$APPDIR/usr/share/doc/libcups2"

# --- 4c. symlink по SONAME для appindicator ----------------------------------
# linuxdeploy кладёт --library под её настоящим именем (libayatana-appindicator3
# .so.1.0.0), а dlopen в libappindicator-sys ищет ровно «libayatana-appindicator3
# .so.1». Без symlink'а загрузчик возьмёт системную копию и словит рассинхрон
# glib. Делаем symlink по SONAME (для одной либы, но пишем обобщённо).
for f in "$APPDIR"/usr/lib/libayatana-appindicator3.so.*; do
    [ -e "$f" ] || continue
    soname="$(readelf -d "$f" 2>/dev/null | grep -o 'SONAME.*\[[^]]*\]' | sed 's/.*\[\(.*\)\]/\1/')"
    [ -n "$soname" ] && [ "$(basename "$f")" != "$soname" ] && \
        ln -sf "$(basename "$f")" "$APPDIR/usr/lib/$soname"
done

# --- 5. AppRun-хук -----------------------------------------------------------
# AppImageKit-овский AppRun сорсит apprun-hooks/*.sh, поэтому хук может и
# переменные выставить, и сделать cd для родительской оболочки.
log "пишу AppRun-хук (dmabuf off + cd в корень AppDir)"
HOOKDIR="$APPDIR/apprun-hooks"
mkdir -p "$HOOKDIR"
cat > "$HOOKDIR/voiceog-webkit.sh" <<'EOF'
#! /usr/bin/env bash
# Отключаем DMABUF-рендерер WebKit: на NVIDIA/Wayland он отдаёт белое окно
# или падает. Софт-рендер работает везде, для пульта этого хватает.
export WEBKIT_DISABLE_DMABUF_RENDERER=1
# Хелпер-процессы WebKit (WebKitWebProcess и т.п.) — отдельные бинарники, у
# которых нет rpath на usr/lib. Без этого они не найдут libwebkit2gtk и
# веб-процесс упадёт (белое окно). Поэтому кладём библиотеки в LD_LIBRARY_PATH.
export LD_LIBRARY_PATH="${APPDIR}/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# cd в корень AppDir: относительные пути ././libexec/... из патча должны
# резолвиться от него, а не от каталога, где юзер запустил AppImage.
cd "${APPDIR}" 2>/dev/null || true
EOF
# Подсказка WebKit, где искать injected-bundle внутри образа. Путь зависит от
# дистрибутива (Fedora: /lib64/...; Debian: /lib/x86_64-linux-gnu/...), поэтому
# дописываем его в хук уже из посчитанного $WEBKIT_INJECTED_REL. ВАЖНО: пишем
# литерал "${APPDIR}", а НЕ раскрытый $APPDIR — иначе в образ утечёт абсолютный
# путь сборочной машины (/work/window/target/appimage/AppDir/...), которого на
# чужой тачке нет, и WebKit его не найдёт (белое окно). ${APPDIR} AppRun
# подставляет уже при запуске, путь считается относительно корня распакованного
# AppImage. Формат printf в одинарных кавычках — ${APPDIR} остаётся как есть.
# shellcheck disable=SC2016  # ${APPDIR} тут литерал, не ошибка: AppRun раскроет его при запуске
printf 'export WEBKIT_INJECTED_BUNDLE_PATH="${APPDIR}%s"\n' \
    "$WEBKIT_INJECTED_REL" >> "$HOOKDIR/voiceog-webkit.sh"
chmod +x "$HOOKDIR/voiceog-webkit.sh"

# --- 6. упаковка в .AppImage --------------------------------------------------
OUTPUT="$WORK/${APP}-${VERSION}-${ARCH}.AppImage"
rm -f "$OUTPUT"
cd "$WORK"
export OUTPUT LDAI_OUTPUT="$OUTPUT"
log "linuxdeploy --output appimage: упаковываю в $(basename "$OUTPUT")"
# linuxdeploy на выходе дёргает linuxdeploy-plugin-appimage (обёртка над
# appimagetool). Если он почему-то не сработал — падаем на голый appimagetool.
if ! ARCH="$ARCH" "$LINUXDEPLOY" --appdir "$APPDIR" --output appimage; then
    log "linuxdeploy-плагин appimage не сработал — зову appimagetool напрямую"
    ARCH="$ARCH" "$APPIMAGETOOL" "$APPDIR" "$OUTPUT"
fi

log "готово"
ls -la "$OUTPUT"
