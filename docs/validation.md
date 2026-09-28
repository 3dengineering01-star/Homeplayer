# Проверка спроса: 1 месяц

Цель: до основных месяцев разработки понять, есть ли люди, которые ждут такой плеер.

## Порог решения (через 30 дней после публикации)

| Подписок в листе ожидания | Решение |
|---|---|
| 300+ | Идём дальше по плану, Android-бета через 2–3 месяца |
| 100–300 | Смотрим ответы: кто и что просит. Возможно, сузить нишу (только видео или только музыка) |
| < 100 | Пересмотреть идею, прежде чем тратить месяцы |

Второй сигнал — вопрос о цене. Если «Yes» + «Maybe» меньше 40%, модель разовой покупки под вопросом.

## Что нужно сделать вам (я этого сделать не могу)

1. **Бэкенд формы.** ✅ Formspree подключён (`FORM_ENDPOINT` в `landing/index.html`).
   Форма шлёт заявки через JavaScript, поэтому CAPTCHA в настройках Formspree должна оставаться выключенной
   (проверено 28.09.2026: Disabled, Formshield включён). После размещения один раз отправить тестовую заявку и удалить её в панели Formspree.
2. **Хостинг.** ✅ Временно на https://educonsalt.com (Hostinger, тариф Business, сайт создан 28.09.2026). Когда имя будет выбрано, купить домен и перенести.
3. **Имя.** «Homeplay» рабочее. До публикации проверить, что имя не занято в Google Play и нет конфликта по товарному знаку.
4. **Публикация постов.** Ниже черновики. Правила сабреддитов меняются, перед постом их стоит перечитать.
   В r/selfhosted посты о своих проектах разрешены, но без агрессивной рекламы.

## Черновик: r/jellyfin

**Title:** I'm building an Android player for Jellyfin + Navidrome that uses mpv. What would make you switch?

> Hi all. I'm working on an Android app that plays both video (Jellyfin) and music (Jellyfin or Navidrome/Subsonic) in one place, with mpv under the hood so MKV, HEVC, DTS/TrueHD and ASS subtitles direct-play instead of transcoding.
>
> Other goals: works away from home over Tailscale with no port forwarding, offline downloads, no account, no ads, no telemetry. The core player is free, extras are a one-time purchase.
>
> It's early. I have a working prototype that logs in, browses libraries and plays. Before going further I'd like to hear from you:
>
> - What's the one thing your current Android client gets wrong?
> - Do you use separate apps for music and video today? Would one app be better, or do you prefer them separate?
>
> Waitlist, if you want to try the beta: https://educonsalt.com

## Черновик: r/selfhosted

**Title:** Plex made remote streaming paid, so I'm building an Infuse-style player for Jellyfin on Android

> After Plex put remote playback behind a paywall, a lot of people moved to Jellyfin. On iOS there's Infuse, but Android still has no equivalent.
>
> I'm building one: an mpv-based player for Jellyfin (video) and Navidrome/Subsonic (music) in one app. It connects over Tailscale out of the box, has no account and no tracking, and the full version is a one-time purchase.
>
> Prototype works (login, browse, direct play). Looking for early testers and honest feedback on what matters most to you.
>
> Waitlist: https://educonsalt.com

## Где ещё

- r/navidrome, r/androidapps (после появления беты), r/DataHoarder (осторожно, только в тему).
- Форум Jellyfin (forum.jellyfin.org), раздел клиентов.
- Русскоязычные: Habr (статья «делаю плеер», а не реклама), Telegram-чаты по self-hosted.
