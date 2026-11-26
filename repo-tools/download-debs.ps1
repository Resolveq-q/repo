<#
    download-debs.ps1 — скачивает нужные .deb в папку debs/ прямо с ПК.

    Зачем: у тебя на iPhone репозитории отдают 522 (Cloudflare), а с ПК те же
    файлы качаются нормально. Качаем на компьютер — телефон потом берёт их
    уже с твоего собственного GitHub-репозитория.

    Запуск (из корня репозитория):
        powershell -ExecutionPolicy Bypass -File repo-tools\download-debs.ps1
        powershell -ExecutionPolicy Bypass -File repo-tools\download-debs.ps1 -Rootful

    По умолчанию качаются ОБА варианта (rootful iphoneos-arm и rootless
    iphoneos-arm64) — Sileo/Zebra сами выберут нужный под твой джейлбрейк.
#>

[CmdletBinding()]
param(
    [switch]$Rootful,   # только rootful (iphoneos-arm)
    [switch]$Rootless,  # только rootless (iphoneos-arm64)
    [switch]$WithTheme  # + бесплатная тема иконок Morandi (SnowBoard), ~5.8 МБ
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

    # ---- RemoteCompanion: привязка жестов, в т.ч. от статус-бара -----------
    # нужен, чтобы Пункт управления открывался сверху (жест от верхнего края)
    @{ Name = 'com.saihgupr.remotecompanion_4.4.0_iphoneos-arm.deb';
       Url  = 'https://havoc.app/api/download/package/6af9a44fcfe2bcdc1fc06e6f/rootful.deb'; Arch = 'arm' }
    @{ Name = 'com.saihgupr.remotecompanion_4.4.0_iphoneos-arm64.deb';
       Url  = 'https://havoc.app/api/download/package/6af9a44fcfe2bcdc1fc06e6f/com.saihgupr.remotecompanion_4.4.0_iphoneos-arm64.deb'; Arch = 'arm64' }
)

if ($WithTheme) {
    $items += @(
        @{ Name = 'com.rowandesign.morandi_1.1.0_iphoneos-arm.deb';
           Url  = 'https://havoc.app/api/download/package/643fd6bf19a7b92188411a5b/Morandi_1.1.0.deb'; Arch = 'arm' }
        @{ Name = 'com.rowandesign.morandi_1.1.0_iphoneos-arm64.deb';
           Url  = 'https://havoc.app/api/download/package/643fd6bf19a7b92188411a5b/com.rowandesign.morandi_1.1.0_iphoneos-arm64.deb'; Arch = 'arm64' }
    )
}

$wanted = @()
if ($Rootful)  { $wanted += 'arm' }
if ($Rootless) { $wanted += 'arm64' }

$ok = 0; $fail = 0
foreach ($it in $items) {
    if ($wanted -notcontains $it.Arch) { continue }
    $dest = Join-Path $debDir $it.Name
    try {
        Write-Host ("-> {0}" -f $it.Name) -ForegroundColor Cyan
        Invoke-WebRequest -Uri $it.Url -OutFile $dest -UseBasicParsing -TimeoutSec 120
        $sizeKb = [math]::Round((Get-Item $dest).Length / 1KB, 1)
        Write-Host ("   OK, {0} KB" -f $sizeKb) -ForegroundColor Green
        $ok++
    }
    catch {
        Write-Host ("   FAIL: {0}" -f $_.Exception.Message) -ForegroundColor Red
        if (Test-Path $dest) { Remove-Item $dest -Force }
        $fail++
    }
}

Write-Host ""
Write-Host ("Скачано: {0}, с ошибками: {1}" -f $ok, $fail)
Write-Host "Дальше: python repo-tools\gen-repo.py   (локальная проверка сборки индекса)"
if ($fail -gt 0) { exit 1 }
