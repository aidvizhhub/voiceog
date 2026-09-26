# scripts/install-autostart.ps1 — автозапуск VOICEog при входе в Windows.
#
#   powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1
# Снять:  powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove
#
# Ставит задачу в Планировщик: при входе запускает voiceog.cmd (сервер + хоткей).

param([switch]$Remove)

$ErrorActionPreference = 'Stop'
$Root = Split-Path -Parent $PSScriptRoot
$Cmd = Join-Path $Root 'voiceog.cmd'
$Vbs = Join-Path $Root 'scripts\run-hidden.vbs'
$Task = 'VOICEog'

if ($Remove) {
  schtasks /Delete /TN $Task /F 2>$null | Out-Null
  Write-Host "[voiceog] автозапуск снят ($Task)"
  exit 0
}

if (-not (Test-Path $Cmd)) { throw "нет $Cmd" }
if (-not (Test-Path $Vbs)) { throw "нет $Vbs" }

# Запуск без окна консоли: Планировщик зовёт wscript, тот скрытно поднимает voiceog.cmd.
$Action = "wscript.exe `"$Vbs`""
schtasks /Create /TN $Task /TR $Action /SC ONLOGON /RL LIMITED /F | Out-Null

Write-Host "[voiceog] автозапуск поставлен: $Task → $Cmd (скрытно)"
Write-Host "[voiceog] проверить: schtasks /Query /TN $Task"
Write-Host "[voiceog] снять:     powershell -ExecutionPolicy Bypass -File scripts\install-autostart.ps1 -Remove"
