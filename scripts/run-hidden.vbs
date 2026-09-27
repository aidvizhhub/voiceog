' run-hidden.vbs — запускает voiceog.cmd скрытно, без окна консоли.
' Нужен для автозапуска при входе в систему (зовётся ярлыком VOICEog.lnk из «Автозагрузки», ставит install-autostart.ps1).
' Кладётся в scripts/, проект — на уровень выше.

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

root = fso.GetParentFolderName(fso.GetParentFolderName(WScript.ScriptFullName))
sh.CurrentDirectory = root
sh.Run """" & root & "\voiceog.cmd""", 0, False
