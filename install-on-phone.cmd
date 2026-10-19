@echo off
chcp 65001 >nul
rem Двойной щелчок: свежая версия с GitHub, сборка и установка OwnMedia на Android-телефон по USB.
cd /d "%~dp0"
set "BASH=%ProgramFiles%\Git\bin\bash.exe"
if not exist "%BASH%" (
  echo Не найден Git Bash: %BASH%
  echo Поставьте Git для Windows: winget install --id Git.Git -e
  goto :end
)
echo Скачиваю свежую версию с GitHub...
git pull --ff-only
if errorlevel 1 (
  echo.
  echo Не получилось скачать обновление. Пришлите этот текст Claude.
  goto :end
)
echo.
echo Собираю и ставлю на телефон. Телефон должен быть подключён кабелем и разблокирован.
echo Первая сборка идёт несколько минут. Когда приложение откроется на телефоне, окно можно закрыть.
echo Если что-то пошло не так, пришлите Claude последние строки из этого окна.
echo.
"%BASH%" app/build.sh run
:end
echo.
pause
