@echo off
chcp 65001 >nul
rem 개발 시작: Rojo를 켜고, 30초마다 GitHub에서 새 코드를 받는다 (Pull origin 자동)
rem 이 창을 닫으면 자동 받기가 멈춘다. Rojo 창은 따로 닫는다
cd /d "%~dp0"
title 자동 업데이트 (닫으면 멈춤)

rem git 찾기: 설치된 git이 없으면 GitHub Desktop 안에 들어 있는 git을 쓴다
set "GIT=git"
where git >nul 2>nul
if errorlevel 1 (
  for /d %%D in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do (
    if exist "%%D\resources\app\git\cmd\git.exe" set "GIT=%%D\resources\app\git\cmd\git.exe"
  )
)
set GIT_TERMINAL_PROMPT=0

rem Rojo는 새 창에서
start "Rojo" cmd /k rojo serve

echo 자동 업데이트를 시작해요. 30초마다 새 코드를 확인해요.
:loop
for /f %%H in ('"%GIT%" rev-parse HEAD') do set "BEFORE=%%H"
"%GIT%" pull --ff-only -q >nul 2>nul
if errorlevel 1 echo [%time%] 새 코드를 못 받았어요. GitHub Desktop에서 Pull origin을 한 번 눌러 확인해 주세요.
for /f %%H in ('"%GIT%" rev-parse HEAD') do set "AFTER=%%H"
if not "%BEFORE%"=="%AFTER%" echo [%time%] 새 코드를 받았어요! Studio에서 정지 후 다시 플레이하세요.
timeout /t 30 /nobreak >nul
goto loop
