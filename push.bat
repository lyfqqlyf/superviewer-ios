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
if errorlevel 1 goto :skip_commit
echo [COMMIT] %MSG%
goto :check_remote
:skip_commit
echo [SKIP] nothing new to commit - existing commits will be pushed

:check_remote
git remote get-url origin >nul 2>nul
if errorlevel 1 goto :need_remote

echo.
echo [PUSH] pushing to GitHub. First time: a browser window opens for login ...
git push -u origin main
if errorlevel 1 goto :push_fail
echo.
echo [OK] done. Open your repo page - Actions tab - "Build IPA" - Run workflow.
git remote get-url origin
goto :end

:need_remote
echo.
echo Create an EMPTY repo on github.com first:  New repository - name superviewer-ios - Private - NO README
echo.
set /p REMOTE=Paste repo URL, like https://github.com/YourName/superviewer-ios.git :
if "%REMOTE%"=="" goto :no_url
git remote add origin "%REMOTE%"
echo [REMOTE] %REMOTE%
goto :check_remote

:no_url
echo [ERROR] repo URL required.
goto :end

:push_fail
echo.
set /p FORCE=Push rejected. Overwrite remote with local? (y/n):
if /i "%FORCE%"=="y" (
    git push -u origin main --force
    goto :end
)
echo [FAILED] common causes:
echo   1. remote has other commits - answer y to force overwrite above
echo   2. repo not created yet - create an EMPTY repo on github.com first, then re-run
echo   3. wrong URL / no permission - re-run and paste the URL again

:end
echo.
pause
