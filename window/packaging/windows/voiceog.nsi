; voiceog.nsi — установщик VOICEog для Windows (NSIS 3.x).
;
; Что делает:
;   * ставит всё в %LOCALAPPDATA%\VOICEog — на пользователя, БЕЗ прав админа
;     (никакого UAC: RequestExecutionLevel user);
;   * кладёт окно-пульт (voiceog-window.exe), портативный node.exe и сервер
;     (server\: src, public, node_modules, models);
;   * делает ярлыки в Пуске и на Рабочем столе (зовут launch.vbs — тихий старт);
;   * прописывается в HKCU\...\Uninstall\VOICEog — видно в «Установка и удаление»;
;   * проверяет WebView2 Runtime и, если его нет, ставит Evergreen Bootstrapper.
;
; Сборка (Fedora):  window/packaging/windows/build-installer.sh
; Или напрямую:     makensis voiceog.nsi
;
; Все пути ниже — относительные, считаются от папки этого .nsi
; (window\packaging\windows). Переживают перенос проекта. Любую переменную
; можно перебить снаружи:  makensis -DWIN_EXE=... -DNODE_EXE=... voiceog.nsi

Unicode true
; Target НЕ задаём — оставляем дефолт NSIS = x86-unicode.
; Так надо потому, что у официального Windows-NSIS (nsis.sf.net, CI-раннер) в
; комплекте нет стаба amd64-unicode: `Target amd64-unicode` валится на
; "reading stub ... zlib-amd64-unicode" ещё до сборки. Установщик 32-битный,
; но payload внутри всё равно x64 (node.exe и окно), а ставим всё в
; %LOCALAPPDATA% текущего пользователя — 32-битный инсталлятор там работает
; без вопросов и на 64-битной Windows. Хочешь amd64-стаб — собирай makensis,
; у которого он есть (Linux-NSIS), но быстрый путь релиза = x86-unicode.

; --------------------------------------------------------------------------
; Пути.
;   ROOT    = папка window\          (тут target\ с exe окна)
;   APP_DIR = корень проекта VOICEog (тут src\, public\, models\, node_modules\)
; --------------------------------------------------------------------------
!define ROOT    "..\.."
!define APP_DIR "${ROOT}\.."

!ifndef APP_NAME
  !define APP_NAME "VOICEog"
!endif
!ifndef APP_VERSION
  !define APP_VERSION "0.1.0"
!endif
!ifndef PUBLISHER
  !define PUBLISHER "VOICEog"
!endif

; --- откуда берём файлы (перебивается -D...) ---
; По умолчанию node.exe и серверный каталог берём из sidecar:
; window\target\win-sidecar\ (готовят sidecar/provision.sh и
; sidecar/build-node-modules.ps1). build-installer.sh передаёт их явно.
!ifndef WIN_EXE
  !define WIN_EXE "${ROOT}\target\x86_64-pc-windows-msvc\release\voiceog-window.exe"
!endif
!ifndef NODE_EXE
  !define NODE_EXE "${ROOT}\target\win-sidecar\node.exe"
!endif
!ifndef SERVER_DIR
  !define SERVER_DIR "${ROOT}\target\win-sidecar"
!endif
!ifndef WEBVIEW2_SETUP
  !define WEBVIEW2_SETUP "${APP_DIR}\MicrosoftEdgeWebview2Setup.exe"
!endif
; Модель распознавания распаковывается в ~641 МБ на диске. По умолчанию кладём. Хочешь лёгкий
; установщик — собирай с -DWITH_MODEL=0, тогда модель качается при первом старте.
!ifndef WITH_MODEL
  !define WITH_MODEL 1
!endif
!ifndef OUT_FILE
  ; target\ — рядом с остальными артефактами сборки окна (он в .gitignore).
  !define OUT_FILE "${ROOT}\target\${APP_NAME}-setup.exe"
!endif

!define UNINST_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\${APP_NAME}"
!define WV2_GUID "{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

; --------------------------------------------------------------------------
; Проверки на этапе сборки. Нет файла — не собираем, а говорим понятное «где взять».
; --------------------------------------------------------------------------
!if /FileExists "${WIN_EXE}"
!else
  !error "нет exe окна: ${WIN_EXE} -- собери: cd window && cargo xwin build --release --target x86_64-pc-windows-msvc"
!endif
!if /FileExists "${NODE_EXE}"
!else
  !error "нет node.exe: ${NODE_EXE} -- прогони sidecar/provision.sh (скачает Windows node.exe в window\target\win-sidecar) или задай -DNODE_EXE=<путь>"
!endif
!if /FileExists "${SERVER_DIR}\src\server.mjs"
!else
  !error "нет ${SERVER_DIR}\src\server.mjs -- прогони sidecar/build-node-modules.ps1 или задай -DSERVER_DIR=<каталог sidecar с src/public/node_modules>"
!endif
!if /FileExists "${SERVER_DIR}\public\index.html"
!else
  !error "нет ${SERVER_DIR}\public\index.html -- собери sidecar (build-node-modules.ps1) или задай -DSERVER_DIR=<каталог sidecar>"
!endif
; !if в этом NSIS умеет только /FileExists — проверяем по файлу-маркеру.
!if /FileExists "${SERVER_DIR}\node_modules\sherpa-onnx-node\package.json"
!else
  !error "нет ${SERVER_DIR}\node_modules -- на Windows-сборке там должны быть win-модули (sherpa-onnx-node, sherpa-onnx-win-x64 и т.д.)"
!endif
!if ${WITH_MODEL}
  !if /FileExists "${SERVER_DIR}\models\sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8\tokens.txt"
  !else
    !error "нет модели в ${SERVER_DIR}\models (нет tokens.txt) -- собери с -DWITH_MODEL=0, тогда качается при старте"
  !endif
!endif
; Bootstrapper WebView2 кладём, только если он реально есть рядом.
!if /FileExists "${WEBVIEW2_SETUP}"
  !define HAVE_WV2_SETUP
!endif

; --------------------------------------------------------------------------
; Общее
; --------------------------------------------------------------------------
!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"
!include "WinVer.nsh"

Name "${APP_NAME}"
OutFile "${OUT_FILE}"
RequestExecutionLevel user
InstallDir "$LOCALAPPDATA\${APP_NAME}"
ShowInstDetails show
ShowUninstDetails show

; Сжатие: обычный LZMA (не solid). Solid-режим пришлось не брать: он
; игнорирует SetCompress off, а модель (~641 МБ уже сжатых onnx) совать
; в LZMA бессмысленно и очень долго. Словарь 64 МБ — node_modules жмёт плотно.
SetCompressor lzma
SetCompressorDictSize 64

VIProductVersion "0.1.0.0"
VIAddVersionKey "ProductName" "${APP_NAME}"
VIAddVersionKey "FileDescription" "Установщик ${APP_NAME}"
VIAddVersionKey "FileVersion" "${APP_VERSION}"
VIAddVersionKey "ProductVersion" "${APP_VERSION}"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "LegalCopyright" "(c) 2026 ${PUBLISHER}"

!define MUI_ICON "${__FILEDIR__}\app.ico"
!define MUI_UNICON "${__FILEDIR__}\app.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN
!define MUI_FINISHPAGE_RUN_TEXT "Запустить ${APP_NAME}"
!define MUI_FINISHPAGE_RUN_FUNCTION LaunchVoiceog

; Страницы: без выбора папки — ставим ровно в %LOCALAPPDATA%\VOICEog.
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "Russian"

Function LaunchVoiceog
  Exec '"$SYSDIR\wscript.exe" "$INSTDIR\launch.vbs"'
FunctionEnd

Function .onInit
  ${IfNot} ${AtLeastWin10}
    ; В тихом режиме предупреждение пропускаем, иначе окно виснет (/SD у MB_OK не спасает от паузы).
    IfSilent wv2_win_ok
    MessageBox MB_OK|MB_ICONEXCLAMATION "${APP_NAME} рассчитан на Windows 10/11. На старых версиях WebView2 может не поставиться."
  ${EndIf}
  wv2_win_ok:
FunctionEnd

; --------------------------------------------------------------------------
; Секция 1: WebView2 Runtime. Движок окна на Windows — это WebView2 (Edge/Chromium).
; Свежие Win10/11 идут с ним из коробки. Нет — ставим bootstrapper.
; --------------------------------------------------------------------------
Section "WebView2 Runtime" SEC_WV2
  ; Проверяем три места, как советует Microsoft: per-machine (32-битный вид
  ; реестра = WOW6432Node), per-user и per-machine (64-битный вид).
  StrCpy $R0 ""
  StrCpy $R1 ""
  StrCpy $R2 ""
  ClearErrors
  SetRegView 32
  ReadRegStr $R0 HKLM "SOFTWARE\Microsoft\EdgeUpdate\Clients\${WV2_GUID}" "pv"
  ReadRegStr $R1 HKCU "Software\Microsoft\EdgeUpdate\Clients\${WV2_GUID}" "pv"
  SetRegView 64
  ReadRegStr $R2 HKLM "SOFTWARE\Microsoft\EdgeUpdate\Clients\${WV2_GUID}" "pv"

  StrCmp $R0 "" 0 wv2_done
  StrCmp $R1 "" 0 wv2_done
  StrCmp $R2 "" 0 wv2_done

  DetailPrint "WebView2 Runtime не найден — ставлю."
!ifdef HAVE_WV2_SETUP
  InitPluginsDir
  SetOutPath "$PLUGINSDIR"
  File "${WEBVIEW2_SETUP}"
  SetOutPath "$INSTDIR"
  DetailPrint "Запускаю Microsoft Edge WebView2 Bootstrapper (тихо)..."
  ExecWait '"$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe" /silent /install' $R3
  DetailPrint "Bootstrapper завершился с кодом $R3."
!else
  ; Тихий режим (/S, CI-smoke): диалог не показываем — иначе MessageBox
  ; без /SD ждёт клика и установка виснет до таймаута. Просто идём дальше:
  ; приложение ставится, WebView2 доставит система/Edge при первом запуске.
  IfSilent wv2_done
  MessageBox MB_OKCANCEL|MB_ICONEXCLAMATION \
    "WebView2 Runtime не найден, а bootstrapper рядом с установщиком не лежит.$\n$\nСкачать сейчас в браузере?" \
    /SD IDCANCEL \
    IDOK wv2_open IDCANCEL wv2_done
  wv2_open:
    ExecShell "open" "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
!endif

  wv2_done:
SectionEnd

; --------------------------------------------------------------------------
; Секция 2: сам VOICEog.
; --------------------------------------------------------------------------
Section "!${APP_NAME}" SEC_MAIN
  SectionIn RO

  ; --- окно-пульт, node, ярлыковый лончер ---
  SetOutPath "$INSTDIR"
  File /oname=voiceog-window.exe "${WIN_EXE}"
  File /oname=node.exe "${NODE_EXE}"
  File "${__FILEDIR__}\app.ico"
  File "${__FILEDIR__}\launch.vbs"
  File "${__FILEDIR__}\voiceog-console.cmd"

  ; --- сервер ---
  SetOutPath "$INSTDIR\server"
  File /r "${SERVER_DIR}\public"
  File /r "${SERVER_DIR}\src"
  File /r "${SERVER_DIR}\node_modules"
  File /nonfatal "${SERVER_DIR}\package.json"
  File /nonfatal "${SERVER_DIR}\voiceog.config.json"
  File /nonfatal /r "${SERVER_DIR}\scripts"

  ; --- модель (тяжёлая; -DWITH_MODEL=0 отключает) ---
!if ${WITH_MODEL}
  SetCompress off
  SetOutPath "$INSTDIR\server\models"
  File /r "${SERVER_DIR}\models\sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8"
  SetCompress auto
!endif

  ; --- удалятор ---
  SetOutPath "$INSTDIR"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  ; --- ярлыки (только текущий пользователь) ---
  SetShellVarContext current
  CreateDirectory "$SMPROGRAMS\${APP_NAME}"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk" "$SYSDIR\wscript.exe" '"$INSTDIR\launch.vbs"' "$INSTDIR\app.ico" 0 SW_SHOWNORMAL "" "${APP_NAME} — локальный голосовой ввод"
  CreateShortCut "$SMPROGRAMS\${APP_NAME}\Удалить ${APP_NAME}.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\app.ico" 0
  CreateShortCut "$DESKTOP\${APP_NAME}.lnk" "$SYSDIR\wscript.exe" '"$INSTDIR\launch.vbs"' "$INSTDIR\app.ico" 0 SW_SHOWNORMAL "" "${APP_NAME} — локальный голосовой ввод"

  ; --- реестр: запись в «Установка и удаление программ» (per-user) ---
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayName" "${APP_NAME}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayVersion" "${APP_VERSION}"
  WriteRegStr HKCU "${UNINST_KEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKCU "${UNINST_KEY}" "DisplayIcon" "$INSTDIR\app.ico"
  WriteRegStr HKCU "${UNINST_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINST_KEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKCU "${UNINST_KEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINST_KEY}" "NoRepair" 1
  WriteRegStr HKCU "Software\${APP_NAME}" "InstallDir" "$INSTDIR"

  ; --- размер на диске (для списка программ) ---
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  WriteRegDWORD HKCU "${UNINST_KEY}" "EstimatedSize" $0
SectionEnd

; --------------------------------------------------------------------------
; Удаление
; --------------------------------------------------------------------------
Section "Uninstall"
  SetShellVarContext current

  ; Закрываем окно — иначе его файл занят и не удалится. Имя уникальное,
  ; чужие процессы не заденем.
  ExecWait 'taskkill /F /IM voiceog-window.exe'

  ; ярлыки
  Delete "$DESKTOP\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\${APP_NAME}.lnk"
  Delete "$SMPROGRAMS\${APP_NAME}\Удалить ${APP_NAME}.lnk"
  RMDir "$SMPROGRAMS\${APP_NAME}"

  ; реестр
  DeleteRegKey HKCU "${UNINST_KEY}"
  DeleteRegKey HKCU "Software\${APP_NAME}"

  ; файлы. Ставим ровно в %LOCALAPPDATA%\VOICEog — сносим только её.
  StrCmp "$INSTDIR" "$LOCALAPPDATA\${APP_NAME}" 0 un_done
  RMDir /r "$INSTDIR"

  un_done:
SectionEnd
