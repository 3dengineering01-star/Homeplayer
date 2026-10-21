#!/usr/bin/env bash
# Каталог модулей Jellyfin для «Homeplay Backup»: собирает модуль, кладёт его zip и manifest.json
# в jellyfin-repo/. Jellyfin (Панель управления → Плагины → Репозитории) берёт каталог по адресу
#   https://raw.githubusercontent.com/3dengineering01-star/Homeplayer/main/jellyfin-repo/manifest.json
# и ставит модуль одной кнопкой — на любом сервере: Synology, другой NAS, Docker, Linux, Windows.
#
# Запуск из корня репозитория: tools/make_plugin_repo.sh. Нужен .NET SDK (в облаке его ставит хук).
# В zip нет приложения (OwnMedia.apk) и установщика: они большие для git. Страница приглашения и
# QR-код ведут за приложением на сайт (https://ownmedia.app/download/OwnMedia.apk, PhoneLink.AppUrl).
set -euo pipefail

repo=3dengineering01-star/Homeplayer
raw="https://raw.githubusercontent.com/$repo/main/jellyfin-repo"
project=server/Jellyfin.Plugin.HomeplayBackup
out=jellyfin-repo

dotnet build "$project" -c Release -nologo -v quiet
bin="$project/bin/Release/net10.0"
version=$(sed -n 's:.*<Version>\(.*\)</Version>.*:\1:p' "$project/Jellyfin.Plugin.HomeplayBackup.csproj")
abi=$(sed -n 's:.*Include="Jellyfin.Controller" Version="\([^"]*\)".*:\1:p' "$project/Jellyfin.Plugin.HomeplayBackup.csproj").0
zip_name="homeplay-backup_$version.zip"

mkdir -p "$out"
rm -f "$out"/homeplay-backup_*.zip
stage=$(mktemp -d)
cp "$bin/Jellyfin.Plugin.HomeplayBackup.dll" "$bin/QRCoder.dll" "$stage/"
cp server/LICENSE "$stage/LICENSE.txt"
cp server/THIRD-PARTY-NOTICES.txt "$stage/"
# Fixed dates inside the zip: the same build gives the same file and the same checksum.
find "$stage" -exec touch -d '2026-01-01 00:00:00' {} +
(cd "$stage" && zip -X -q "$OLDPWD/$out/$zip_name" ./*)
rm -rf "$stage"
checksum=$(md5sum "$out/$zip_name" | cut -d' ' -f1)

cat > "$out/manifest.json" <<EOF
[
  {
    "guid": "ca1d038a-d3f7-4ef4-9839-1e93a8105618",
    "name": "Homeplay Backup",
    "description": "OwnMedia: photo backup from the phone, invites for friends, the phone page with a QR code.",
    "overview": "The server side of the OwnMedia app for Android.",
    "owner": "OwnMedia",
    "category": "General",
    "imageUrl": "https://raw.githubusercontent.com/$repo/main/docs/play/icon-512.png",
    "versions": [
      {
        "version": "$version",
        "changelog": "See https://github.com/$repo",
        "targetAbi": "$abi",
        "sourceUrl": "$raw/$zip_name",
        "checksum": "$checksum",
        "timestamp": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
      }
    ]
  }
]
EOF
echo "Готово: $out/$zip_name ($checksum), $out/manifest.json, Jellyfin $abi и новее"
