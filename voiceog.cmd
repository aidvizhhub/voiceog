@echo off
rem voiceog.cmd — запуск VOICEog и управление им на Windows.
rem
rem   voiceog            — старт сервера (ставит зависимости и модель при надобности)
rem   voiceog toggle     — старт/стоп записи (для глобального хоткея)
rem   voiceog status     — состояние (пишет ли, готова ли вставка)
setlocal
cd /d "%~dp0"

set "PORT=%VOICEOG_PORT%"
if "%PORT%"=="" set "PORT=7777"
set "BASE=http://127.0.0.1:%PORT%"

if "%~1"=="toggle" (
  curl.exe -s -X POST "%BASE%/toggle"
  echo.
  exit /b 0
)
if "%~1"=="status" (
  curl.exe -s "%BASE%/state"
  echo.
  exit /b 0
)

if not exist "node_modules\sherpa-onnx-node" (
  echo [voiceog] ставлю зависимости...
  call npm install || exit /b 1
)

if not exist "models\sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8\tokens.txt" (
  echo [voiceog] модели нет - качаю...
  node scripts\download-model.mjs || exit /b 1
)

node src\server.mjs %*
