# Homeplay Backup — плагин Jellyfin

Принимает фото и видео из приложения Homeplay и складывает их в папку на сервере:
`<папка>\<пользователь Jellyfin>\<телефон>\<год>\<месяц>\<файл>`. Дата файла — дата съёмки.

- Загрузка кусками с докачкой после обрыва. Уже полученный файл второй раз не принимается.
- Служебные данные (недокачанные файлы, список полученных) лежат в `<папка>\.homeplay`.
- Пока администратор не задал папку, загрузка отклоняется.

## API (нужен вход пользователя Jellyfin)

- `GET /HomeplayBackup/Info` → `{ Version, Configured }`.
- `POST /HomeplayBackup/Check` с телом `{ Device, Ids: [...] }` → для каждого id `{ Id, Done, Offset }`.
- `PUT /HomeplayBackup/Upload?device=&id=&name=&size=&takenAt=&offset=`, тело — байты куска (до 64 МБ).
  Ответ `{ Id, Done, Offset }`. Если кусок начинается не там, где кончается копия на сервере, ответ 409 с правильным `Offset`.

## Сборка и тесты

```bash
dotnet test server/Jellyfin.Plugin.HomeplayBackup.Tests
dotnet build server/Jellyfin.Plugin.HomeplayBackup -c Release
```

## Установка вручную

1. Скопировать `Jellyfin.Plugin.HomeplayBackup.dll` из `bin/Release/net10.0` в
   `C:\ProgramData\Jellyfin\Server\plugins\Homeplay Backup_1.0.0.0\`.
2. Перезапустить Jellyfin.
3. Панель управления → Плагины → Homeplay Backup: указать папку для фото.
