#!/usr/bin/env bash
# Сборка и запуск. Тулчейн лежит в D:\APP\tools и ставился отдельно от системы.
#   ./build.sh            debug-APK
#   ./build.sh release    release-APK (один файл для телефонов arm и arm64)
#   ./build.sh apk        APK для установки людям: release с ключом из android/key.properties,
#                         копия в app/dist/Homeplay-<версия>.apk
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
  # Один файл на все телефоны: человеку не нужно знать, какой у него процессор. x86_64 (эмуляторы,
  # Chromebook) не входит, чтобы файл был меньше. Без --split-per-abi код версии равен номеру сборки
  # из pubspec.yaml: так новый файл всегда ставится поверх старого.
  release) flutter build apk --release --target-platform android-arm,android-arm64 ;;
  apk)
    # Подписанный debug-ключом файл потом нельзя обновить файлом с настоящим ключом, только удалив приложение.
    if [ ! -f android/key.properties ]; then
      echo "Нет android/key.properties: без своего ключа APK подпишется debug-ключом. См. docs/play/README.md." >&2
      exit 1
    fi
    flutter build apk --release --target-platform android-arm,android-arm64 || exit 1
    version=$(sed -n 's/^version: *\([^+]*\).*/\1/p' pubspec.yaml)
    mkdir -p dist
    cp build/app/outputs/flutter-apk/app-release.apk "dist/Homeplay-$version.apk"
    echo "Готово: app/dist/Homeplay-$version.apk"
    ;;
  run)     flutter run ;;
  test)    flutter test ;;
  bundle)  flutter build appbundle --release ;;
  *)       flutter "$@" ;;
esac
