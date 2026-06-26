-- GameProject premake: prebuilt NEMEngine SDK を参照してゲームアプリだけを生成する
-- エンジンソース・外部ライブラリには一切触れない（SDKのNEMEngine.dll/import lib/公開ヘッダのみ使用）

newoption {
    trigger = "engine-root",
    value = "PATH",
    description = "Path to the prebuilt NEMEngine SDK (External/NEMEngine)"
}

local GAME_ROOT = path.getabsolute(path.join(_SCRIPT_DIR, ".."))
local GAME_PROJECT_ROOT = path.join(GAME_ROOT, "Project")
local localSettings = path.join(_SCRIPT_DIR, "local_settings.lua")

if os.isfile(localSettings) then
    dofile(localSettings)
end

GAME_NAME = GAME_NAME or "__GAME_NAME__"

-- SDKルートの解決: --engine-root → local_settings(NEM_SDK_ROOT) → 環境変数 → External/NEMEngine
if _OPTIONS["engine-root"] then
    NEM_SDK_ROOT = path.getabsolute(_OPTIONS["engine-root"])
end
if not NEM_SDK_ROOT then
    local envSdkRoot = os.getenv("NEM_SDK_ROOT")
    if envSdkRoot and envSdkRoot ~= "" then
        NEM_SDK_ROOT = path.getabsolute(envSdkRoot)
    end
end
if not NEM_SDK_ROOT then
    local bundled = path.join(GAME_ROOT, "External", "NEMEngine")
    if os.isdir(bundled) then
        NEM_SDK_ROOT = path.getabsolute(bundled)
    end
end
if not NEM_SDK_ROOT or not os.isfile(path.join(NEM_SDK_ROOT, "Include/NEMEngineRuntime.h")) then
    error("NEMEngine SDK was not found. Place the SDK at External/NEMEngine, set NEM_SDK_ROOT in Premake/local_settings.lua, or pass --engine-root=...")
end

NEM_GAME_OUTPUT_ROOT = path.join(GAME_ROOT, "Generated")

dofile(path.join(NEM_SDK_ROOT, "Premake", "nem_game.lua"))

local GAME_APP_ROOT = path.join(GAME_PROJECT_ROOT, GAME_NAME)

local function NEM_AddGameAppFiles()
    files {
        path.join(GAME_APP_ROOT, "**.h"),
        path.join(GAME_APP_ROOT, "**.hpp"),
        path.join(GAME_APP_ROOT, "**.inl"),
        path.join(GAME_APP_ROOT, "**.cpp"),
        path.join(GAME_APP_ROOT, "**.c"),
        path.join(GAME_APP_ROOT, "**.hlsl"),
        path.join(GAME_APP_ROOT, "**.hlsli"),
        path.join(GAME_APP_ROOT, "GameAssets/**.*"),
    }

    vpaths {
        ["Source/*"] = {
            path.join(GAME_APP_ROOT, "**.h"),
            path.join(GAME_APP_ROOT, "**.hpp"),
            path.join(GAME_APP_ROOT, "**.inl"),
            path.join(GAME_APP_ROOT, "**.cpp"),
            path.join(GAME_APP_ROOT, "**.c"),
        },
        ["Shaders/*"] = {
            path.join(GAME_APP_ROOT, "**.hlsl"),
            path.join(GAME_APP_ROOT, "**.hlsli"),
        },
        ["GameAssets/*"] = {
            path.join(GAME_APP_ROOT, "GameAssets/**.*"),
        },
    }

    -- HLSLはエンジンのDXC実行時コンパイルで扱うため、ソリューション表示用のNone項目にする
    filter "files:**.hlsl"
        buildaction "None"
    filter "files:**.hlsli"
        buildaction "None"
    filter {}

    -- C#(.cs/.csproj)はGameScripts(C#)プロジェクト専用にする。C++プロジェクトにも含めると
    -- Solution Explorerでそちら側から開けてしまい、C#言語サービスが効かず白文字・無補完になる
    removefiles {
        path.join(GAME_APP_ROOT, "**/bin/**"),
        path.join(GAME_APP_ROOT, "**/obj/**"),
        path.join(GAME_APP_ROOT, "Managed/**"),
        path.join(GAME_APP_ROOT, "**.cs"),
        path.join(GAME_APP_ROOT, "**.csproj"),
    }
end

workspace (GAME_NAME)
    location (GAME_PROJECT_ROOT)
    configurations { "Debug", "Develop", "Release" }
    platforms { "x64" }
    startproject (GAME_NAME)

    filter "platforms:x64"
        architecture "x64"
    filter {}

project (GAME_NAME)
    location (GAME_APP_ROOT)
    kind "WindowedApp"

    NEM_GameApplyCppSettings()
    NEM_GameConfigureWorkspace(GAME_PROJECT_ROOT)
    NEM_AddGameAppFiles()

    includedirs {
        GAME_APP_ROOT,
    }

    NEM_GameLinkEngine()
    NEM_GameApplyConfigFilters()
