@echo off
rem Double-click to update the referenced NEMEngine SDK and regenerate the VS project.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UpdateSdk.ps1"
set "SDK_UPDATE_RESULT=%ERRORLEVEL%"
if not "%SDK_UPDATE_RESULT%"=="0" pause
exit /b %SDK_UPDATE_RESULT%
