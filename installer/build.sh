#!/usr/bin/env bash
# Сборка HomeplaySetup.exe (Git Bash на Windows): APK, плагин, затем Inno Setup.
# Результат: installer/dist/HomeplaySetup.exe. Нужны android/key.properties (ключ APK) и Inno Setup 6.
#   ./installer/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."
DOTNET="${DOTNET:-/d/APP/tools/dotnet/dotnet}"
ISCC="${ISCC:-/d/APP/tools/InnoSetup/ISCC.exe}"
./app/build.sh apk
"$DOTNET" build server/Jellyfin.Plugin.HomeplayBackup -c Release
"$ISCC" installer/HomeplaySetup.iss
echo "Готово: installer/dist/HomeplaySetup.exe"
