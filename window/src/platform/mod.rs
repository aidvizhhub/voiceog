// Платформенный слой voiceog-window.
//
// Общая логика (трей, меню, события, иконка, URL) живёт в main.rs и ничего не
// знает про Linux/Windows. Сюда вынесено только то, что реально отличается:
// как построить вебвью и как показать/поднять окно, как открыть ссылку в
// системном браузере и какие переменные окружения выставить до старта GUI.

#[cfg(unix)]
mod linux;
#[cfg(unix)]
pub use linux::{build_webview, open_external, prepare_environment, present_window};

#[cfg(windows)]
mod windows;
#[cfg(windows)]
pub use windows::{build_webview, open_external, prepare_environment, present_window};
