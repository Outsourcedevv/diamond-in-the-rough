@echo off
title Diamond Rush TikTok Bridge
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is not installed yet. Opening the download page...
  echo Install the LTS version, then double-click Start Bridge again.
  start "" https://nodejs.org/en/download
  pause
  exit /b 1
)
if not exist node_modules\tiktok-live-connector (
  echo First run: installing the TikTok connector. This takes a minute...
  call npm install --omit=dev --no-audit --no-fund
  if errorlevel 1 (
    echo Installing failed. Check your internet connection and try again.
    pause
    exit /b 1
  )
)
start "" http://localhost:8787
node bridge.mjs
pause
