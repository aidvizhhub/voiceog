// voiceog-window — нативное окно-пульт для VOICEog.
//
// Не переизобретает морду: в окне живёт тот же локальный веб-интерфейс, что
// отдаёт Node-сервер VOICEog (public/index.html). Нужен, чтоб пульт жил отдельным
// окном и в трее, а не вкладкой браузера.
//
// Собрано на tao (окно и цикл событий) + wry (системный WebView) + tray-icon
// (иконка в трее). Chromium внутрь не тащим — рендерит системный браузерный
// движок: webkit2gtk на Linux, WebView2 (Edge/Chromium) на Windows.
// Платформенные различия вынесены в src/platform (см. mod platform).
//
// Окно — «пульт»: сам сервер не поднимает, только показывает уже запущенный
// (по умолчанию http://127.0.0.1:7777). Адрес переопределяется VOICEOG_URL /
// VOICEOG_PORT, а белый список навигации считается от того же адреса.
//
// Плюс single-instance: второй запуск не открывает новое окно, а поднимает уже
// живое (через D-Bus) и выходит — см. mod single_instance.

// В release-сборке под Windows это GUI-приложение: чёрная консоль не открывается.
// В debug оставляем консоль — туда идут логи. На Linux/через xwin не влияет.
#![cfg_attr(all(windows, not(debug_assertions)), windows_subsystem = "windows")]

mod platform;
mod single_instance;

use tao::dpi::LogicalSize;
use tao::event::{Event, StartCause, WindowEvent};
use tao::event_loop::{ControlFlow, EventLoopBuilder};
use tao::window::{Window, WindowBuilder};
use tray_icon::{
    menu::{Menu, MenuEvent, MenuItem, PredefinedMenuItem},
    Icon, TrayIcon, TrayIconBuilder, TrayIconEvent,
};
use wry::{WebView, WebViewBuilder};

/// Адрес морды — тот же, что у сервера. Меняется через VOICEOG_URL / VOICEOG_PORT.
fn voiceog_url() -> String {
    if let Ok(u) = std::env::var("VOICEOG_URL") {
        return u;
    }
    let port = std::env::var("VOICEOG_PORT").unwrap_or_else(|_| "7777".into());
    format!("http://127.0.0.1:{port}/")
}

/// Выделить origin (схема + host[:port]) из адреса морды. Именно origin — та
/// граница, за которую навигации уходить нельзя: путь/параметры/якорь свои,
/// а хост и порт должны совпадать. Для `http://127.0.0.1:7998/` вернёт
/// `http://127.0.0.1:7998`. Если схемы нет (`about:blank`, `data:...`) — пусто.
fn origin_of(url: &str) -> &str {
    let Some(pos) = url.find("://") else {
        return "";
    };
    let after_scheme = pos + 3;
    let rest = &url[after_scheme..];
    let end = rest.find(['/', '?', '#']).unwrap_or(rest.len());
    &url[..after_scheme + end]
}

/// События, которые прокидываем в цикл tao (иначе он их не заметит).
enum UserEvent {
    Tray(TrayIconEvent),
    Menu(MenuEvent),
    /// Второй экземпляр попросил показать окно (D-Bus Activate).
    Activate,
}

/// Показать окно и поднять его с фокусом.
///
/// Общая часть (снять minimize, сделать видимым) одинакова везде; конкретный
/// способ «поднять и сфокусировать» различается по платформам — см. platform.
fn show_window(window: &Window) {
    if window.is_minimized() {
        window.set_minimized(false);
    }
    window.set_visible(true);
    platform::present_window(window);
}

/// Показать/скрыть окно. Крестик и пункт меню трея дёргают именно это.
fn toggle_window(window: &Window) {
    if window.is_visible() && !window.is_minimized() {
        window.set_visible(false);
    } else {
        show_window(window);
    }
}

/// Собрать вебвью: общая конфигурация (разрешения, навигация, новые окна) +
/// платформенная постройка (GTK-контейнер на Linux, окно tao на Windows).
fn make_webview(window: &Window, url: &str, origin: &str) -> wry::Result<WebView> {
    // Белый список навигации считаем от фактического адреса морды: меняешь
    // VOICEOG_PORT — и origin, и разрешение меняются вместе. Хардкода 7777 нет.
    let allowed_origin = origin.to_string();
    let builder = WebViewBuilder::new()
        .with_url(url)
        // Разрешаем ТОЛЬКО микрофон (кнопка записи в морде дёргает
        // getUserMedia; WebKitGTK по умолчанию отвечает отказом —
        // страница показывает «the user denied permission»). Всё прочее
        // (камера, гео, буфер) — отказ.
        .with_permission_handler(|kind| match kind {
            wry::PermissionKind::Microphone => wry::PermissionResponse::Allow,
            _ => wry::PermissionResponse::Deny,
        })
        // Пускаем только свой origin (наш локальный сервер) плюс about:/data:
        // (внутренние страницы движка). Чужой сайт — отказ: морда не уедет по
        // ссылке и не получит там доступ к микрофону.
        .with_navigation_handler(move |target| {
            target.starts_with("about:")
                || target.starts_with("data:")
                || origin_of(&target) == allowed_origin
        })
        .with_new_window_req_handler(|target, _features| {
            // target="_blank" (ссылка Health) — окна не плодим, открываем в браузере.
            platform::open_external(&target);
            wry::NewWindowResponse::Deny
        });
    platform::build_webview(window, builder)
}

fn main() -> wry::Result<()> {
    // Платформенный препа-хук до старта GTK. На NVIDIA+Wayland — включаем
    // GPU (DMABUF + __NV_DISABLE_EXPLICIT_SYNC=1), на остальных ничего не
    // трогаем; CPU-режим — вручную через VOICEOG_DISABLE_DMABUF=1.
    platform::prepare_environment();

    let url = voiceog_url();
    let origin = origin_of(&url).to_string();

    let event_loop = EventLoopBuilder::<UserEvent>::with_user_event().build();

    // Single-instance: если окно уже запущено — будим его и выходим с кодом 0.
    // Для первого экземпляра в `instance` живёт D-Bus-соединение: держим его до
    // конца main, иначе имя освободится и защита от дубля отвалится.
    let instance = single_instance::acquire(event_loop.create_proxy());
    if instance.is_secondary() {
        return Ok(());
    }

    // Трей шлёт события в свой канал — прокидываем их в tao через proxy.
    let proxy = event_loop.create_proxy();
    TrayIconEvent::set_event_handler(Some(move |e| {
        let _ = proxy.send_event(UserEvent::Tray(e));
    }));
    let proxy = event_loop.create_proxy();
    MenuEvent::set_event_handler(Some(move |e| {
        let _ = proxy.send_event(UserEvent::Menu(e));
    }));

    let window = WindowBuilder::new()
        .with_title("voiceog")
        .with_inner_size(LogicalSize::new(1000.0, 800.0))
        .with_min_inner_size(LogicalSize::new(720.0, 560.0))
        .build(&event_loop)
        .unwrap();

    // Вебвью строится платформенно: на Linux — в GTK-контейнер окна tao,
    // на Windows — прямо в окно. Общая конфигурация — в make_webview.
    let webview = make_webview(&window, &url, &origin)?;

    // Контент на месте — задаём размер ещё раз (Wayland иногда залипает на
    // «натуральном» размере вебвью) и поднимаем окно наверх.
    window.set_inner_size(LogicalSize::new(1000.0, 800.0));
    platform::present_window(&window);
    // Для отладки/скриншотов: VOICEOG_WINDOW_TOPMOST=1 держит окно поверх всех.
    if std::env::var_os("VOICEOG_WINDOW_TOPMOST").is_some() {
        window.set_always_on_top(true);
    }
    #[cfg(debug_assertions)]
    eprintln!("[voiceog-window] inner_size = {:?}", window.inner_size());

    // Трей держим в переменной, которую захватывает замыкание: создаём его в
    // StartCause::Init (когда цикл уже крутится) и не даём умереть.
    let mut tray: Option<TrayIcon> = None;

    event_loop.run(move |event, _target, control_flow| {
        *control_flow = ControlFlow::Wait;
        match event {
            // Resized здесь намеренно не слушаем: событие приходит на каждый
            // чих композитора, а толку от него нет. Отладочные размеры (когда
            // реально нужны) печатаются один раз выше под debug_assertions.
            // Трей поднимаем уже на старте цикла: бэкенду AppIndicator нужен
            // работающий event loop, иначе libappindicator уходит в legacy-фолбэк
            // (сыплет Gtk-CRITICAL и ведёт себя криво).
            Event::NewEvents(StartCause::Init) => {
                // Страховка от tao-бага #929: цикл стартовал — ещё раз задаём
                // размер (иногда первый configure приходит неверным).
                window.set_inner_size(LogicalSize::new(1000.0, 800.0));
                if tray.is_none() {
                    let menu = Menu::new();
                    let item_toggle = MenuItem::with_id("toggle", "Показать / Скрыть", true, None);
                    let item_reload = MenuItem::with_id("reload", "Перезагрузить", true, None);
                    let item_browser =
                        MenuItem::with_id("browser", "Открыть в браузере", true, None);
                    let item_quit = MenuItem::with_id("quit", "Выход", true, None);
                    menu.append_items(&[
                        &item_toggle,
                        &PredefinedMenuItem::separator(),
                        &item_reload,
                        &item_browser,
                        &PredefinedMenuItem::separator(),
                        &item_quit,
                    ])
                    .unwrap();

                    tray = Some(
                        TrayIconBuilder::new()
                            .with_id("main")
                            .with_tooltip("voiceog — локальный голосовой ввод")
                            .with_icon(make_icon(64))
                            .with_menu(Box::new(menu))
                            // Linux: меню на левый клик (как было). Windows:
                            // меню — по правому, а левый шлёт TrayIconEvent::Click
                            // → toggle_window (обработчик ниже).
                            .with_menu_on_left_click(cfg!(unix))
                            .build()
                            .unwrap(),
                    );
                }
            }
            // Крестик не закрывает программу — прячет окно в трей.
            Event::WindowEvent {
                event: WindowEvent::CloseRequested,
                ..
            } => window.set_visible(false),
            // Второй экземпляр попросил показать окно — поднимаем и фокусим.
            Event::UserEvent(UserEvent::Activate) => show_window(&window),
            Event::UserEvent(UserEvent::Menu(e)) => {
                if e.id == "toggle" {
                    toggle_window(&window);
                } else if e.id == "reload" {
                    let _ = webview.load_url(&url);
                } else if e.id == "browser" {
                    platform::open_external(&url);
                } else if e.id == "quit" {
                    *control_flow = ControlFlow::Exit;
                }
            }
            Event::UserEvent(UserEvent::Tray(TrayIconEvent::Click {
                button: tray_icon::MouseButton::Left,
                button_state: tray_icon::MouseButtonState::Up,
                ..
            })) => toggle_window(&window),
            _ => {}
        }
    });
}

/// Иконка трея рисуется прямо в коде: микрофон цветом-акцентом VOICEog (#0070f3).
/// Без внешних файлов — бинарь самодостаточный, и иконка не отвалится.
fn make_icon(size: u32) -> Icon {
    const SS: u32 = 4; // супер-сэмплинг: считаем 4×4 субпикселя — края гладкие
    let accent = (0u8, 112u8, 243u8); // #0070f3
    let mut rgba = Vec::with_capacity((size * size * 4) as usize);

    // Всё в долях [0,1] — форма не зависит от размера.
    let on = |x: f32, y: f32| -> bool {
        // корпус микрофона — капсула
        if capsule(x, y, 0.5, 0.16, 0.5, 0.50, 0.24) {
            return true;
        }
        // держатель — нижняя полуокружность (толстая дуга)
        let dx = x - 0.5;
        let dy = y - 0.42;
        let r = (dx * dx + dy * dy).sqrt();
        if y >= 0.42 && (r - 0.235).abs() <= 0.0425 {
            return true;
        }
        // ножка и основание
        if capsule(x, y, 0.5, 0.655, 0.5, 0.78, 0.085) {
            return true;
        }
        if capsule(x, y, 0.34, 0.82, 0.66, 0.82, 0.085) {
            return true;
        }
        false
    };

    for oy in 0..size {
        for ox in 0..size {
            let mut hits = 0u32;
            for sy in 0..SS {
                for sx in 0..SS {
                    let x = (ox as f32 + (sx as f32 + 0.5) / SS as f32) / size as f32;
                    let y = (oy as f32 + (sy as f32 + 0.5) / SS as f32) / size as f32;
                    if on(x, y) {
                        hits += 1;
                    }
                }
            }
            let cov = hits as f32 / (SS * SS) as f32;
            rgba.extend_from_slice(&[accent.0, accent.1, accent.2, (cov * 255.0) as u8]);
        }
    }

    Icon::from_rgba(rgba, size, size).expect("иконка трея")
}

/// Точка внутри «капсулы» — отрезок с закруглёнными концами. `w` — полная толщина.
fn capsule(x: f32, y: f32, x0: f32, y0: f32, x1: f32, y1: f32, w: f32) -> bool {
    let dx = x1 - x0;
    let dy = y1 - y0;
    let len2 = dx * dx + dy * dy;
    let t = if len2 > 0.0 {
        (((x - x0) * dx + (y - y0) * dy) / len2).clamp(0.0, 1.0)
    } else {
        0.0
    };
    let px = x0 + t * dx;
    let py = y0 + t * dy;
    let ddx = x - px;
    let ddy = y - py;
    ddx * ddx + ddy * ddy <= (w * 0.5) * (w * 0.5)
}
