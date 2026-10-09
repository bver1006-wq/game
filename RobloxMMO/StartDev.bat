@echo off
rem StartDev: start Rojo, then pull new code from GitHub every 30 seconds.
rem Closing this window stops auto-update. Close the Rojo window separately.
cd /d "%~dp0"
title Auto update - close to stop

set "GIT=git"
where git >nul 2>nul
if errorlevel 1 (
  for /d %%D in ("%LOCALAPPDATA%\GitHubDesktop\app-*") do (
    if exist "%%D\resources\app\git\cmd\git.exe" set "GIT=%%D\resources\app\git\cmd\git.exe"
  )
)
set GIT_TERMINAL_PROMPT=0

"%GIT%" --version >nul 2>nul
if errorlevel 1 (
  echo [ERROR] git not found. Install GitHub Desktop or Git for Windows.
  pause
  exit /b 1
)

start "Rojo" cmd /k rojo serve

echo Auto update started. Checking GitHub every 30 seconds...
:loop
for /f %%H in ('call "%GIT%" rev-parse HEAD') do set "BEFORE=%%H"
"%GIT%" pull --ff-only -q
if errorlevel 1 echo [%time%] [ERROR] Could not pull. Take a screenshot of this window.
for /f %%H in ('call "%GIT%" rev-parse HEAD') do set "AFTER=%%H"
if not "%BEFORE%"=="%AFTER%" echo [%time%] NEW CODE DOWNLOADED. In Studio: Stop, then Play again.
timeout /t 30 /nobreak >nul
goto loop
