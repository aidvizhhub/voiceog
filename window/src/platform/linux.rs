// Linux-ветка: окно и вебвью строятся поверх GTK (webkit2gtk).

use gtk::prelude::GtkWindowExt;
use tao::platform::unix::WindowExtUnix;
use tao::window::Window;
use wry::{WebView, WebViewBuilder, WebViewBuilderExtUnix};

/// Готовим окружение WebKitGTK до инициализации GTK. Всё решается тут, в одном
/// месте, ровно один раз на старте.
///
/// Исторически мы просто гасили DMABUF-рендерер (`WEBKIT_DISABLE_DMABUF_RENDERER=1`):
/// на NVIDIA+Wayland он валил окно ошибкой «Gdk-Message: Error 71 ... dispatching
/// to Wayland display». Цена — отрисовка уходила на CPU, и окно лагучу. Живой
/// тест на GTX 1660 + NVIDIA 615 + Wayland показал: DMABUF-рендерер реально
/// заводится на GPU, если к нему добавить `__NV_DISABLE_EXPLICIT_SYNC=1`
/// (снимает explicit-sync/EDID-протокол, который проприетарный драйвер и
/// Wayland не тянут). Тогда WebKit-процесс сидит на `/dev/dri/renderD128`.
///
/// Логика:
///   1. `VOICEOG_DISABLE_DMABUF=1` — аварийная ручка. Наша сборка/драйвер
///      снова сломались — возвращаем старый проверенный CPU-режим.
///   2. NVIDIA-proprietary — гоняем по-разному в зависимости от того, куда
///      реально рисуем:
///        • нативный Wayland — включаем GPU: DMABUF on + обход explicit-sync.
///        • X11/XWayland — принудительный CPU. Тут DMABUF держится на GBM
///          (Generic Buffer Management — механизм аллокации/шаринга GPU-буферов
///          через DRM). Вебкит пробует собрать GBM-буфер, но связка
///          XWayland + проприетарный NVIDIA его не тянет: `Failed to create GBM
///          buffer of size ...`, и рендерер тихо валится обратно в CPU — то есть
///          GPU нет, но лог срётся ошибками. Убираем иллюзию: сразу CPU.
///   3. Не-NVIDIA (AMD/Intel/nouveau) — ничего не трогаем: дефолты WebKit там
///      рабочие, лезть со своими флагами только вредить.
///
/// Что задали снаружи (в env) — уважаем и не перетираем: юзер/дистрибутив
/// всегда прав.
pub fn prepare_environment() {
    // 1. Аварийный фолбэк в CPU-режим: `VOICEOG_DISABLE_DMABUF=1`.
    if std::env::var("VOICEOG_DISABLE_DMABUF").as_deref() == Ok("1") {
        if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
            // SAFETY: до инициализации GTK/потоков — гонок нет, это самый старт main.
            unsafe { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1") };
        }
        return;
    }

    // 2. Проприетарный NVIDIA: модуль ядра nvidia.
    let nvidia_proprietary = std::path::Path::new("/sys/module/nvidia").exists();
    if !nvidia_proprietary {
        // 3. AMD/Intel/nouveau — ничего не трогаем, дефолты WebKit рабочие.
        return;
    }

    // Куда рисуем: нативный Wayland или X11/XWayland.
    // `GDK_BACKEND=x11` — принудительный X11-путь (в т.ч. XWayland под
    // Wayland-сессией), смотрим по наличию подстроки, а не по точному равенству:
    // там бывает "x11,wayland" через запятую.
    let forced_x11 = std::env::var("GDK_BACKEND")
        .map(|v| v.to_ascii_lowercase().contains("x11"))
        .unwrap_or(false);

    let session_type = std::env::var("XDG_SESSION_TYPE").unwrap_or_default();
    let session_wayland = session_type.eq_ignore_ascii_case("wayland");
    let session_x11 = session_type.eq_ignore_ascii_case("x11");
    let has_wayland_display = std::env::var_os("WAYLAND_DISPLAY").is_some();

    // Нативный Wayland: не форсим X11 и сессия Wayland (по XDG_SESSION_TYPE
    // либо по WAYLAND_DISPLAY).
    let native_wayland = !forced_x11 && (session_wayland || has_wayland_display);
    // X11/XWayland: форсим X11 через GDK_BACKEND или сессия X11.
    let on_x11 = forced_x11 || session_x11;

    if native_wayland {
        if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
            // "0" — явно разрешаем DMABUF: рендер уедет на GPU.
            // SAFETY: до инициализации GTK/потоков — гонок нет.
            unsafe { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "0") };
        }
        if std::env::var_os("__NV_DISABLE_EXPLICIT_SYNC").is_none() {
            // Обход explicit-sync: без него NVIDIA+Wayland валит WebKit
            // ошибкой Error 71 (см. шапку). С ним DMABUF-рендерер живёт.
            // SAFETY: до инициализации GTK/потоков — гонок нет.
            unsafe { std::env::set_var("__NV_DISABLE_EXPLICIT_SYNC", "1") };
        }
        return;
    }

    if on_x11 {
        if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
            // CPU-режим: на X11/XWayland + NVIDIA GBM-буфер не создаётся
            // (`Failed to create GBM buffer ...`), DMABUF всё равно падает в
            // CPU-фолбэк, только с вонью в stderr. Гасим его сразу.
            // SAFETY: до инициализации GTK/потоков — гонок нет.
            unsafe { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1") };
        }
        return;
    }

    // NVIDIA, но вид сессии не распознали — не гадаем, оставляем дефолты.
}

/// wry на Linux строится в GTK-контейнер окна tao (default_vbox).
pub fn build_webview<'a>(
    window: &'a Window,
    builder: WebViewBuilder<'a>,
) -> wry::Result<WebView> {
    let vbox = window.default_vbox().unwrap();
    builder.build_gtk(vbox)
}

/// Показать окно и поднять с фокусом.
///
/// `window.set_focus()` на Linux ненадёжен: tao молча выходит, если GTK ещё не
/// успел применить `set_visible` (запрос идёт в очередь glib), а focus stealing
/// prevention фокус всё равно не даёт. `gtk_window().present()` — канонический
/// путь (так чинит сам Tauri в issue #6310): и поднимает, и фокусит.
pub fn present_window(window: &Window) {
    window.gtk_window().present();
}

/// Открыть ссылку во внешнем браузере через xdg-open.
pub fn open_external(url: &str) {
    let _ = std::process::Command::new("xdg-open").arg(url).spawn();
}
