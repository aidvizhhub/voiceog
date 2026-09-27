// Windows-ветка: окно tao + системный WebView2 (Edge/Chromium), без GTK.

use tao::window::Window;
use wry::{WebView, WebViewBuilder};

/// На Windows специального препа окружения не нужно: WebView2 не страдает
/// Wayland-болячками. Оставляем точку входа ради общего API платформы.
pub fn prepare_environment() {}

/// На Windows вебвью строится прямо в окно tao (HasWindowHandle) — без vbox.
pub fn build_webview<'a>(
    window: &'a Window,
    builder: WebViewBuilder<'a>,
) -> wry::Result<WebView> {
    builder.build(window)
}

/// Показать окно и дать ему фокус. Тут `set_focus()` — штатный путь.
pub fn present_window(window: &Window) {
    window.set_focus();
}

/// Открыть ссылку во внешнем браузере. Пустой "" после `start` — это заголовок
/// окна (иначе `start` принимает первый URL за title и ничего не открывает).
pub fn open_external(url: &str) {
    let _ = std::process::Command::new("cmd")
        .args(["/C", "start", "", url])
        .spawn();
}
