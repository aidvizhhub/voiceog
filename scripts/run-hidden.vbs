' run-hidden.vbs — запускает voiceog.cmd скрытно, без окна консоли.
' Нужен для автозапуска при входе в систему (Планировщик зовёт этот файл).
' Кладётся в scripts/, проект — на уровень выше.

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
sh.CurrentDirectory = root
sh.Run """" & root & "\voiceog.cmd""", 0, False
