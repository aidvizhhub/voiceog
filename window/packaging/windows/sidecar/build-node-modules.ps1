# build-node-modules.ps1 — собрать Windows-sidecar: node_modules + серверные файлы.
#
# Запускать ТОЛЬКО на Windows (живая тачка или windows-latest в CI). Причина:
# нативные модули sherpa-onnx-node, uiohook-napi и ffmpeg-static качаются/
# собираются под текущую ОС. На Linux npm ci положит linux-бинарники — такой
# sidecar на Windows не заведётся.
#
# Что делает:
#   1. npm ci --omit=dev в корне проекта (ставит прод-зависимости под win32-x64).
#   2. Проверяет, что нативные бинари реально win-овые (PE «MZ») и на месте.
#      Нет — падает с понятным списком, ЧТО именно не хватает.
#   3. Складывает в win-sidecar/: node_modules, src, public, scripts, package.json
#      и models/ — если папка models/ есть в корне проекта (в репе её нет,
#      models/ в .gitignore). node.exe туда кладёт provision.sh на Linux — здесь
#      не трогаем.
#
# Ручки:
#   -RepoRoot <путь>      корень проекта (по умолч. вычисляется от файла скрипта)
#   -SidecarDir <путь>    куда собирать (по умолч. <repo>\window\target\win-sidecar)
#   -SkipNpmCi            не звать npm ci (если node_modules уже собраны)
#
# Запуск (PowerShell):
#   powershell -ExecutionPolicy Bypass -File window\packaging\windows\sidecar\build-node-modules.ps1

[CmdletBinding()]
param(
    [string]$RepoRoot,
    [string]$SidecarDir,
    [switch]$SkipNpmCi
)

$ErrorActionPreference = 'Stop'

function Info([string]$m) { Write-Host "[sidecar] $m" }
function Die([string]$m) {
    Write-Host "[sidecar] ОШИБКА: $m" -ForegroundColor Red
    exit 1
}

# --- где мы и где проект ----------------------------------------------------
$Here = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $RepoRoot)    { $RepoRoot   = (Resolve-Path (Join-Path $Here '..\..\..\..')).Path }
if (-not $SidecarDir)  { $SidecarDir = Join-Path $RepoRoot 'window\target\win-sidecar' }

if ($env:OS -ne 'Windows_NT') {
    Die "скрипт только для Windows: npm ci должен дать win32-x64-нативники. Сейчас OS='$env:OS'"
}
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Die "нет npm в PATH — поставь Node.js (https://nodejs.org) и повтори"
}
if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot 'package.json'))) {
    Die "нет package.json в $RepoRoot — неверный -RepoRoot?"
}

# --- PE-проверка: файл начинается с 'MZ'? -----------------------------------
function Test-Pe([string]$Path) {
    try {
        $fs = [System.IO.File]::OpenRead($Path)
        try {
            $b = New-Object byte[] 2
            [void]$fs.Read($b, 0, 2)
            return ($b[0] -eq 0x4D -and $b[1] -eq 0x5A)
        } finally { $fs.Dispose() }
    } catch { return $false }
}

# --- 1. npm ci --------------------------------------------------------------
if (-not $SkipNpmCi) {
    Info "npm ci --omit=dev  ($RepoRoot)"
    Push-Location $RepoRoot
    try {
        & npm ci --omit=dev
        if ($LASTEXITCODE -ne 0) { Die "npm ci упал с кодом $LASTEXITCODE" }
    } finally { Pop-Location }
} else {
    Info "npm ci пропущен (-SkipNpmCi)"
}

# --- 2. что обязано быть -----------------------------------------------------
# Каждый нативник: путь относительно корня проекта + человеческое «зачем».
$required = @(
    @{ path = 'node_modules\sherpa-onnx-win-x64\sherpa-onnx.node'; why = 'распознавание речи (сборка под win-x64)' },
    @{ path = 'node_modules\sherpa-onnx-win-x64\onnxruntime.dll'; why = 'движок ONNX Runtime, нужен рядом с sherpa-onnx.node' },
    @{ path = 'node_modules\ffmpeg-static\ffmpeg.exe';           why = 'запись микрофона через dshow' },
    @{ path = 'src\server.mjs';                                  why = 'сам сервер' },
    @{ path = 'src\stt.mjs';                                     why = 'обвязка распознавания' },
    @{ path = 'public\index.html';                               why = 'морда (страница с кнопкой)' },
    @{ path = 'package.json';                                    why = 'манифест (type: module)' }
)

$missing = @()
$broken  = @()
foreach ($item in $required) {
    $p = Join-Path $RepoRoot $item.path
    if (-not (Test-Path -LiteralPath $p)) {
        $missing += ("{0}  — {1}" -f $item.path, $item.why)
    }
}

# uiohook-napi: имя .node-файла может отличаться — ищем маской.
$uhDir = Join-Path $RepoRoot 'node_modules\uiohook-napi\prebuilds\win32-x64'
$uhNode = @(Get-ChildItem -LiteralPath $uhDir -Filter '*.node' -ErrorAction SilentlyContinue)
if ($uhNode.Count -eq 0) {
    $missing += 'node_modules\uiohook-napi\prebuilds\win32-x64\*.node  — глобальный хоткей'
}

if ($missing.Count -gt 0) {
    $list = ($missing | ForEach-Object { "  - $_" }) -join "`n"
    Die "sidecar не собрать — нет нужных файлов:`n$list`n`nПодсказка: npm ci пройди заново на Windows. sherpa-onnx-win-x64 ставится как optional-зависимость sherpa-onnx-node (в package-lock.json он есть). ffmpeg.exe скачивает postinstall ffmpeg-static."
}

# --- нативники должны быть Windows-PE, а не Linux-ELF ------------------------
$peCheck = @(
    'node_modules\sherpa-onnx-win-x64\sherpa-onnx.node',
    'node_modules\sherpa-onnx-win-x64\onnxruntime.dll',
    'node_modules\ffmpeg-static\ffmpeg.exe'
)
foreach ($rel in $peCheck) {
    if (-not (Test-Pe (Join-Path $RepoRoot $rel))) {
        $broken += "$rel (не PE/MZ — похоже, собран не на Windows)"
    }
}
if ($uhNode.Count -gt 0 -and -not (Test-Pe $uhNode[0].FullName)) {
    $broken += "$($uhNode[0].FullName) (не PE/MZ)"
}
if ($broken.Count -gt 0) {
    $list = ($broken | ForEach-Object { "  - $_" }) -join "`n"
    Die "нативные бинари не win-овые:`n$list`n`nЭто значит, что node_modules собраны не на Windows (или под не ту платформу)."
}

Info "все нативники на месте и win-овые ✔"

# --- 3. копируем в sidecar ---------------------------------------------------
function Copy-Tree([string]$src, [string]$dst) {
    if (-not (Test-Path -LiteralPath $src)) { return }
    New-Item -ItemType Directory -Force -Path $dst | Out-Null
    # robocopy: /MIR — зеркалим, /NFL /NDL /NJH /NJS /NP — тихий вывод,
    # /R:2 /W:1 — не зависать на занятых файлах. Зовём через & — PowerShell сам
    # закавычит пути с пробелами.
    & robocopy $src $dst /MIR /NFL /NDL /NJH /NJS /NP /R:2 /W:1 | Out-Null
    # Коды robocopy 0..7 — норма (0 = нечего копировать). 8+ — ошибка.
    if ($LASTEXITCODE -ge 8) { Die "robocopy '$src' -> '$dst' упал (код $LASTEXITCODE)" }
}

New-Item -ItemType Directory -Force -Path $SidecarDir | Out-Null
Info "складываю sidecar: $SidecarDir"

Copy-Tree (Join-Path $RepoRoot 'node_modules') (Join-Path $SidecarDir 'node_modules')
Copy-Tree (Join-Path $RepoRoot 'src')          (Join-Path $SidecarDir 'src')
Copy-Tree (Join-Path $RepoRoot 'public')        (Join-Path $SidecarDir 'public')
Copy-Tree (Join-Path $RepoRoot 'scripts')       (Join-Path $SidecarDir 'scripts')

foreach ($f in @('package.json', 'voiceog.config.json')) {
    $src = Join-Path $RepoRoot $f
    if (Test-Path -LiteralPath $src) {
        Copy-Item -LiteralPath $src -Destination (Join-Path $SidecarDir $f) -Force
    }
}

# --- 4. модель --------------------------------------------------------------
# Модель распознавания (~641 МБ) в репу не входит (models/ в .gitignore). Если
# она уже лежит в корне проекта — кладём её в sidecar, тогда build-installer.sh
# с WITH_MODEL=1 (дефолт) соберётся. Нет модели — НЕ падаем: говорим как есть и
# объясняем, что делать (собирать установщик с WITH_MODEL=0).
$modelName = 'sherpa-onnx-nemo-parakeet-tdt-0.6b-v3-int8'
$modelsSrc = Join-Path $RepoRoot 'models'
$modelSrc  = Join-Path $modelsSrc $modelName
$modelDst  = Join-Path $SidecarDir "models\$modelName"

if (Test-Path -LiteralPath $modelSrc) {
    Info "копирую модель models\$modelName (~641 МБ, это небыстро)"
    Copy-Tree $modelsSrc (Join-Path $SidecarDir 'models')
    $mSize   = (Get-ChildItem -LiteralPath $modelDst -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $mSizeMb = if ($mSize) { [math]::Round($mSize / 1MB, 1) } else { 0 }
    $modelNote = "есть ($mSizeMb МБ) — WITH_MODEL=1 соберётся"
} else {
    $modelNote = "НЕТ (в корне нет models\$modelName) — для WITH_MODEL=1 положи модель и повтори, либо собери установщик с WITH_MODEL=0 (скачается при первом старте)"
}

# --- сводка ------------------------------------------------------------------
$nodeExe = Join-Path $SidecarDir 'node.exe'
$nodeNote = if (Test-Path -LiteralPath $nodeExe) { "есть" } else { "НЕТ — прогони provision.sh на Linux и положи в $SidecarDir" }
$nmSize   = (Get-ChildItem -LiteralPath (Join-Path $SidecarDir 'node_modules') -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$nmSizeMb = if ($nmSize) { [math]::Round($nmSize / 1MB, 1) } else { 0 }

Info "готово:"
Info "  node.exe:      $nodeNote"
Info "  node_modules:  $nmSizeMb МБ"
Info "  сервер:        src\, public\, scripts\, package.json"
Info "  модель:        $modelNote"
Info "Проверка структуры:  bash window/packaging/windows/sidecar/verify-sidecar.sh '$SidecarDir'"
