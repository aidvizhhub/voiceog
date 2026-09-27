// Single-instance: второй запуск не плодит окно, а поднимает уже открытое.
//
// Две платформы — две механики, одинаковая идея: первый процесс «метит» себя
// системным объектом, второй эту метку видит и будит первое окно вместо того,
// чтобы открыть своё.
//
//   * Linux/macOS — D-Bus: первый занимает well-known имя
//     `org.voiceog.window.SingleInstance`, второй имя занять не может → дёргает
//     метод Activate и выходит 0.
//   * Windows — именованные объекты ядра: mutex
//     `Local\voiceog-window.single-instance` как «замок», event
//     `Local\voiceog-window.activate` как «звонок в дверь». Event создаётся
//     первым — до mutex — чтобы проигравший гонку за замок гарантированно видел
//     звонок. Второй дёргает SetEvent по своему хендлу, а первый сидит на
//     WaitForSingleObject в отдельном потоке и превращает сигнал в
//     `UserEvent::Activate`.
//
// zbus кроссплатформенный, но на Windows сессионной шины D-Bus по умолчанию нет,
// поэтому там работает ветка на windows-sys.

use tao::event_loop::EventLoopProxy;

use crate::UserEvent;

/// Well-known имя, которым «метим» единственный живой экземпляр (D-Bus).
#[cfg(unix)]
const BUS_NAME: &str = "org.voiceog.window.SingleInstance";
/// Путь D-Bus-объекта с методом Activate.
#[cfg(unix)]
const OBJ_PATH: &str = "/org/voiceog/window/SingleInstance";

/// Имя «замка» на Windows: занят — значит окно уже живёт.
#[cfg(windows)]
const MUTEX_NAME: &str = "Local\\voiceog-window.single-instance";
/// Имя «звонка» на Windows: первый слушает его, второй дёргает.
#[cfg(windows)]
const EVENT_NAME: &str = "Local\\voiceog-window.activate";

/// Платформенная «ручка» первого экземпляра. Живёт, пока живёт `Instance`:
/// умрёт — освободится метка, и защита от дубля исчезнет.
#[cfg(unix)]
pub(crate) struct Primary(#[allow(dead_code)] zbus::blocking::Connection);

#[cfg(windows)]
pub(crate) struct Primary {
    /// Хендл mutex. Не читается: важен самим фактом открытости.
    #[allow(dead_code)]
    mutex: windows_sys::Win32::Foundation::HANDLE,
    /// Хендл event. Не читается: его слушает отдельный поток.
    #[allow(dead_code)]
    event: windows_sys::Win32::Foundation::HANDLE,
}

#[cfg(windows)]
impl Drop for Primary {
    fn drop(&mut self) {
        unsafe {
            use windows_sys::Win32::Foundation::CloseHandle;
            CloseHandle(self.event);
            CloseHandle(self.mutex);
        }
    }
}

/// Итог попытки «стать единственным окном».
pub enum Instance {
    /// Метку заняли мы — держим её живой до конца main и обслуживаем Activate.
    #[allow(dead_code)]
    Primary(Primary),
    /// Метка занята другим окном; его разбудили, нам осталось выйти с кодом 0.
    Secondary,
    /// Механики нет / объект не создался — single-instance выключен, работаем
    /// как обычно (осознанный фолбэк: лучше открыться без защиты, чем не открыться).
    Disabled,
}

impl Instance {
    /// true, если мы второй экземпляр и должны просто выйти.
    pub fn is_secondary(&self) -> bool {
        matches!(self, Instance::Secondary)
    }
}

// ─────────────────────────── Linux/macOS: D-Bus ───────────────────────────

/// D-Bus-объект, который слушает первый (живой) экземпляр.
#[cfg(unix)]
struct SingleInstanceServer {
    // Mutex: D-Bus зовёт методы из своего потока, а EventLoopProxy — Send, но не
    // гарантированно Sync. Мьютекс делает структуру Send + Sync, как требует Interface.
    proxy: std::sync::Mutex<EventLoopProxy<UserEvent>>,
}

#[cfg(unix)]
#[zbus::interface(name = "org.voiceog.window.SingleInstance")]
impl SingleInstanceServer {
    /// Второй экземпляр просит показать окно. Сами окно не трогаем — просто
    /// кидаем событие в цикл tao через proxy, а поднимает окно уже цикл.
    fn activate(&self) {
        if let Ok(proxy) = self.proxy.lock() {
            let _ = proxy.send_event(UserEvent::Activate);
        }
    }
}

/// Клиент первого экземпляра — им пользуется второй процесс.
#[cfg(unix)]
#[zbus::proxy(
    interface = "org.voiceog.window.SingleInstance",
    default_service = "org.voiceog.window.SingleInstance",
    default_path = "/org/voiceog/window/SingleInstance"
)]
trait SingleInstance {
    fn activate(&self) -> zbus::Result<()>;
}

/// Занять имя или (если занято) разбудить уже живое окно.
#[cfg(unix)]
pub fn acquire(proxy: EventLoopProxy<UserEvent>) -> Instance {
    use std::sync::Mutex;

    use zbus::blocking::connection::Builder;
    use zbus::fdo::RequestNameFlags;

    let server = SingleInstanceServer {
        proxy: Mutex::new(proxy),
    };

    // Соединяемся и поднимаем объект с методом Activate. Имя пока не просим:
    // это делаем отдельно ниже, потому что через Builder::name флаг DoNotQueue
    // не выставить.
    let conn = match Builder::session()
        .and_then(|b| b.serve_at(OBJ_PATH, server))
        .and_then(|b| b.build())
    {
        Ok(conn) => conn,
        // Шины нет (нет DBUS_SESSION_BUS_ADDRESS и т.п.) — не падаем,
        // просто едем без single-instance.
        Err(e) => {
            eprintln!("[voiceog-window] single-instance выключен: D-Bus недоступен ({e})");
            return Instance::Disabled;
        }
    };

    // DoNotQueue обязателен: без него шина молча ставит второй запрос в очередь
    // (RequestNameReply::InQueue) и ошибки «имя занято» не будет — получим два окна.
    match conn.request_name_with_flags(BUS_NAME, RequestNameFlags::DoNotQueue.into()) {
        Ok(_) => Instance::Primary(Primary(conn)),
        // Имя занято — значит окно уже есть. Будим его и выходим.
        Err(zbus::Error::NameTaken) => {
            if activate_existing() {
                Instance::Secondary
            } else {
                Instance::Disabled
            }
        }
        Err(e) => {
            eprintln!("[voiceog-window] single-instance выключен: имя не заняли ({e})");
            Instance::Disabled
        }
    }
}

/// Дёрнуть Activate на уже запущенном экземпляре. `true` — получилось.
#[cfg(unix)]
fn activate_existing() -> bool {
    let Ok(conn) = zbus::blocking::Connection::session() else {
        return false;
    };
    match SingleInstanceProxyBlocking::new(&conn) {
        Ok(proxy) => proxy.activate().is_ok(),
        Err(_) => false,
    }
}

// ──────────────────────────── Windows: win32 ────────────────────────────

/// Win32 ждёт wide-строку с завершающим нулём.
#[cfg(windows)]
fn to_wide(s: &str) -> Vec<u16> {
    s.encode_utf16().chain(std::iter::once(0)).collect()
}

/// Создать «замок» и «звонок», либо — если замок уже занят — позвонить первому
/// экземпляру и уйти в `Secondary`.
#[cfg(windows)]
pub fn acquire(proxy: EventLoopProxy<UserEvent>) -> Instance {
    use windows_sys::Win32::Foundation::{
        CloseHandle, ERROR_ALREADY_EXISTS, GetLastError, HANDLE, SetLastError, WAIT_OBJECT_0,
    };
    use windows_sys::Win32::System::Threading::{
        CreateEventW, CreateMutexW, INFINITE, SetEvent, WaitForSingleObject,
    };
    use windows_sys::Win32::UI::WindowsAndMessaging::{ASFW_ANY, AllowSetForegroundWindow};

    // Сбрасываем код ошибки заранее: CreateEventW/CreateMutexW выставляют его
    // только при неудаче, но подхватить stale-значение от чужого вызова нельзя —
    // очистка гарантирует, что ERROR_ALREADY_EXISTS будет именно нашим сигналом.
    unsafe { SetLastError(0) };

    let mutex_name = to_wide(MUTEX_NAME);
    let event_name = to_wide(EVENT_NAME);

    // Сначала «звонок», потом «замок». Event создаётся и открывается с тем же
    // именем: если объект уже существует, CreateEventW вернёт хендл на него,
    // а не ошибку (ровно как у mutex). Поэтому OpenEventW не нужен — у нас уже
    // есть свой хендл на тот же самый именованный объект.
    // Auto-reset (bManualReset = FALSE): после SetEvent первый же
    // WaitForSingleObject сбросит его, лишние сигналы не накопятся.
    let event = unsafe { CreateEventW(std::ptr::null(), 0, 0, event_name.as_ptr()) };
    if event.is_null() {
        eprintln!("[voiceog-window] single-instance выключен: event не создался");
        return Instance::Disabled;
    }

    // bInitialOwner = FALSE: владение не нужно, важен лишь факт существования
    // объекта — второй процесс увидит ERROR_ALREADY_EXISTS.
    let mutex = unsafe { CreateMutexW(std::ptr::null(), 0, mutex_name.as_ptr()) };
    if mutex.is_null() {
        eprintln!("[voiceog-window] single-instance выключен: mutex не создался");
        unsafe { CloseHandle(event) };
        return Instance::Disabled;
    }

    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        // Мы второй. Event создан раньше mutex, значит первый экземпляр (тот,
        // кто занял mutex) уже гарантированно видит этот event. Разрешаем ему
        // поднять окно наверх (foreground), звоним по своему хендлу и уходим.
        // Оба хендла закрываем — они нам не нужны.
        unsafe {
            AllowSetForegroundWindow(ASFW_ANY);
            SetEvent(event);
            CloseHandle(event);
            CloseHandle(mutex);
        }
        return Instance::Secondary;
    }

    // Мы первый. Поток слушателя. HANDLE — не Send, поэтому тащим его как usize
    // и восстанавливаем на месте; объект ядра держит живым `Primary` в Instance.
    // Detached: при выходе процесса поток умрёт вместе с ним.
    let event_raw = event as usize;
    std::thread::spawn(move || {
        let event = event_raw as HANDLE;
        loop {
            let r = unsafe { WaitForSingleObject(event, INFINITE) };
            // Хендл умер или ошибка — выходим, чтобы не крутить холостой спин.
            if r == WAIT_OBJECT_0 {
                let _ = proxy.send_event(UserEvent::Activate);
            } else {
                break;
            }
        }
    });

    Instance::Primary(Primary { mutex, event })
}
