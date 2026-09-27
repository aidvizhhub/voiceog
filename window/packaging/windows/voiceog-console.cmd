@echo off
rem voiceog-console.cmd — запуск VOICEog с видимой консолью. Для отладки:
rem тут видно логи сервера, чего тихий launch.vbs не показывает.
rem Обычный запуск — ярлык, он зовёт launch.vbs. Этот файл просто лежит рядом.
setlocal
cd /d "%~dp0"

set "PATH=%~dp0server\node_modules\sherpa-onnx-win-x64;%PATH%"
if "%VOICEOG_PORT%"=="" set "VOICEOG_PORT=7777"

echo [voiceog] поднимаю сервер (Ctrl+C в этом окне — стоп)...
start "voiceog-server" /b "%~dp0node.exe" "%~dp0server\src\server.mjs"

echo [voiceog] жду, пока сервер откликнется...
set /a tries=0
:wait
set /a tries+=1
curl.exe -sf -m 2 "http://127.0.0.1:%VOICEOG_PORT%/health" >nul 2>&1 && goto ok
if %tries% geq 120 goto fail
timeout /t 1 /nobreak >nul
goto wait

:ok
echo [voiceog] сервер готов, открываю окно...
start "" "%~dp0voiceog-window.exe"
exit /b 0

:fail
echo [voiceog] сервер не поднялся — смотри его вывод выше.
exit /b 1
