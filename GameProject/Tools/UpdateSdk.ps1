# ゲームが参照する NEMEngine SDK を最新へ更新する
# SDK更新処理バージョン: 2
# - git submodule 参照: SDK専用リポジトリから最新を取得する
# - ローカル junction 参照: SDK作成.bat の再エクスポート結果がそのまま反映されるため取得は不要
# 最後に Visual Studio プロジェクトを再生成し、全構成(Debug/Develop/Release)をリビルドする

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = "Stop"

# このスクリプトはゲームルートのTools直下に置く
$gameRoot = Split-Path -Parent $PSScriptRoot
$externalEngine = Join-Path $gameRoot "External\NEMEngine"
$updaterSource = [System.IO.File]::ReadAllText($PSCommandPath)

# Gitの途中失敗を後続コマンドの成功で隠さない
function Invoke-SdkGit([string[]]$Arguments) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    try {
        $output = & git -C $externalEngine @Arguments 2>&1
        $code = $LASTEXITCODE
    } finally {
        $ErrorActionPreference = $previousPreference
    }
    if ($code -ne 0) {
        throw "SDKのGit処理に失敗しました: git $($Arguments -join ' ')`n$($output -join [Environment]::NewLine)"
    }
    return $output
}

# 実行中のEditorやゲームがある場合はSDKを変更しない
function Assert-SdkNotInUse {
    $gameName = Get-GameProjectName
    $running = @(Get-Process -Name "NEMEditor", $gameName -ErrorAction SilentlyContinue)
    if ($running.Count -ne 0) {
        throw "Editorとゲームを終了してからSDK更新を実行してください: $($running.Id -join ', ')"
    }
    foreach ($directory in @("Editor", "Bin")) {
        $binaryRoot = Join-Path $externalEngine $directory
        if (-not (Test-Path -LiteralPath $binaryRoot)) { continue }
        foreach ($file in Get-ChildItem -LiteralPath $binaryRoot -Recurse -File) {
            if ($file.Extension -notin @(".exe", ".dll")) { continue }
            try {
                $stream = [System.IO.File]::Open($file.FullName,
                    [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                    [System.IO.FileShare]::None)
                $stream.Dispose()
            } catch {
                throw "SDKのファイルが使用中、または読み取りできません: $($file.FullName)"
            }
        }
    }
}

# SDK以外のリポジトリを誤って更新しない
function Update-SdkRepository {
    if (-not (Test-Path -LiteralPath (Join-Path $externalEngine ".git"))) {
        throw "External\NEMEngineのGit管理情報がありません。サブモジュールの初期化を確認してください。"
    }
    $repositoryRoot = (Invoke-SdkGit @("rev-parse", "--show-toplevel") | Out-String).Trim()
    if ([System.IO.Path]::GetFullPath($repositoryRoot).TrimEnd('\', '/') -ne
        [System.IO.Path]::GetFullPath($externalEngine).TrimEnd('\', '/')) {
        throw "SDKのGitルートがExternal\NEMEngineと一致しません。更新を中止します。"
    }

    Invoke-SdkGit @("fetch", "origin", "+refs/heads/main:refs/remotes/origin/main") | Out-Host
    $target = (Invoke-SdkGit @("rev-parse", "--verify", "origin/main^{commit}") | Out-String).Trim()
    $before = (Invoke-SdkGit @("rev-parse", "HEAD") | Out-String).Trim()
    Write-Host "SDK更新: $before -> $target"

    # 未追跡のシーンや無視対象も退避し、配布ファイルと混在させない
    $changes = @(Invoke-SdkGit @("status", "--porcelain", "--untracked-files=all", "--ignored"))
    if ($changes.Count -ne 0) {
        $backupName = "NEMEngine SDK update backup " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
        Invoke-SdkGit @("stash", "push", "--all", "-m", $backupName) | Out-Host
        $backup = (Invoke-SdkGit @("rev-parse", "refs/stash") | Out-String).Trim()
        Write-Host "SDK内の変更をGit stashへ退避しました: $backup"
        Write-Host "退避内容は自動復元しません。必要なシーン等はこの退避から取り出してください。"
    }
    Invoke-SdkGit @("reset", "--hard", $target) | Out-Host
    Invoke-SdkGit @("submodule", "update", "--init", "--recursive") | Out-Host
    $actual = (Invoke-SdkGit @("rev-parse", "HEAD") | Out-String).Trim()
    if ($actual -ne $target) { throw "SDKの更新先が一致しません: $actual / $target" }
    Invoke-SdkGit @("diff", "--quiet", "HEAD", "--") | Out-Host
    Write-Host "[確認済み] SDKのHEADと追跡ファイルが更新先に一致しました: $actual"
}

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

    $sourceTools = Join-Path $supportRoot "Tools"
    $gameTools = Join-Path $gameRoot "Tools"
    New-Item -ItemType Directory -Force -Path $gameTools | Out-Null
    foreach ($fileName in @("SDK更新.bat", "UpdateSdk.ps1", "FinalizeSdkToolMigration.ps1")) {
        $source = Join-Path $sourceTools $fileName
        if (Test-Path -LiteralPath $source) {
            Copy-Item -Force -LiteralPath $source -Destination (Join-Path $gameTools $fileName)
            Write-Host "  更新: Tools\$fileName"
        }
    }

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

    $gitIgnorePath = Join-Path $gameRoot ".gitignore"
    $gitIgnoreChanged = Add-TextFileRule $gitIgnorePath "Project/**/Library/" "# NEMEngine local editor/runtime data"
    $gitIgnoreChanged = (Add-TextFileRule $gitIgnorePath "Project/**/Saved/" "# NEMEngine local editor/runtime data") -or $gitIgnoreChanged
    $gitIgnoreChanged = (Add-TextFileRule $gitIgnorePath "Project/**/UserSettings/" "# NEMEngine local editor/runtime data") -or $gitIgnoreChanged
    if ($gitIgnoreChanged) {
        Write-Host "  更新: .gitignore"
    }

    $gitAttributesChanged = Add-TextFileRule (Join-Path $gameRoot ".gitattributes") "*.bat text eol=crlf" "# NEMEngine Windows scripts"
    if ($gitAttributesChanged) {
        Write-Host "  更新: .gitattributes"
    }

    $finalizer = Join-Path $gameTools "FinalizeSdkToolMigration.ps1"
    if (Test-Path -LiteralPath $finalizer -PathType Leaf) {
        $arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$finalizer`" " +
            "-GameRoot `"$gameRoot`" -WaitForProcessID $PID"
        Start-Process -FilePath "powershell.exe" -ArgumentList $arguments -WindowStyle Hidden
    }
}

try {
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

Assert-SdkNotInUse

if ($isJunction) {
    Write-Host "ローカルSDK(ジャンクション)参照です。"
    Write-Host "エンジン側で SDK作成.bat を実行すれば、その内容がそのまま反映されます。取得は不要です。"
} else {
    Write-Host "SDKリポジトリから最新を取得します..."
    Update-SdkRepository
}

$repairScript = Join-Path $externalEngine "GameProject\RepairGameProject.ps1"
try {
if (Test-Path -LiteralPath $repairScript) {
    $global:LASTEXITCODE = 0
    & $repairScript -GameRoot $gameRoot
    if ($LASTEXITCODE -ne 0) { throw "ゲームプロジェクトの修復に失敗しました。" }
} else {
    Sync-GameProjectSupportFiles
}
} finally {
# 旧SDKへの更新でも修正版の更新処理を旧版へ戻さない
$installedUpdater = Join-Path $gameRoot "Tools\UpdateSdk.ps1"
$installedSource = [System.IO.File]::ReadAllText($installedUpdater)
$installedRevision = [regex]::Match($installedSource, 'SDK更新処理バージョン: (\d+)')
if (-not $installedRevision.Success -or [int]$installedRevision.Groups[1].Value -lt 2) {
    [System.IO.File]::WriteAllText($installedUpdater, $updaterSource,
        [System.Text.UTF8Encoding]::new($true))
}
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
    Write-Host "[未完了] SDKは更新しましたが、MSBuildまたはソリューションが見つかりません。Visual Studioで手動ビルドしてください。"
    Read-Host "Enterキーを押すと終了します"
    exit 1
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
    throw "SDKは更新しましたが、一部構成のビルドに失敗しました。ログを確認してください。"
}
Write-Host ""
Read-Host "Enterキーを押すと終了します"
exit 0
} catch {
    Write-Host "[エラー] $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "SDK更新は完了していません。上記の原因を解消してから再実行してください。"
    exit 1
}
