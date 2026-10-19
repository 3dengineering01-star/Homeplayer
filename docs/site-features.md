# Тексты для сайта: возможности и «Что нового»

Для сессии, которая ведёт сайт (ownmedia.app). Основной язык сайта — английский, русский — второй.
Блоки ниже заменяют устаревшие (в старом лендинге «Android Auto … planned», «In development» и т. п.).
Скриншоты — только с демо-сервера, без личных фото и имён (см. `docs/site-brief.md`, раздел 5).
Про iPhone пока не писать: версия есть, но в App Store её нет.

## Download (кнопка и подпись)

**EN**
- Button: `Download for Android` → `/download/OwnMedia.apk`
- Under it: `Version 0.3.14 for Android phones. If the phone warns about an unknown developer, tap More details → Install anyway. The app tells you when a new version is out.`
- Small: `Coming to Google Play.`

**RU**
- Кнопка: `Скачать для Android`
- Под ней: `Версия 0.3.14 для телефонов на Android. Если телефон предупредит о неизвестном разработчике, нажмите «Подробнее» → «Всё равно установить». О новых версиях приложение скажет само.`
- Мелко: `Скоро в Google Play.`

(Номер версии брать из `app/dist/site/version.json` после `publish-app.cmd`.)

## Features (блоки на главной)

### Music, done properly / Музыка как надо
**EN.** A home for your music: recently added, recently played, most played and favorites. Instant Mix plays
songs like the one you love. Lyrics follow the song, line by line. Albums play without gaps, and you see the
real format: FLAC · 24-bit · 96 kHz. The queue is still there after a restart.

**RU.** Главная для вашей музыки: недавно добавленное, недавно слушали, чаще всего и избранное. Instant Mix
играет песни, похожие на любимую. Тексты идут вместе с песней, строка за строкой. Альбомы без пауз между
треками, и видно настоящий формат: FLAC · 24-bit · 96 kHz. Очередь остаётся и после перезапуска.

### Plays through bad coverage / Играет и при плохой связи
**EN.** While you listen, the next songs are saved on the phone, so the music goes on in tunnels, lifts and on
the train. On mobile data, choose 320, 192 or 128 kbps and save your plan.

**RU.** Пока вы слушаете, следующие песни сохраняются на телефоне — музыка не прерывается в туннеле, лифте и
поезде. В мобильной сети выберите 320, 192 или 128 kbps и сэкономьте трафик.

### Plays every file / Играет любой файл
**EN.** Built on mpv: MKV, HEVC, AV1, DTS, Dolby, FLAC and styled ASS subtitles, as they are, no waiting for
the server to convert.

**RU.** Основан на mpv: MKV, HEVC, AV1, DTS, Dolby, FLAC и субтитры ASS со всем оформлением — как есть, без
ожидания, пока сервер пережмёт.

### Share with friends / Поделитесь с друзьями
**EN.** Send a link. Your friend gets the app and joins your server with one tap — no password, no setup.
You see who watches what, and end access with one button.

**RU.** Отправьте ссылку. Друг ставит приложение и входит на ваш сервер одним нажатием — без пароля и
настроек. Вы видите, кто что смотрит, и закрываете доступ одной кнопкой.

### Your photos, on your server / Ваши фото — на вашем сервере
**EN.** New photos and videos go to your own server seconds after you take them. No cloud, no monthly fee.

**RU.** Новые фото и видео уходят на ваш собственный сервер через несколько секунд после съёмки. Без облака и
абонентской платы.

### On the TV and in the car / На телевизоре и в машине
**EN.** Play on your TV over the home Wi-Fi. Android Auto with your music and voice search.

**RU.** Показ на телевизоре по домашнему Wi-Fi. Android Auto с вашей музыкой и голосовым поиском.

### No strings / Без лишнего
**EN.** No account, no ads, no analytics. The app talks to your servers — and, only if you allow it, to LRCLIB
for lyrics.

**RU.** Без учётной записи, рекламы и аналитики. Приложение общается с вашими серверами — и, только если вы
разрешите, с LRCLIB за текстами песен.

## What's new in 0.3.14 / Что нового в 0.3.14

**EN**
- Home tab for music on Jellyfin and Navidrome: recently added, recently played, most played, favorites.
- Instant Mix from any song, album or artist.
- Synced lyrics, from your server or LRCLIB.
- Gapless albums; the sound format under the seek bar.
- Songs ahead: the next songs are saved on the phone and play without a connection.
- Data saver for music on mobile data.
- The queue survives a restart; swipe the mini player to change songs; letters on the side of long lists.
- Invites download the newest app from ownmedia.app; the app tells you about new versions.
- Fixed: notification buttons after a long pause.

**RU**
- Вкладка Home для музыки в Jellyfin и Navidrome: недавно добавленное, недавно слушали, чаще всего, избранное.
- Instant Mix от любой песни, альбома или исполнителя.
- Тексты песен под музыку, с вашего сервера или LRCLIB.
- Альбомы без пауз; формат звука под полосой прокрутки.
- Песни наперёд: следующие песни сохраняются на телефоне и играют без связи.
- Экономия трафика для музыки в мобильной сети.
- Очередь сохраняется после перезапуска; смахивание мини-плеера; буквы сбоку в длинных списках.
- Приглашения скачивают свежую версию с ownmedia.app; приложение само сообщает о новых версиях.
- Исправлено: кнопки в шторке после долгой паузы.
