@echo off
rem Double-click to update the referenced NEMEngine SDK and regenerate the VS project.
chcp 65001 >nul
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0UpdateSdk.ps1"
if errorlevel 1 pause
