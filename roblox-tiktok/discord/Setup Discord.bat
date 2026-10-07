@echo off
title Diamond Rush Discord setup
cd /d "%~dp0"
where node >nul 2>nul
if errorlevel 1 (
  echo Node.js is not installed yet. Opening the download page...
  start "" https://nodejs.org/en/download
  pause
  exit /b 1
)
node setup.mjs
pause
