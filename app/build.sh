#!/usr/bin/env bash
# Сборка и запуск. Тулчейн лежит в D:\APP\tools и ставился отдельно от системы.
#   ./build.sh            debug-APK
#   ./build.sh release    release-APK
#   ./build.sh run        собрать и запустить на подключённом телефоне
#   ./build.sh test       юнит-тесты
#   ./build.sh bundle     App Bundle для Google Play (нужен android/key.properties, см. docs/play/README.md)
# Пути ниже в виде Git Bash (/d/...): Windows-программам (Gradle) их переводит MSYS. С MSYS_NO_PATHCONV=1,
# который ставят для adb, перевода нет, и Gradle не находил JAVA_HOME.
unset MSYS_NO_PATHCONV
export JAVA_HOME=/d/APP/tools/jdk-17.0.20.1+1
export ANDROID_HOME=/d/APP/tools/sdk
export PATH="/d/APP/tools/flutter/bin:$JAVA_HOME/bin:$ANDROID_HOME/platform-tools:$PATH"
cd "$(dirname "$0")"
case "${1:-debug}" in
  debug)   flutter build apk --debug ;;
  release) flutter build apk --release --split-per-abi ;;
  run)     flutter run ;;
  test)    flutter test ;;
  bundle)  flutter build appbundle --release ;;
  *)       flutter "$@" ;;
esac
