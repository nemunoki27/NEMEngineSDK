@echo off
setlocal

rem GameProject generate: reference the prebuilt NEMEngine SDK only and generate the game VS project.
rem No engine full build and no CMake external build are triggered.

pushd "%~dp0"

if exist "%~dp0local_settings.bat" (
    call "%~dp0local_settings.bat"
)

for %%I in ("%~dp0..") do set "GAME_ROOT=%%~fI"
for %%I in ("%GAME_ROOT%") do set "GAME_NAME=%%~nxI"

rem Resolve SDK root: NEM_SDK_ROOT(local_settings) or External\NEMEngine
if not defined NEM_SDK_ROOT if exist "%GAME_ROOT%\External\NEMEngine\Include\NEMEngineRuntime.h" set "NEM_SDK_ROOT=%GAME_ROOT%\External\NEMEngine"

if not defined NEM_SDK_ROOT (
    echo [ERROR] NEMEngine SDK is not found.
    echo         Place the prebuilt SDK at External\NEMEngine, or set NEM_SDK_ROOT in Premake\local_settings.bat
    popd
    exit /b 1
)

for %%I in ("%NEM_SDK_ROOT%") do set "NEM_SDK_ROOT=%%~fI"

if not exist "%NEM_SDK_ROOT%\Premake\premake5.exe" (
    echo [ERROR] premake5.exe was not found in SDK: %NEM_SDK_ROOT%\Premake\premake5.exe
    popd
    exit /b 1
)

echo ===== Cleanup Old Project Files =====
rem 旧 .slnx は名前に依存せず一掃する。cloneフォルダ名と project 名がズレていても確実に作り直す
if exist "%GAME_ROOT%\Project\*.slnx" del /q "%GAME_ROOT%\Project\*.slnx"
if exist "%GAME_ROOT%\Project\%GAME_NAME%\%GAME_NAME%.vcxproj" del /q "%GAME_ROOT%\Project\%GAME_NAME%\%GAME_NAME%.vcxproj"
if exist "%GAME_ROOT%\Project\%GAME_NAME%\%GAME_NAME%.vcxproj.filters" del /q "%GAME_ROOT%\Project\%GAME_NAME%\%GAME_NAME%.vcxproj.filters"

echo ===== Generate Start =====
"%NEM_SDK_ROOT%\Premake\premake5.exe" --file="%~dp0premake5.lua" vs2026 > "%~dp0premake_error.log" 2>&1
set "PREMAKE_RC=%ERRORLEVEL%"
type "%~dp0premake_error.log"
echo.

findstr /c:"Error:" "%~dp0premake_error.log" >nul
set "FINDSTR_RC=%ERRORLEVEL%"

if not "%PREMAKE_RC%"=="0" (
    echo [ERROR] Premake generation failed. ^(premake exit code=%PREMAKE_RC%^)
    popd
    exit /b 1
)

if "%FINDSTR_RC%"=="0" (
    echo [ERROR] Premake generation failed. ^(Error: found in premake_error.log^)
    popd
    exit /b 1
)

echo [OK] Premake generation succeeded.

rem premake が実際に生成した .slnx から GAME_NAME を確定する。
rem clone フォルダ名と project 名がズレていても、生成物の名前へ追従させて patch 先を一致させる。
rem .slnx が無い＝premake が生成していない場合はここで明示的に失敗させる（patch 側の不明瞭なエラーを防ぐ）。
set "GENERATED_SLNX="
for %%F in ("%GAME_ROOT%\Project\*.slnx") do set "GENERATED_SLNX=%%~fF"
if not defined GENERATED_SLNX (
    echo [ERROR] No .slnx was generated under Project\. Check premake5.lua GAME_NAME and the SDK.
    popd
    exit /b 1
)
for %%F in ("%GENERATED_SLNX%") do set "GAME_NAME=%%~nF"

rem Add the C# script project to the solution and set the debugger working directory.
if exist "%NEM_SDK_ROOT%\Premake\patch_script_slnx.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%NEM_SDK_ROOT%\Premake\patch_script_slnx.ps1" -SlnxPath "%GAME_ROOT%\Project\%GAME_NAME%.slnx" -GameScriptsProject "%GAME_ROOT%\Project\%GAME_NAME%\Scripts\GameScripts.csproj"
if exist "%NEM_SDK_ROOT%\Premake\patch_vcxproj_user_debugger.ps1" powershell -NoProfile -ExecutionPolicy Bypass -File "%NEM_SDK_ROOT%\Premake\patch_vcxproj_user_debugger.ps1" -ProjectUserPath "%GAME_ROOT%\Project\%GAME_NAME%\%GAME_NAME%.vcxproj.user" -WorkingDirectory ".."

popd
endlocal
exit /b 0
