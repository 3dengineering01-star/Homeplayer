# OwnMedia на Synology

Сервер для OwnMedia на NAS Synology: Jellyfin в Container Manager и наш модуль «Homeplay Backup» из
каталога модулей. Установщик для Windows здесь не нужен. Займёт около получаса, один раз.

Что получится: фильмы, сериалы, музыка и фото с NAS на телефоне, копия фото с телефона на NAS,
приглашения друзьям, доступ из интернета.

## 1. Можно ли на этом NAS

Откройте **Центр пакетов** и найдите **Container Manager**. Если он есть — дальше по этой инструкции.

Если его нет (младшие модели), Jellyfin ставится пакетом SynoCommunity, но там обычно старая версия, а
наш модуль работает с Jellyfin 12.1 и новее. В этом случае напишите — подберём другой путь.

## 2. Папки

В **File Station** создайте:

- `docker/jellyfin/config` и `docker/jellyfin/cache` — для самого Jellyfin;
- папку для копий фото с телефона, например `photo/OwnMedia`.

Фильмы, сериалы и музыку оставьте там, где они лежат; ниже нужны только пути к их папкам (например,
`/volume1/video`, `/volume1/music`). Путь видно в File Station: правой кнопкой по папке → «Свойства».

## 3. Jellyfin в Container Manager

**Container Manager → Проект → Создать**:

- Имя проекта: `ownmedia`
- Путь: `/volume1/docker/jellyfin`
- Источник: «Создать docker-compose.yml», и вставить (пути к своим папкам поправить):

```yaml
services:
  jellyfin:
    image: jellyfin/jellyfin:12.1
    container_name: jellyfin
    # Сеть NAS напрямую: телефон находит сервер в Wi-Fi сам («Add your server»).
    network_mode: host
    restart: unless-stopped
    volumes:
      - /volume1/docker/jellyfin/config:/config
      - /volume1/docker/jellyfin/cache:/cache
      - /volume1/video:/media/video:ro
      - /volume1/music:/media/music:ro
      - /volume1/photo/OwnMedia:/media/photos
```

Далее → Готово. Container Manager скачает Jellyfin (около 300 МБ) и запустит.

`:ro` — только чтение: Jellyfin не может ничего изменить в фильмах и музыке. Папка фото — без `:ro`,
туда записываются копии с телефона.

## 4. Первая настройка Jellyfin

В браузере на компьютере откройте `http://<адрес NAS>:8096` (адрес NAS — тот же, по которому открывается
DSM, например `http://192.168.1.50:8096`):

1. Язык → создать пользователя: имя и пароль (их вы введёте в телефоне).
2. Медиатеки: «Фильмы» → папка `/media/video`, «Музыка» → `/media/music`, при желании «Фото» →
   `/media/photos`.
3. Удалённый доступ — оставить включённым. Готово.

## 5. Модуль OwnMedia

В Jellyfin: **Панель управления → Плагины → Каталог → ⚙ (Репозитории) → +**:

- Имя: `OwnMedia`
- Адрес: `https://raw.githubusercontent.com/3dengineering01-star/Homeplayer/main/jellyfin-repo/manifest.json`

Сохранить → в **Каталоге** появится **Homeplay Backup** → Установить → **Панель управления →
Перезапуск** (кнопка вверху). После перезапуска модуль в «Моих плагинах» со статусом «Активен».

Там же, в настройках модуля **Homeplay Backup**, укажите папку для копий фото: `/media/photos`.

Новые версии модуля Jellyfin показывает сам, в «Плагинах».

## 6. Телефон

В OwnMedia: **Add your server** — NAS найдётся сам, если телефон в том же Wi-Fi. Если нет — адрес
`<адрес NAS>:8096`. Имя и пароль из шага 4.

Страница с QR-кодом для телефонов: `http://<адрес NAS>:8096/Homeplay/Phone`.

## 7. Доступ из интернета и приглашения друзьям (Tailscale)

1. **Центр пакетов → Tailscale** → установить → открыть → войти своим аккаунтом Tailscale.
2. Включить Funnel для Jellyfin: **Панель управления DSM → Планировщик задач → Создать → Задача,
   запускаемая по событию → Пользовательский сценарий**: пользователь `root`, событие «Загрузка», во
   вкладке «Параметры задачи» сценарий:

   ```sh
   /var/packages/Tailscale/target/bin/tailscale funnel --bg 8096
   ```

   Сохранить, затем выбрать задачу → **Выполнить**. Если Tailscale попросит разрешить Funnel, он покажет
   ссылку в результатах задачи (или в журнале) — откройте её и нажмите **Enable Funnel**.
3. Адрес NAS в интернете — `https://<имя NAS>.<ваша сеть>.ts.net` (виден в Tailscale → Machines).
   В OwnMedia: меню сервера ⋮ → **Share with friends** → «I have an address already» → этот адрес.

Шаг 7 на Synology пока не проверен на настоящем NAS: если что-то пойдёт не так — пришлите, что
показала задача.

## Приложение для друзей

На Windows установщик кладёт приложение (`OwnMedia.apk`) рядом с модулем, и страница приглашения даёт
его скачать. Из каталога модуль ставится без приложения (оно большое), поэтому страница приглашения
ведёт в Google Play. Пока приложения там нет, положите `OwnMedia.apk` через File Station в папку
модуля: `docker/jellyfin/config/plugins/Homeplay Backup_<версия>/` — страница приглашения и QR-код
сразу начнут давать его скачать.
