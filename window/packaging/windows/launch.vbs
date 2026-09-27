' launch.vbs — тихий запуск VOICEog на Windows.
'
' Ярлыки (Start Menu / Desktop) зовут именно этот файл через wscript.exe,
' поэтому окна консоли не мигают. Что тут по шагам:
'   1. Сервер уже отвечает на http://127.0.0.1:7777/health? Не трогаем его —
'      мог поднять автозапуск или сам пользователь.
'   2. Иначе запускаем node.exe server\src\server.mjs скрытно и ждём до 60 c,
'      пока он откликнется. Долго — потому что сервер грузит модель (сотни МБ).
'   3. Открываем voiceog-window.exe (окно-пульт) и ждём, пока его закроют.
'      Крестик прячет окно в трей, реальный выход — «Выход» в меню трея.
'   4. Окно закрыли — гасим ТОЛЬКО тот сервер, который подняли сами. Чужой
'      не трогаем никогда.
'
' Порт переопределяется переменной VOICEOG_PORT (по умолчанию 7777). VOICEOG_URL
' тут ни при чём — это ручка окна на Linux, launch.vbs её не читает.

Option Explicit

Dim fso, sh, root, nodeExe, winExe, serverJs, serverDir, libDir
Dim modelTokens, dlScript, port, healthUrl, startedServer, i

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(WScript.ScriptFullName)
nodeExe = root & "\node.exe"
winExe = root & "\voiceog-window.exe"
serverDir = root & "\server"
serverJs = serverDir & "\src\server.mjs"
libDir = serverDir & "\node_modules\sherpa-onnx-win-x64"
modelTokens = serverDir & "\models\sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8\tokens.txt"
dlScript = serverDir & "\scripts\download-model.mjs"

port = sh.Environment("PROCESS")("VOICEOG_PORT")
If port = "" Then port = "7777"
healthUrl = "http://127.0.0.1:" & port & "/health"

' --- всё на месте? ---
If Not fso.FileExists(nodeExe) Then Fail "нет " & nodeExe
If Not fso.FileExists(winExe) Then Fail "нет " & winExe
If Not fso.FileExists(serverJs) Then Fail "нет " & serverJs

' --- второй пульт не плодим (как run-window.sh). VOICEOG_WINDOW_ALLOW_MULTI=1
'     снимает только эту проверку лончера (на Linux zbus-защита бинаря независима) ---
If sh.Environment("PROCESS")("VOICEOG_WINDOW_ALLOW_MULTI") = "" Then
  If WindowRunning() Then WScript.Quit 0
End If

' --- модель: нет (сборка с WITH_MODEL=0) — качаем при первом старте ---
If Not fso.FileExists(modelTokens) And fso.FileExists(dlScript) Then
  MsgBox "Первый запуск: качаю модель распознавания (~487 МБ)." & vbCrLf & _
    "Это займёт пару минут — окно появится после.", 64, "VOICEog"
  sh.CurrentDirectory = serverDir
  sh.Run """" & nodeExe & """ """ & dlScript & """", 0, True
  If Not fso.FileExists(modelTokens) Then
    MsgBox "Модель не скачалась. Запусти вручную:" & vbCrLf & _
      """" & nodeExe & """ """ & dlScript & """", 48, "VOICEog"
  End If
End If

startedServer = False

' --- 1-2. сервер ---
If Not Health(healthUrl) Then
  ' sherpa-onnx на Windows подгружает свои DLL из своего пакета — даём путь.
  If fso.FolderExists(libDir) Then
    sh.Environment("PROCESS")("PATH") = libDir & ";" & sh.Environment("PROCESS")("PATH")
  End If

  sh.CurrentDirectory = serverDir
  sh.Run """" & nodeExe & """ """ & serverJs & """", 0, False
  startedServer = True

  For i = 1 To 120
    If Health(healthUrl) Then Exit For
    WScript.Sleep 500
  Next
  If Not Health(healthUrl) Then
    MsgBox "Сервер VOICEog не поднялся за 60 секунд." & vbCrLf & vbCrLf & _
      "Посмотри, что он говорит. Запусти вручную:" & vbCrLf & _
      """" & nodeExe & """ """ & serverJs & """", _
      48, "VOICEog"
  End If
End If

' --- 3. окно (ждём закрытия) ---
sh.CurrentDirectory = root
sh.Run """" & winExe & """", 0, True

' --- 4. гасим только свой сервер ---
If startedServer Then KillOwnServer

WScript.Quit 0

' ================= вспомогательные =================

Sub Fail(msg)
  MsgBox "VOICEog не запустился: " & msg, 16, "VOICEog"
  WScript.Quit 1
End Sub

' Сервер жив? Тихий GET /health, ждём максимум пару секунд.
Function Health(url)
  Dim x
  Health = False
  On Error Resume Next
  Set x = CreateObject("MSXML2.XMLHTTP")
  x.Open "GET", url, False
  x.Send
  If Err.Number = 0 And x.Status = 200 Then Health = True
  Err.Clear
  On Error GoTo 0
End Function

' Окно уже открыто?
Function WindowRunning()
  Dim wmi, list, p
  WindowRunning = False
  On Error Resume Next
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  Set list = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name = 'voiceog-window.exe'")
  If Err.Number = 0 Then
    For Each p In list
      WindowRunning = True
      Exit For
    Next
  End If
  Err.Clear
  On Error GoTo 0
End Function

' Убить node.exe, чья командная строка указывает на наш server.mjs.
' Так мы не заденем чужие node-процессы (сборки, другие серверы).
Sub KillOwnServer()
  Dim wmi, list, p
  On Error Resume Next
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  Set list = wmi.ExecQuery("SELECT ProcessId, CommandLine FROM Win32_Process WHERE Name = 'node.exe'")
  For Each p In list
    If Not IsNull(p.CommandLine) Then
      If InStr(LCase(p.CommandLine), LCase(serverJs)) > 0 Then
        ' /T — вместе с дочерними (ffmpeg при записи).
        sh.Run "taskkill /PID " & p.ProcessId & " /T /F", 0, True
      End If
    End If
  Next
  Err.Clear
  On Error GoTo 0
End Sub
