# Puts the fresh signed app where people get it: next to the server plugin (invite links and the
# QR code hand it out from there) and into app\dist\site\ for the website: OwnMedia.apk and version.json,
# which the app checks for a newer version. Both go to https://ownmedia.app/download/.
# Run by publish-app.cmd after the build; the app file is app\dist\OwnMedia-<version>.apk.
# Saved with a BOM: Windows PowerShell 5 reads a file without one in the old code page, and the
# Russian messages came out garbled.
param([Parameter(Mandatory = $true)] [string] $Apk)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot

# For the website: always the same name, so the site's download link never changes.
$site = Join-Path $repo 'app\dist\site'
New-Item -ItemType Directory -Force -Path $site | Out-Null
Copy-Item -Force $Apk (Join-Path $site 'OwnMedia.apk')
Write-Host "Для сайта: $site\OwnMedia.apk"

# version.json next to it: the app asks for it once a day and offers the update (app_update.dart).
$line = Select-String -Path (Join-Path $repo 'app\pubspec.yaml') -Pattern '^version:\s*([^+\s]+)\+(\d+)' | Select-Object -First 1
if (-not $line) { throw 'No version in app\pubspec.yaml' }
$version = $line.Matches[0].Groups[1].Value
$build = [int]$line.Matches[0].Groups[2].Value
$json = [ordered]@{ version = $version; build = $build; apk = 'OwnMedia.apk' } | ConvertTo-Json
# UTF-8 without a BOM: the app reads it as JSON from the website.
[System.IO.File]::WriteAllText((Join-Path $site 'version.json'), $json, (New-Object System.Text.UTF8Encoding $false))
Write-Host "Для сайта: $site\version.json ($version, сборка $build)"

# For the server: every installed copy of the plugin (Jellyfin keeps one folder per version).
$data = $null
foreach ($key in 'HKLM:\SOFTWARE\WOW6432Node\Jellyfin\Server', 'HKLM:\SOFTWARE\Jellyfin\Server') {
    $value = (Get-ItemProperty -Path $key -Name DataFolder -ErrorAction SilentlyContinue).DataFolder
    if ($value) { $data = $value; break }
}
if (-not $data) { $data = Join-Path $env:ProgramData 'Jellyfin\Server' }
$plugins = @(Get-ChildItem -Path (Join-Path $data 'plugins') -Directory -Filter 'Homeplay Backup_*' -ErrorAction SilentlyContinue)
if ($plugins.Count -eq 0) {
    Write-Host 'Модуль Homeplay Backup на этом компьютере не найден: приглашения раздают приложение с другого сервера.'
    exit 0
}
foreach ($p in $plugins) {
    try {
        # Jellyfin reads the file on each download, so it need not be stopped.
        Copy-Item -Force $Apk (Join-Path $p.FullName 'OwnMedia.apk')
        Write-Host "Для приглашений: $($p.FullName)\OwnMedia.apk"
    } catch [System.UnauthorizedAccessException] {
        Write-Host "Нет прав на папку $($p.FullName). Запустите publish-app.cmd правой кнопкой -> «Запуск от имени администратора»."
        exit 1
    }
}
