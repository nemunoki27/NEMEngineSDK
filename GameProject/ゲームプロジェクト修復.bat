@echo off
rem Repair this game project using the referenced NEMEngine SDK.
chcp 65001 >nul
setlocal

if exist "%~dp0External\NEMEngine\GameProject\RepairGameProject.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0External\NEMEngine\GameProject\RepairGameProject.ps1" -GameRoot "%~dp0"
) else if exist "%~dp0RepairGameProject.ps1" (
    powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0RepairGameProject.ps1" -GameRoot "%~dp0"
) else (
    echo [ERROR] RepairGameProject.ps1 was not found.
    exit /b 1
)

if errorlevel 1 pause
