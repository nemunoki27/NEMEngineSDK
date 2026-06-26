# ゲームが参照する NEMEngine SDK を最新へ更新する
# - git submodule 参照: SDK専用リポジトリから最新を取得する
# - ローカル junction 参照: SDK作成.bat の再エクスポート結果がそのまま反映されるため取得は不要
# 最後に Visual Studio プロジェクトを再生成し、全構成(Debug/Develop/Release)をリビルドする

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = "Stop"

# このスクリプトはゲームルート直下に置く
$gameRoot = $PSScriptRoot
$externalEngine = Join-Path $gameRoot "External\NEMEngine"

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Get-GameProjectName {
    $premakePath = Join-Path $gameRoot "Premake\premake5.lua"
    if (Test-Path -LiteralPath $premakePath) {
        $text = [System.IO.File]::ReadAllText($premakePath)
        $match = [regex]::Match($text, 'GAME_NAME\s*=\s*GAME_NAME\s*or\s*"([^"]+)"')
        if ($match.Success -and $match.Groups[1].Value -ne "__GAME_NAME__") {
            return $match.Groups[1].Value
        }
    }

    $projectRoot = Join-Path $gameRoot "Project"
    if (Test-Path -LiteralPath $projectRoot) {
        $scriptProject = Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "Scripts\GameScripts.csproj") } |
            Select-Object -First 1
        if ($scriptProject) {
            return $scriptProject.Name
        }
    }

    return Split-Path -Leaf $gameRoot
}

function Add-TextFileRule([string]$Path, [string]$Rule, [string]$Header) {
    if (-not (Test-Path -LiteralPath $Path)) {
        Write-Utf8NoBom $Path ($Rule + [Environment]::NewLine)
        return $true
    }

    $text = [System.IO.File]::ReadAllText($Path)
    $lines = $text -split "`r?`n"
    if ($lines -contains $Rule) {
        return $false
    }

    $separator = if ($text.EndsWith("`r`n") -or $text.EndsWith("`n")) { "" } else { [Environment]::NewLine }
    $append = $separator + [Environment]::NewLine + $Header + [Environment]::NewLine + $Rule + [Environment]::NewLine
    Write-Utf8NoBom $Path ($text + $append)
    return $true
}

function Sync-GameProjectSupportFiles {
    $supportRoot = Join-Path $externalEngine "GameProject"
    if (-not (Test-Path -LiteralPath $supportRoot)) {
        Write-Host "SDK内にGameProjectサポートファイルが無いため、ゲーム側Premake同期はスキップします。"
        return
    }

    Write-Host ""
    Write-Host "ゲーム側サポートファイルを同期します..."

    $gameName = Get-GameProjectName
    $gamePremakeDir = Join-Path $gameRoot "Premake"
    New-Item -ItemType Directory -Force -Path $gamePremakeDir | Out-Null

    $srcPremakeLua = Join-Path $supportRoot "Premake\premake5.lua"
    if (Test-Path -LiteralPath $srcPremakeLua) {
        $text = [System.IO.File]::ReadAllText($srcPremakeLua).Replace("__GAME_NAME__", $gameName)
        Write-Utf8NoBom (Join-Path $gamePremakeDir "premake5.lua") $text
        Write-Host "  更新: Premake\premake5.lua"
    }

    $srcGenerateBat = Join-Path $supportRoot "Premake\generate_vs2026.bat"
    if (Test-Path -LiteralPath $srcGenerateBat) {
        Copy-Item -Force -LiteralPath $srcGenerateBat -Destination (Join-Path $gamePremakeDir "generate_vs2026.bat")
        Write-Host "  更新: Premake\generate_vs2026.bat"
    }

    $gitIgnoreChanged = Add-TextFileRule (Join-Path $gameRoot ".gitignore") "Project/**/*.exeConfig.json" "# NEMEngine local editor/runtime config"
    if ($gitIgnoreChanged) {
        Write-Host "  更新: .gitignore"
    }

    $gitAttributesChanged = Add-TextFileRule (Join-Path $gameRoot ".gitattributes") "*.bat text eol=crlf" "# NEMEngine Windows scripts"
    if ($gitAttributesChanged) {
        Write-Host "  更新: .gitattributes"
    }
}

Write-Host "============================================"
Write-Host "  NEMEngine SDK 更新"
Write-Host "============================================"
Write-Host ""

if (-not (Test-Path -LiteralPath $externalEngine)) {
    Write-Host "[エラー] External\NEMEngine が見つかりません: $externalEngine"
    Read-Host "Enterキーを押すと終了します"
    exit 1
}

# ジャンクション(ローカルSDK)か git submodule かで更新方法が変わる
$item = Get-Item -LiteralPath $externalEngine -Force
$isJunction = [bool]($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint)

if ($isJunction) {
    Write-Host "ローカルSDK(ジャンクション)参照です。"
    Write-Host "エンジン側で SDK作成.bat を実行すれば、その内容がそのまま反映されます。取得は不要です。"
} else {
    Write-Host "SDKリポジトリから最新を取得します..."
    # git は進捗やメッセージを stderr へ出すため、ネイティブ stderr でスクリプトを止めないよう一時的に緩める
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    $updateOk = $false
    Push-Location $externalEngine
    try {
        git fetch origin
        # 実行中エディタが書き込んだ設定ファイル等のローカル変更を破棄し、確実に最新SDK(origin/main)へ揃える
        # SDKは配布物なのでローカル変更を保持する必要はない
        git reset --hard origin/main
        git submodule update --init --recursive
        $updateOk = ($LASTEXITCODE -eq 0)
    } finally {
        Pop-Location
        $ErrorActionPreference = $prevEAP
    }
    if (-not $updateOk) {
        Write-Host ""
        Write-Host "[エラー] SDKの取得に失敗しました。External\NEMEngine の状態を確認してください。"
        Read-Host "Enterキーを押すと終了します"
        exit 1
    }
}

$repairScript = Join-Path $externalEngine "GameProject\RepairGameProject.ps1"
if (Test-Path -LiteralPath $repairScript) {
    & $repairScript -GameRoot $gameRoot
} else {
    Sync-GameProjectSupportFiles
}

Write-Host ""
Write-Host "Visual Studio プロジェクトを再生成します..."
& (Join-Path $gameRoot "Premake\generate_vs2026.bat")
if ($LASTEXITCODE -ne 0) {
    Write-Host "[エラー] プロジェクトの再生成に失敗しました。"
    Read-Host "Enterキーを押すと終了します"
    exit 1
}

Write-Host ""
Write-Host "全構成をリビルドします（Debug/Develop/Release）..."
Write-Host "  ※ エディター/ゲームを閉じていないとDLLがロックされて失敗します。"

# msbuild を vswhere で特定する
$vswhere = "C:\Program Files (x86)\Microsoft Visual Studio\Installer\vswhere.exe"
$msbuild = ""
if (Test-Path $vswhere) {
    $msbuild = & $vswhere -latest -prerelease -find "MSBuild\**\Bin\MSBuild.exe" | Select-Object -First 1
}
# ゲームのソリューション(.slnx)を探す
$slnx = Get-ChildItem -LiteralPath (Join-Path $gameRoot "Project") -Filter "*.slnx" -ErrorAction SilentlyContinue | Select-Object -First 1

if ([string]::IsNullOrWhiteSpace($msbuild) -or -not (Test-Path $msbuild) -or -not $slnx) {
    Write-Host ""
    Write-Host "[完了] SDKは更新しました。MSBuildまたはソリューションが見つからないため、Visual Studio で手動ビルドしてください。"
    Read-Host "Enterキーを押すと終了します"
    exit 0
}

# msbuildは進捗をstderrへ出すことがあるため、ネイティブstderrで止めない
$prevBuildEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
$buildOk = $true
foreach ($cfg in @("Debug", "Develop", "Release")) {
    Write-Host ""
    Write-Host "  [$cfg] リビルド中..."
    # SDKのDLLを確実に実行フォルダへ配置するためRebuildする
    # 初回はC#のproject.assets.jsonが無いと NETSDK1004 になるため-restoreで先に復元する
    & $msbuild $slnx.FullName -restore -t:Rebuild -p:Configuration=$cfg -p:Platform=x64 -m -v:m -nologo
    if ($LASTEXITCODE -ne 0) {
        Write-Host "  [$cfg] ビルドに失敗しました。"
        $buildOk = $false
    }
}
$ErrorActionPreference = $prevBuildEAP

Write-Host ""
if ($buildOk) {
    Write-Host "[完了] SDK更新と全構成のリビルドが完了しました。"
} else {
    Write-Host "[完了] SDKは更新しましたが、一部構成のビルドに失敗しました。ログを確認してください。"
}
Write-Host ""
Read-Host "Enterキーを押すと終了します"
