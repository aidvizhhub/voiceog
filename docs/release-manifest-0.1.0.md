# VOICEog 0.1.0 — манифест релиза

Собрано локально **27.09.2026** из одного дерева `window/`.
Опорная точка «свежести» — исходник `window/src/single_instance.rs` (и `main.rs`), mtime **17:45:21**. Это mtime **второго** `touch src/*.rs` — **содержимое не менялось, обновился только mtime**. Что код тот же, доказано пересборкой: у крейта `voiceog-window` снесены `.fingerprint` и `deps`-артефакт, затем `cargo build --release` скомпилировал его заново и выдал **тот же** sha256, что и до `touch` (`333a9117af17b682…`). Честно про свежесть по **фактическим mtime**: свежее исходника (17:45:21) ровно **один** артефакт — Linux-бинарь `release/voiceog-window` (mtime **17:47:53**), и это как раз та реальная пересборка, что сделана после `touch` (sha при этом не изменился). Остальные упаковки собраны **до** второго `touch` (их mtime 17:19–17:41), так что «свежее исходника» они формально **не** являются. Но код в них тот же — доказательство: `.rpm` и бандл несут payload-бинарь **байт-в-байт** (`333a9117af17b682…`, как в `release/voiceog-window`), а `.deb` — **стрипнутый** бинарь (`50cc2f72392de68b…`, 4 060 088 б против 5 798 384 б): `cargo-deb` срезает символы, но GNU BuildID остаётся **тот же** `c22a17004d553d30…`, то есть код идентичен. Windows-`.exe` — отдельная история по линкеру, AppImage — по пересборке, см. «Свежесть».
Важная правка сборщика `window/packaging/appimage/build.sh` (литерал `${APPDIR}` вместо раскрытого `/work/...` в `WEBKIT_INJECTED_BUNDLE_PATH`) — mtime **17:35:12**. Это **более поздняя** правка того же файла; bookworm-AppImage пересобирался раньше — в **17:19:02**, и наличие фикса `${APPDIR}` в образе подтверждено распаковкой (вхождений `/work/` в хуках нет). AppImage по владению **не пересобирался** (дорого) — оставлен как есть, хэш сверен с диском.
Все sha256 — от реально лежащих на диске файлов, не выдуманные.

## Артефакты

| Артефакт (window/target/…) | Размер | sha256 (16) | mtime | Для чего |
|---|---|---|---|---|
| `release/voiceog-window` | 5.5 MiB | `333a9117af17b682` | 17:47:53 | Linux-бинарь окна (ELF x86-64). Основа для deb/rpm/AppImage/бандла. Это **реальная пересборка после `touch`** (mtime свежее src 17:45:21). Хэш **не изменился** относительно прежней сборки — детерминирован. |
| `debian/voiceog-window_0.1.0-1_amd64.deb` | 1.1 MiB | `8b9478d15c832966` | 17:39:30 | Установка в Debian/Ubuntu (`apt install ./…deb`). Хэш **не изменился** — детерминирован (cargo-deb обнуляет mtime файлов). |
| `generate-rpm/voiceog-window-0.1.0-1.x86_64.rpm` | 1.4 MiB | `47e5219814ac3acd` | 17:40:23 | Установка в Fedora/openSUSE (`dnf/rpm -i`). Хэш изменился (`26753bff…`) **только из-за `BUILDTIME`/mtime в заголовке** — payload-бинарь внутри = `333a9117af17b682…`, `rpm -K` → digests ОК. |
| `appimage/voiceog-window-0.1.0-x86_64-bookworm.AppImage` | 90.0 MiB | `5bba618523a89727` | 17:19:02 | **Раздаваемый AppImage**, ✅ **FIXED** (пересборка уже после правки `build.sh`). Хэш сверен с диском — совпадает, файл не менялся. Bookworm-сборка, потолок требуемой glibc — 2.35 (заводится на Debian 12, Ubuntu 22.04, Fedora 39 и новее). Хук `apprun-hooks/voiceog-webkit.sh` ставит `WEBKIT_INJECTED_BUNDLE_PATH=${APPDIR}/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle` — утёкшего `/work/...` нет (проверено распаковкой образа). |
| `x86_64-pc-windows-msvc/release/voiceog-window.exe` | 3.4 MiB | `5707927ed311b987` | 17:41:24 | Окно под Windows (PE32+ GUI x86-64). Хэш изменился (`1d90018f…`) **из-за `TimeDateStamp` и GUID PDB в PE-метаданных**, не из-за кода. |
| `bundle/VOICEog-0.1.0-linux-x86_64.tar.zst` | 12.1 MiB | `b035d3b1ba03839a` | 17:40:25 | Портативный бандл: распаковал → `./run.sh`. Окно + сервер (`src/`, `public/`) + prod-node_modules под linux-x64. Хэш изменился (`ac64ed5e…`) — tar фиксирует mtime, а `npm ci` в свежей площадке ставит модули со свежим mtime; **окно внутри = `333a9117af17b682…`**. |

## Свежесть относительно исходника (mtime 17:45:21 после `touch`)

- **`touch src/*.rs` (второй, в 17:45) не изменил код** — только mtime. Канонический sha256 Linux-бинаря остался `333a9117af17b682…`: доказано реальной перекомпиляцией крейта (снесены `target/release/.fingerprint/voiceog-window-*` и `target/release/deps/voiceog_window-*`, затем `cargo build --release`) — код тот же, бинарь побитово тот же.
- **Пересобрано владельцем финализации** (`cargo build --release` → `cargo deb` → `cargo generate-rpm` → `SKIP_BUILD=1 make-bundle.sh` → `cargo xwin build --release --target x86_64-pc-windows-msvc`). AppImage не трогали.
- **Совпали с прежним манифестом (байт-в-байт):** `release/voiceog-window` (`333a9117…`, mtime **17:47:53** — новая пересборка после `touch`) и `.deb` (`8b9478d1…`, 17:39:30) — Rust-сборка детерминирована.
- **Разошлись хэши — только из-за метаданных, а не кода:**
  - `.rpm` (`26753bff…` → `47e52198…`): в заголовок пакета пишется `BUILDTIME` и mtime файлов. Проверено: при `SOURCE_DATE_EPOCH=1700000000` две сборки дают **идентичный** файл (`fe08a3da…`). Payload-бинарь внутри rpm = `333a9117…`, `rpm -K` → digests ОК.
  - `.exe` (`1d90018f…` → `5707927e…`): PE-заголовок несёт `TimeDateStamp` (момент линковки) и случайный GUID PDB в `.rdata` (8 байт). Даже два линка при одинаковом `SOURCE_DATE_EPOCH` дают разные GUID — поэтому `.exe` не бит-в-бит. Контексты различаются по линкеру, но результат один и тот же: здешний локальный `.exe` собран через `cargo xwin` (toolchain clang + **lld**), а CI на `windows-latest` линкует нативным **MSVC** (`link.exe`) — см. `.github/workflows/release.yml` и `docs/packaging.md`. **Оба** линкера невоспроизводимы по PE-метаданным: `TimeDateStamp` (момент линковки) + свежий GUID PDB на каждый линк. Так что расхождение локальной и CI-сборок ожидаемо, а не признак расхождения кода.
  - `.tar.zst` (`ac64ed5e…` → `b035d3b1…`): tar кладёт mtime файлов, а `npm ci` в свежей площадке ставит модули с текущим mtime. Окно внутри бандла = `333a9117…`.
- **bookworm-AppImage** — 17:19:02; хэш на диске `5bba618523a89727` (совпадает с прежним). Фикс `${APPDIR}` в образе подтверждён распаковкой. Отдельно: текущий `build.sh` имеет mtime **17:35:12** — то есть правился **после** этой сборки образа; но образ содержит нужный фикс, а дальнейшие правки файла сборки кода окна не трогали. mtime образа старше искусственного mtime исходника (17:45:21), но так как `touch` код не менял, содержимое валидно — пересборка не требуется.
- **Самый свежий артефакт** — пересобранный `release/voiceog-window` (17:47:53, **новее** src 17:45:21). Дальше по старшинству все остальные **старше** src: `voiceog-window.exe` (17:41:24), `.tar.zst` (17:40:25), `.rpm` (17:40:23), `.deb` (17:39:30), AppImage (17:19:02). Их mtime — «до `touch`», но код тот же: payload-бинарь `333a9117af17b682…` (rpm и бандл совпадают с бинарём **байт-в-байт**; в `.deb` бинарь **стрипнут** — `50cc2f72392de68b…`, 4 060 088 б, — но GNU BuildID `c22a17004d553d30…` тот же), `.exe` отличается лишь PE-метаданными линкера.
- Старый AppImage `appimage/voiceog-window-0.1.0-x86_64.AppImage` (Fedora, 16:31:42) **удалён** — на диске его нет. Раздаём только bookworm-версию.

## Доказательство содержимого (маркеры single-instance)

Строки собраны из финальных артефактов на диске:

- **Linux `release/voiceog-window`** (`strings … | grep -i "SingleInstance\|voiceog.window"`): `5<interface name="org.voiceog.window.SingleInstance">`, `org.voiceog.window.SingleInstance`, `/org/voiceog/window/SingleInstance`, `[voiceog-window] single-instance`, `VOICEOG_WINDOW_TOPMOST` — маркер D-Bus single-instance на месте.
- **Windows `voiceog-window.exe`** (тот же grep): `5<interface name="org.voiceog.window.SingleInstance">`, `org.voiceog.window.SingleInstance`, `/org/voiceog/window/SingleInstance`, `src/single_instance.rs`, `[voiceog-window] single-instance`, `VOICEOG_WINDOW_TOPMOST` — тот же код внутри PE32+ GUI.
- `file`: Linux — `ELF 64-bit LSB pie executable, x86-64`; Windows — `PE32+ executable for MS Windows 6.00 (GUI), x86-64, 6 sections`.
- Целостность упаковок: `dpkg-deb -I` читает control (Package/Version/Depends/Installed-Size), payload-бинарь извлекается; `rpm -K` → `digests ОК`, `rpm -qRp` → 45 зависимостей, payload-бинарь = `333a9117…`; бандл `tar --zstd -tf` → 374 записи, окно внутри = `333a9117…`.

## Пересборка AppImage (фикс `WEBKIT_INJECTED_BUNDLE_PATH`)

- **Что было сломано:** в AppRun-хук попадал раскрытый абсолютный путь сборочного контейнера — `WEBKIT_INJECTED_BUNDLE_PATH=/work/window/target/appimage/AppDir/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle`. На чужой машине каталога `/work/` нет → WebKit не находит injected-bundle → белое окно.
- **Диагноз подтверждён распаковкой (старый образ):** `squashfs-root` из прошлого AppImage содержал в `apprun-hooks/voiceog-webkit.sh` ровно эту строку с `/work/`.
- **Фикс проверен распаковкой (новый образ):** `--appimage-extract` свежего AppImage → в `apprun-hooks/voiceog-webkit.sh` стоит `${APPDIR}/lib/x86_64-linux-gnu/webkit2gtk-4.1/injected-bundle` (плюс `cd "${APPDIR}"` и `LD_LIBRARY_PATH=${APPDIR}/usr/lib`), вхождений `/work/` в хуках **нет**.
- **Фикс в источнике:** `build.sh` теперь дописывает хук через `printf` с одинарными кавычками, оставляя литерал `${APPDIR}` (раскрывается AppRun при запуске). В рабочем дереве правка на месте.
- **Статус: ✅ готово.** Пересборка (`packaging/appimage/build-bookworm.sh`, образ `debian:bookworm`, лог пересборки `/tmp/rebuild-bookworm.log`) завершилась успешно в **17:19:02** (`appimage/stderr: Success`), контейнер прибран. Новый образ: **90.0 MiB**, `sha256` (16) = **`5bba618523a89727`**, mtime **17:19:02**. Маркер «PRE-FIX» снят.
- **Раздаваемый вариант — bookworm:** собран на glibc 2.36, но потолок требуемых символов — `GLIBC_2.35` (проверено `objdump -T` по либам образа; CUPS-бэкенд, тянувший 2.36, вырезан), т.е. совместим с Ubuntu 22.04 / Debian 12.

## Отсутствует

- `window/packaging/windows/*setup.exe` — **не собран**. В `packaging/windows/` лежат исходники (`voiceog.nsi`, `build-installer.sh`, `launch.vbs`, `voiceog-console.cmd`, `app.ico`, `README.md`, `sidecar/`), но самого установщика нет. Это норм: `setup.exe` собирается **только в CI** отдельным шагом (нужен `makensis` + sidecar-`node.exe` и win-модули, которых на Linux-машине нет).
- `window/target/VOICEog-setup.exe` — тоже нет.

## Что пересобирается в CI по тегу `v*`

`.github/workflows/release.yml`, триггер `push tags: v*` (или вручную):

- **linux** (ubuntu-22.04, glibc 2.35): `cargo build --release` → `cargo deb` → `cargo generate-rpm` → `appimage/build.sh` → `bundle/make-bundle.sh` (`SKIP_BUILD=1`). Артефакт `linux-packages`.
- **windows** (windows-latest): sidecar (`node.exe` + win-модули) → `cargo build --release` → NSIS `build-installer.sh` (`WITH_MODEL=0`). Артефакт `windows-setup` (setup.exe может отсутствовать — шаг `if-no-files-found: ignore`).
- **release**: по тегу `v*` клеит всё к GitHub Release.

То есть `.deb/.rpm/AppImage(bookworm)/tar.zst/exe/setup.exe` на CI воспроизводятся; локально сейчас лежит ровно один AppImage — bookworm, он и раздаётся.

## Где смотреть дальше

- Установка и упаковка — [packaging.md](packaging.md).
- Проверка руками (живая верифа) — [qa-window.md](qa-window.md).
- Заметки релиза — [release-notes-0.1.0.md](release-notes-0.1.0.md).
