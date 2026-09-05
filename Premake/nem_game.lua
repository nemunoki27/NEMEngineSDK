-- NEMEngine prebuilt SDK: game-side premake helpers
-- ゲームワークスペース専用の最小限の設定だけを提供する
-- エンジンソースや外部ライブラリのプロジェクトには一切触れない（prebuilt DLLをリンクするだけ）
-- 利用前に NEM_SDK_ROOT(=External/NEMEngine) と NEM_GAME_OUTPUT_ROOT を設定しておくこと

function NEM_GameConfigureWorkspace(runtimeDebugDir)
    objdir(path.join(NEM_GAME_OUTPUT_ROOT, "Intermediate/%{prj.name}/%{cfg.buildcfg}"))

    filter "kind:ConsoleApp or kind:WindowedApp"
        targetdir(path.join(NEM_GAME_OUTPUT_ROOT, "Output/%{cfg.buildcfg}/%{prj.name}"))
        debugdir(runtimeDebugDir)

    filter {}
end

function NEM_GameApplyCppSettings()
    system "windows"
    language "C++"
    cppdialect "C++20"
    staticruntime "On"
    warnings "High"
    multiprocessorcompile "On"
    buildoptions { "/utf-8" }
    defines { "NOMINMAX" }

    filter "action:vs2022"
        toolset "v143"
    filter {}
end

function NEM_GameApplyConfigFilters()
    filter "configurations:Debug"
        symbols "On"
        defines { "_DEVELOPBUILD" }

    filter "configurations:Develop"
        optimize "On"
        defines { "_DEVELOPBUILD" }

    filter "configurations:Release"
        optimize "On"
        defines { "_RELEASE" }
        buildoptions { "/wd4100" }

    filter {}
end

-- prebuilt SDK のエンジンをリンクし、実行時ランタイムとC#ゲームスクリプトの配置までを設定する
function NEM_GameLinkEngine()
    includedirs {
        path.join(NEM_SDK_ROOT, "Include"),
    }

    links {
        "NEMRuntime",
    }

    linkoptions {
        "/IGNORE:4099",
    }

    -- import lib は構成別にSDKのBinから引く
    filter "configurations:Debug"
        libdirs { path.join(NEM_SDK_ROOT, "Bin/Debug") }
    filter "configurations:Develop"
        libdirs { path.join(NEM_SDK_ROOT, "Bin/Develop") }
    filter "configurations:Release"
        libdirs { path.join(NEM_SDK_ROOT, "Bin/Release") }
    filter {}

    -- C#ゲームスクリプトをビルドする。SDK同梱のNEM.ScriptCore.dll等を参照する
    local metaSyncDll = path.translate(path.join(NEM_SDK_ROOT, "Managed/Tools/NEM.ScriptMetaSync.dll"), "\\")
    prebuildcommands {
        'set DOTNET_CLI_UI_LANGUAGE=en',
        'if "%NEMScriptMetadataMode%"=="" set NEMScriptMetadataMode=EditorSync',
        'if exist "' .. metaSyncDll .. '" if exist "$(ProjectDir)GameAssets" dotnet "' .. metaSyncDll .. '" --root "$(ProjectDir)GameAssets" --mode "%NEMScriptMetadataMode%"',
        'if not exist "$(ProjectDir)Scripts\\GameScripts.csproj" (echo [エラー] C#ゲームスクリプトのプロジェクトが見つかりません: $(ProjectDir)Scripts\\GameScripts.csproj & exit /b 1)',
        'if not "$(BuildingSolutionFile)"=="true" dotnet build "$(ProjectDir)Scripts\\GameScripts.csproj" -c "$(Configuration)" -p:NEMScriptMetadataMode=%NEMScriptMetadataMode%',
    }

    -- 実行時ランタイム(NEMRuntime.dll / dxc / nethost / Managed等)をSDKから実行ファイル横へ配置する
    -- さらにゲームのGameScripts出力もManagedへまとめる
    local runtimeDir = path.translate(path.join(NEM_SDK_ROOT, "Runtime/$(Configuration)"), "\\")
    postbuildcommands {
        'if not exist "' .. runtimeDir .. '" (echo [エラー] NEMEngineランタイムが見つかりません: ' .. runtimeDir .. ' & exit /b 1)',
        'if exist "' .. runtimeDir .. '" xcopy /Y /I /E "' .. runtimeDir .. '\\*" "$(TargetDir)" >nul',
        'if exist "$(ProjectDir)Managed\\$(Configuration)\\*" xcopy /Y /I "$(ProjectDir)Managed\\$(Configuration)\\*" "$(TargetDir)Managed\\" >nul',
        'if not exist "$(TargetDir)Managed\\GameScripts.dll" (echo [エラー] ゲーム実行用のGameScripts.dllを配置できませんでした: $(TargetDir)Managed\\GameScripts.dll & exit /b 1)',
    }
end
