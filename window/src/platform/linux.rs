// Linux-ветка: окно и вебвью строятся поверх GTK (webkit2gtk).

use gtk::prelude::GtkWindowExt;
use tao::platform::unix::WindowExtUnix;
use tao::window::Window;
use wry::{WebView, WebViewBuilder, WebViewBuilderExtUnix};

/// Гасим DMABUF-рендерер WebKitGTK до старта GTK. На Wayland (особенно с
/// NVIDIA/некоторыми драйверами) он валит окно ошибкой «Gdk-Message: Error 71
/// ... dispatching to Wayland display». Если переменную уже задали снаружи —
/// уважаем её и не трогаем.
pub fn prepare_environment() {
    if std::env::var_os("WEBKIT_DISABLE_DMABUF_RENDERER").is_none() {
        // SAFETY: до инициализации GTK/потоков — гонок нет, это самый старт main.
        unsafe { std::env::set_var("WEBKIT_DISABLE_DMABUF_RENDERER", "1") };
    }
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
