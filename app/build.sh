#!/usr/bin/env bash
# Сборка и запуск. Тулчейн лежит в D:\APP\tools и ставился отдельно от системы.
#   ./build.sh            debug-APK
#   ./build.sh release    release-APK (один файл для телефонов arm и arm64)
#   ./build.sh apk        APK для установки людям: release с ключом из android/key.properties,
#                         копия в app/dist/OwnMedia-<версия>.apk
#   ./build.sh run        собрать и запустить на подключённом телефоне (debug, для разработки, с надписью DEBUG)
#   ./build.sh phone      поставить на подключённый телефон версию как у людей: release с ключом из
#                         android/key.properties, без надписи DEBUG; потом обновляется с сайта
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
  # Chromebook) не входит, чтобы файл был меньше: его библиотеки из плагинов отсекает packaging в build.gradle.kts. Без --split-per-abi код версии равен номеру сборки
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
    cp build/app/outputs/flutter-apk/app-release.apk "dist/OwnMedia-$version.apk"
    echo "Готово: app/dist/OwnMedia-$version.apk"
    ;;
  run)     flutter run ;;
  phone)
    # Тот же ключ, что у файла на сайте: иначе обновление с сайта на этот телефон не встанет.
    if [ ! -f android/key.properties ]; then
      echo "Нет android/key.properties (ключ подписи, см. docs/play/README.md). Без него поставить можно только" >&2
      echo "пробную версию: ./build.sh run" >&2
      exit 1
    fi
    flutter build apk --release --target-platform android-arm,android-arm64 || exit 1
    apk=build/app/outputs/flutter-apk/app-release.apk
    out=$(adb install -r "$apk" 2>&1)
    echo "$out"
    if echo "$out" | grep -q "UPDATE_INCOMPATIBLE\|signatures do not match"; then
      echo
      echo "На телефоне стоит пробная версия (с надписью DEBUG), она подписана другим ключом."
      echo "Поверх неё обычную версию Android не ставит: старую нужно удалить."
      echo "После этого серверы придётся добавить заново, а скачанные на телефон фильмы и музыка удалятся."
      read -r -p "Удалить пробную версию и поставить обычную? Введите y и нажмите Enter: " answer
      case "$answer" in
        y|Y|д|Д|l|L) adb uninstall dev.homeplay.homeplay && adb install "$apk" || exit 1 ;;
        *) echo "Ничего не изменилось."; exit 1 ;;
      esac
    elif ! echo "$out" | grep -q "Success"; then
      echo "Не получилось поставить. Телефон подключён кабелем, разблокирован и разрешил отладку по USB?" >&2
      exit 1
    fi
    adb shell monkey -p dev.homeplay.homeplay -c android.intent.category.LAUNCHER 1 >/dev/null 2>&1
    echo "Готово: OwnMedia $(sed -n 's/^version: *//p' pubspec.yaml) на телефоне."
    ;;
  test)    flutter test ;;
  bundle)  flutter build appbundle --release ;;
  *)       flutter "$@" ;;
esac
