#!/bin/bash
# Облачная сессия Claude Code: ставит Flutter (та же версия, что локально) и зависимости app/,
# чтобы работали flutter analyze и flutter test, и .NET SDK для плагина в server/. Локально ничего не делает.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

FLUTTER_VERSION=3.47.5
FLUTTER_HOME=/opt/flutter

if ! "$FLUTTER_HOME/bin/flutter" --version 2>/dev/null | grep -q "Flutter $FLUTTER_VERSION "; then
  rm -rf "$FLUTTER_HOME"
  mkdir -p "$(dirname "$FLUTTER_HOME")"
  curl -fsSL "https://storage.googleapis.com/flutter_infra_release/releases/stable/linux/flutter_linux_${FLUTTER_VERSION}-stable.tar.xz" \
    | tar -xJ -C "$(dirname "$FLUTTER_HOME")"
fi
git config --global --get-all safe.directory | grep -qx "$FLUTTER_HOME" \
  || git config --global --add safe.directory "$FLUTTER_HOME"

export PATH="$FLUTTER_HOME/bin:$PATH"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo "export PATH=\"$FLUTTER_HOME/bin:\$PATH\"" >> "$CLAUDE_ENV_FILE"
fi

flutter config --no-analytics >/dev/null
flutter --disable-analytics >/dev/null 2>&1 || true

cd "$CLAUDE_PROJECT_DIR/app"
flutter pub get

# Server plugin (server/): .NET SDK from Ubuntu's own packages.
if ! dotnet --list-sdks 2>/dev/null | grep -q '^10\.'; then
  apt-get update -qq
  DEBIAN_FRONTEND=noninteractive apt-get install -y -qq dotnet-sdk-10.0
fi
dotnet restore "$CLAUDE_PROJECT_DIR/server/Jellyfin.Plugin.HomeplayBackup.Tests" >/dev/null
