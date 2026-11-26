<#
    download-debs.ps1 — скачивает базовые .deb в папку debs/ прямо с ПК.

    Зачем: на iPhone чужие репозитории отдают 522 (Cloudflare + фильтрация у
    провайдера), а телефон потом берёт те же файлы уже из твоего репозитория.

    Запуск (из корня репозитория):
        powershell -ExecutionPolicy Bypass -File repo-tools\download-debs.ps1

    По умолчанию качаются ОБА варианта (rootful iphoneos-arm и rootless
    iphoneos-arm64) — Sileo/Zebra сами выберут нужный под твой джейлбрейк.

    Устройство безопасное: файл сначала пишется как .part, проверяется и только
    потом заменяет готовый .deb. Уже скачанные файлы не перекачиваются
    (перекачать принудительно: -Force).

    ВАЖНО: остальные пакеты (RemoteCompanion, тема Morandi) не качаются здесь —
    они перечислены в extras.txt и их скачивает сам GitHub Actions, где нет
    российской фильтрации трафика.
#>

[CmdletBinding()]
param(
    [switch]$Rootful,   # только rootful (iphoneos-arm)
    [switch]$Rootless,  # только rootless (iphoneos-arm64)
    [switch]$Force      # перекачать даже то, что уже есть
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$debDir = Join-Path $root 'debs'
New-Item -ItemType Directory -Force -Path $debDir | Out-Null

if (-not $Rootful -and -not $Rootless) { $Rootful = $true; $Rootless = $true }

$items = @(
    # ---- SnowBoard: движок тем (иконки, UI, статус-бар) -------------------
    @{ Name = 'com.spark.snowboard_1.5.37-Beta4_iphoneos-arm.deb';
       Url  = 'https://sparkdev.me/download/com.spark.snowboard/1.5.37-Beta4.deb'; Arch = 'arm' }
    @{ Name = 'com.spark.snowboard_1.5.37-Beta4_iphoneos-arm64.deb';
       Url  = 'https://sparkdev.me/download/com.spark.snowboard/1.5.37-Beta4-rootless.deb'; Arch = 'arm64' }

    # ---- GesturesXV: полоска Home + жесты как на iPhone X -----------------
    @{ Name = 'com.nahtedetihw.gesturesxv_1.6_iphoneos-arm.deb';
       Url  = 'https://havoc.app/api/download/package/645592a94ab1374a97160be8/com.nahtedetihw.gesturesxv_1.6_iphoneos-arm.deb'; Arch = 'arm' }
    @{ Name = 'com.nahtedetihw.gesturesxv_1.6_iphoneos-arm64.deb';
       Url  = 'https://havoc.app/api/download/package/645592a94ab1374a97160be8/com.nahtedetihw.gesturesxv_1.6_iphoneos-arm64.deb'; Arch = 'arm64' }

    # ---- Speedster: ускорение анимаций = ощущение "плавности" -------------
    @{ Name = 'com.hoangdus.speedster_2.1.2_iphoneos-arm.deb';
       Url  = 'https://havoc.app/api/download/package/698560276424d27e7aea436c/com.hoangdus.speedster_2.1.2_iphoneos-arm.deb'; Arch = 'arm' }
    @{ Name = 'com.hoangdus.speedster_2.1.2_iphoneos-arm64.deb';
       Url  = 'https://havoc.app/api/download/package/698560276424d27e7aea436c/com.hoangdus.speedster_2.1.2_iphoneos-arm64.deb'; Arch = 'arm64' }
)

function Test-Deb([string]$path) {
    if (-not (Test-Path $path)) { return $false }
    if ((Get-Item $path).Length -lt 1000) { return $false }
    $fs = [IO.File]::OpenRead($path)
    try {
        $buf = New-Object byte[] 8
        $n = $fs.Read($buf, 0, 8)
    }
    finally { $fs.Dispose() }
    if ($n -lt 8) { return $false }
    return ([Text.Encoding]::ASCII.GetString($buf, 0, 7) -eq '!<arch>')
}

$wanted = @()
if ($Rootful)  { $wanted += 'arm' }
if ($Rootless) { $wanted += 'arm64' }

$ok = 0; $skip = 0; $fail = 0
foreach ($it in $items) {
    if ($wanted -notcontains $it.Arch) { continue }
    $dest = Join-Path $debDir $it.Name
    $part = "$dest.part"

    if (-not $Force -and (Test-Deb $dest)) {
        Write-Host ("-- {0} уже есть, пропускаю" -f $it.Name) -ForegroundColor DarkGray
        $skip++
        continue
    }

    try {
        Write-Host ("-> {0}" -f $it.Name) -ForegroundColor Cyan
        if (Test-Path $part) { Remove-Item $part -Force }
        Invoke-WebRequest -Uri $it.Url -OutFile $part -UseBasicParsing -TimeoutSec 180 `
            -Headers @{ 'User-Agent' = 'Sileo/2.5 CFNetwork/1335.0.3 Darwin/21.6.0' }
        if (-not (Test-Deb $part)) { throw "скачался не .deb (обрыв соединения?)" }
        Move-Item -Force $part $dest
        Write-Host ("   OK, {0} KB" -f [math]::Round((Get-Item $dest).Length / 1KB, 1)) -ForegroundColor Green
        $ok++
    }
    catch {
        Write-Host ("   FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
        if (Test-Path $part) { Remove-Item $part -Force }
        $fail++
    }
}

Write-Host ""
Write-Host ("Скачано: {0}, пропущено (уже были): {1}, ошибок: {2}" -f $ok, $skip, $fail)
Write-Host "Дальше: python repo-tools\gen-repo.py   (локальная проверка сборки индекса)"
if ($fail -gt 0) { exit 1 }
