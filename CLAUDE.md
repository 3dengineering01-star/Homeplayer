# Homeplay

Android-плеер музыки и видео с домашнего сервера: Jellyfin (видео и музыка) и Navidrome/Subsonic (музыка).
Flutter + media_kit (libmpv), direct play без транскодирования. Подробности и список возможностей в `README.md`.

## Структура

- `app/` — Flutter-приложение (пакет `homeplay`), целевая платформа Android.
  - `lib/api/` — клиенты серверов: `jellyfin.dart`, `subsonic.dart`, общее в `common.dart`
    (`PlayItem`, `PlaybackReporter`, список кодеков, которые декодирует libmpv), автопоиск Jellyfin в `discovery.dart`.
  - `lib/services/playback.dart` — единственный плеер приложения (`Playback`, audio_service): очередь,
    медиауведомление, аудиофокус, отчёты о прогрессе на сервер, выбор и запоминание дорожек.
  - `lib/services/track_choice.dart` — чистые функции выбора аудио и субтитров (покрыты тестами).
  - `lib/services/account_store.dart` — аккаунты; токены в flutter_secure_storage, пароль не хранится.
  - `lib/screens/`, `lib/widgets/` — UI.
  - `test/common_test.dart` — юнит-тесты.
- `server/` — плагин Jellyfin «Homeplay Backup» (C#, .NET 10, Jellyfin 12.1): принимает фото и видео
  с телефона. Логика хранения в `BackupStore.cs` (покрыта тестами), HTTP API в `Api/BackupController.cs`.
  Подробности в `server/README.md`.
- `landing/index.html` — лендинг с листом ожидания (Formspree).
- `docs/validation.md` — план проверки спроса.
- `tools/phone.sh` — управление телефоном через adb (только локально).

## Команды

В облачной сессии Flutter ставит хук `.claude/hooks/session-start.sh` в `/opt/flutter` (версия как локально, 3.47.5):

```bash
cd app
flutter analyze   # линтер, должен быть "No issues found!"
flutter test      # юнит-тесты
```

Плагин (в облаке .NET SDK ставит тот же хук):

```bash
dotnet test server/Jellyfin.Plugin.HomeplayBackup.Tests
dotnet build server/Jellyfin.Plugin.HomeplayBackup -c Release
```

Локально (Windows, тулчейн в `D:\APP\tools`) то же через `./app/build.sh test`, `./app/build.sh` и т. д.

В облаке нет Android SDK и телефона: APK там не собрать и приложение не запустить. Изменения проверяются
анализатором и тестами, на устройстве — локально.

## Соглашения

- С пользователем общаться только на русском, все сообщения целиком, простыми словами без жаргона.
- Комментарии в коде и сообщения в UI на английском, документация и коммиты на русском.
- Окончания строк LF (`.gitattributes`).
- Логи приложения с префиксом `homeplay`; токены и URL с токеном в лог не пишутся.
- Новую логику, которую можно отделить от плеера и сети, выносить в чистые функции и покрывать тестами.
