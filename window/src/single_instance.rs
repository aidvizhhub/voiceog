// Single-instance: второй запуск не плодит окно, а поднимает уже открытое.
//
// Схема классическая для десктопа: через D-Bus занимаем well-known имя
// `org.voiceog.window.SingleInstance`.
//   * первый процесс занял имя и держит соединение → живёт окно;
//   * второй имя занять не смог → дёргает на первом метод Activate и выходит 0.
//
// zbus кроссплатформенный, но на Windows сессионной шины D-Bus по умолчанию нет:
// там `acquire()` вернёт `Disabled`, и окно стартует как обычно — просто без
// защиты от дубля (осознанный фолбэк, лучше так, чем не открыться вообще).

use std::sync::Mutex;

use tao::event_loop::EventLoopProxy;

use crate::UserEvent;

/// Well-known имя, которым «метим» единственный живой экземпляр.
const BUS_NAME: &str = "org.voiceog.window.SingleInstance";
/// Путь D-Bus-объекта с методом Activate.
const OBJ_PATH: &str = "/org/voiceog/window/SingleInstance";

/// Итог попытки «стать единственным окном».
pub enum Instance {
    /// Имя заняли мы — держим соединение живым до конца main и обслуживаем Activate.
    ///
    /// Поле не читается намеренно: соединение важно самим фактом жизни. Умрёт —
    /// освободится D-Bus-имя, и защита от дубля исчезнет.
    #[allow(dead_code)]
    Primary(zbus::blocking::Connection),
    /// Имя занято другим окном; его разбудили, нам осталось выйти с кодом 0.
    Secondary,
    /// Шины нет / D-Bus недоступен — single-instance выключен, работаем как обычно.
    Disabled,
}

impl Instance {
    /// true, если мы второй экземпляр и должны просто выйти.
    pub fn is_secondary(&self) -> bool {
        matches!(self, Instance::Secondary)
    }
}

/// D-Bus-объект, который слушает первый (живой) экземпляр.
struct SingleInstanceServer {
    // Mutex: D-Bus зовёт методы из своего потока, а EventLoopProxy — Send, но не
    // гарантированно Sync. Мьютекс делает структуру Send + Sync, как требует Interface.
    proxy: Mutex<EventLoopProxy<UserEvent>>,
}

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
#[zbus::proxy(
    interface = "org.voiceog.window.SingleInstance",
    default_service = "org.voiceog.window.SingleInstance",
    default_path = "/org/voiceog/window/SingleInstance"
)]
trait SingleInstance {
    fn activate(&self) -> zbus::Result<()>;
}

/// Занять имя или (если занято) разбудить уже живое окно.
pub fn acquire(proxy: EventLoopProxy<UserEvent>) -> Instance {
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
        // Шины нет (нет DBUS_SESSION_BUS_ADDRESS, Windows и т.п.) — не падаем,
        // просто едем без single-instance.
        Err(e) => {
            eprintln!("[voiceog-window] single-instance выключен: D-Bus недоступен ({e})");
            return Instance::Disabled;
        }
    };

    // DoNotQueue обязателен: без него шина молча ставит второй запрос в очередь
    // (RequestNameReply::InQueue) и ошибки «имя занято» не будет — получим два окна.
    match conn.request_name_with_flags(BUS_NAME, RequestNameFlags::DoNotQueue.into()) {
        Ok(_) => Instance::Primary(conn),
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
fn activate_existing() -> bool {
    let Ok(conn) = zbus::blocking::Connection::session() else {
        return false;
    };
    match SingleInstanceProxyBlocking::new(&conn) {
        Ok(proxy) => proxy.activate().is_ok(),
        Err(_) => false,
    }
}
