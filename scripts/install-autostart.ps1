# scripts/install-autostart.ps1 — автозапуск VOICEog при входе в Windows.
#
#   powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
# Снять:  powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove
#
# Кладём ярлык в папку «Автозагрузка» (per-user, БЕЗ прав администратора).
# Ярлык зовёт wscript на scripts\run-hidden.vbs, а тот тихо поднимает voiceog.cmd —
# окно консоли не мигает. Планировщик (schtasks /SC ONLOGON) для этого требовал бы
# прав администратора, поэтому обходимся автозагрузкой.

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Cmd = Join-Path $Root 'voiceog.cmd'
$Vbs = Join-Path $Root 'scripts\run-hidden.vbs'
$Startup = [Environment]::GetFolderPath('Startup')
$Lnk = Join-Path $Startup 'VOICEog.lnk'

if ($Remove) {
  if (Test-Path $Lnk) { Remove-Item $Lnk -Force }
  Write-Host "[voiceog] автозапуск снят: $Lnk"
  exit 0
}

if (-not (Test-Path $Cmd)) { throw "нет $Cmd" }
if (-not (Test-Path $Vbs)) { throw "нет $Vbs" }

$sh = New-Object -ComObject WScript.Shell
$s = $sh.CreateShortcut($Lnk)
$s.TargetPath = 'wscript.exe'
$s.Arguments = '"' + $Vbs + '"'
$s.WorkingDirectory = $Root
$s.Description = 'VOICEog — локальный голосовой ввод'
$s.Save()

Write-Host "[voiceog] автозапуск поставлен (скрытно): $Lnk"
Write-Host "[voiceog] проверить: dir `"$Startup`""
Write-Host "[voiceog] снять:     powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove"
