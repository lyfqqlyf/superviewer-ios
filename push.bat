@echo off
cd /d "%~dp0"
title SuperViewer iOS - push to GitHub
where git >nul 2>nul || (echo [ERROR] git not installed. https://git-scm.com & pause & exit /b 1)

if not exist .git (
    echo [INIT] creating git repository ...
    git init -b main >nul
    git config user.name  >nul 2>nul || git config user.name  "superviewer"
    git config user.email >nul 2>nul || git config user.email "superviewer@local"
)

git add .
set "MSG=SuperViewer iOS update"
git commit -m "%MSG%" >nul 2>nul
if errorlevel 1 (
    echo [SKIP] no new changes to commit
) else (
    echo [COMMIT] %MSG%
)

git remote get-url origin >nul 2>nul
if errorlevel 1 (
    echo.
    set /p REMOTE=Paste your repo URL (https://github.com/YOU/superviewer-ios.git):
    if "%REMOTE%"=="" (echo [ERROR] repo URL required & pause & exit /b 1)
    git remote add origin "%REMOTE%"
)

echo.
echo [PUSH] first push will open a browser for GitHub login ...
git push -u origin main
if errorlevel 1 (
    echo.
    echo [FAILED] common causes:
    echo   1. repo not created yet - create an EMPTY repo on github.com first
    echo   2. no permission - run this script again to login again
) else (
    echo.
    echo [OK] open your repo page - Actions - Build IPA - Run workflow
)
echo.
pause
