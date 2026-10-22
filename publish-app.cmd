@echo off
chcp 65001 >nul
rem Двойной щелчок: свежая версия с GitHub, подписанный файл приложения для друзей и для сайта.
rem Приглашения с сервера сразу раздают новую версию; копия для сайта - app\dist\site\OwnMedia.apk.
cd /d "%~dp0"
set "BASH=%ProgramFiles%\Git\bin\bash.exe"
echo Скачиваю свежую версию с GitHub...
git pull --ff-only
if errorlevel 1 goto :fail
echo.
echo Собираю подписанное приложение. Это несколько минут.
"%BASH%" app/build.sh apk
if errorlevel 1 goto :fail
for /f "delims=" %%f in ('dir /b /o-d "app\dist\OwnMedia-*.apk"') do (set "APK=app\dist\%%f" & goto :found)
:found
powershell -NoProfile -ExecutionPolicy Bypass -File tools\publish-app.ps1 -Apk "%APK%"
if errorlevel 1 goto :fail
echo.
echo Готово. Осталось залить на сайт новые файлы из папки site\ (или архив ownmedia-site.zip):
echo download\OwnMedia.apk, downloadersion.json, страницы с номером версии и sitemap.xml.
goto :end
:fail
echo.
echo Что-то пошло не так. Пришлите Claude последние строки из этого окна.
:end
echo.
pause
