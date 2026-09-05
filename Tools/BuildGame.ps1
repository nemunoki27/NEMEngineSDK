param(
    [Parameter(Mandatory = $true)]
    [string]$ManifestPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$OutputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = $OutputEncoding

function Write-Utf8Json {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($Path, $json, [System.Text.UTF8Encoding]::new($false))
}

function Get-MSBuildPath {

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    if (Test-Path -LiteralPath $vswhere) {
        $found = & $vswhere -latest -prerelease -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" |
            Select-Object -First 1
        if ($found -and (Test-Path -LiteralPath $found)) {
            return $found
        }
    }

    $command = Get-Command "MSBuild.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    throw "MSBuild.exeが見つかりません。Visual Studioのビルド環境を確認してください"
}

function Get-ChildPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,
        [Parameter(Mandatory = $true)]
        [string]$Relative
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $childFull = [System.IO.Path]::GetFullPath((Join-Path $rootFull $Relative))
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not $childFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "出力フォルダーの外を参照するパスは使用できません: $Relative"
    }
    return $childFull
}

function Assert-FileHash {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [long]$ExpectedSize,
        [Parameter(Mandatory = $true)]
        [string]$ExpectedSha256
    )

    $file = Get-Item -LiteralPath $Path
    if ($file.Length -ne $ExpectedSize) {
        throw "Cook対象ファイルのサイズが一致しません: $Path"
    }
    $actualSha256 = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -ne $ExpectedSha256.ToLowerInvariant()) {
        throw "Cook対象ファイルのハッシュが一致しません: $Path"
    }
}

$stageDirectory = ""
try {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "製品ビルドのマニフェストが見つかりません"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $projectPath = [System.IO.Path]::GetFullPath([string]$manifest.projectPath)
    $sourceRuntime = [System.IO.Path]::GetFullPath([string]$manifest.sourceRuntime)
    $outputRoot = [System.IO.Path]::GetFullPath([string]$manifest.outputRoot)
    $productName = [string]$manifest.productName
    $runtimeExecutable = [string]$manifest.runtimeExecutable
    $executableName = [string]$manifest.executableName

    if (-not (Test-Path -LiteralPath $projectPath)) {
        throw "ゲームプロジェクトが見つかりません: $projectPath"
    }
    $gameScriptsProject = Join-Path ([System.IO.Path]::GetDirectoryName($projectPath)) "Scripts\GameScripts.csproj"
    if (-not (Test-Path -LiteralPath $gameScriptsProject -PathType Leaf)) {
        throw "C#ゲームスクリプトのプロジェクトが見つかりません: $gameScriptsProject"
    }

    $buildToolProject = [string]$manifest.buildToolProject
    $buildToolExecutable = [System.IO.Path]::GetFullPath([string]$manifest.buildToolExecutable)
    if (-not [string]::IsNullOrWhiteSpace($buildToolProject)) {
        $buildToolProject = [System.IO.Path]::GetFullPath($buildToolProject)
        if (-not (Test-Path -LiteralPath $buildToolProject -PathType Leaf)) {
            throw "製品ビルドツールのプロジェクトが見つかりません: $buildToolProject"
        }
    }
    elseif (-not (Test-Path -LiteralPath $buildToolExecutable -PathType Leaf)) {
        throw "SDKの製品ビルドツールが見つかりません。SDKを更新してください: $buildToolExecutable"
    }

    $msbuild = Get-MSBuildPath
    Write-Output "ゲームのReleaseビルドを開始します"
    & $msbuild $projectPath /t:Build /p:Configuration=Release /p:Platform=x64 /m /nodeReuse:false /v:minimal
    if ($LASTEXITCODE -ne 0) {
        throw "ゲームのReleaseビルドに失敗しました"
    }

    # 製品には通常出力の最新DLLだけを使うためC#を強制再ビルドする
    Write-Output "C#ゲームスクリプトのReleaseビルドを確認します"
    & dotnet build $gameScriptsProject -c Release --no-incremental -p:NEMScriptMetadataMode=EditorSync
    if ($LASTEXITCODE -ne 0) {
        throw "C#ゲームスクリプトのReleaseビルドに失敗しました"
    }

    $managedBuildOutput = Join-Path ([System.IO.Path]::GetDirectoryName($projectPath)) "Managed\Release"
    $managedSource = Join-Path $sourceRuntime "Managed"
    $gameScriptsDll = Join-Path $managedBuildOutput "GameScripts.dll"
    if (-not (Test-Path -LiteralPath $gameScriptsDll -PathType Leaf)) {
        throw "C#ゲームスクリプトのDLLが見つかりません: $gameScriptsDll"
    }
    New-Item -ItemType Directory -Path $managedSource -Force | Out-Null
    foreach ($fileName in @("GameScripts.dll", "GameScripts.deps.json", "GameScripts.pdb")) {
        $source = Join-Path $managedBuildOutput $fileName
        if (Test-Path -LiteralPath $source -PathType Leaf) {
            Copy-Item -LiteralPath $source -Destination (Join-Path $managedSource $fileName) -Force
        }
    }
    $deployedGameScriptsDll = Join-Path $managedSource "GameScripts.dll"
    if ((Get-FileHash -LiteralPath $gameScriptsDll -Algorithm SHA256).Hash -ne
        (Get-FileHash -LiteralPath $deployedGameScriptsDll -Algorithm SHA256).Hash) {
        throw "ゲーム実行用のC#ゲームスクリプトDLLが最新ではありません"
    }

    if (-not [string]::IsNullOrWhiteSpace($buildToolProject)) {
        Write-Output "製品ビルドツールをビルドしています"
        & $msbuild $buildToolProject /t:Build /p:Configuration=Release /p:Platform=x64 /m /nodeReuse:false /v:minimal
        if ($LASTEXITCODE -ne 0 -or -not (Test-Path -LiteralPath $buildToolExecutable -PathType Leaf)) {
            throw "製品ビルドツールのビルドに失敗しました"
        }
    }
    else {
        Write-Output "SDKに同梱された製品ビルドツールを使用します"
    }

    $targetDirectory = Get-ChildPath -Root $outputRoot -Relative $productName
    $stageName = "." + $productName + ".building-" + $PID
    $stageDirectory = Get-ChildPath -Root $outputRoot -Relative $stageName
    $backupDirectory = Get-ChildPath -Root $outputRoot -Relative ("." + $productName + ".previous-" + $PID)

    if (Test-Path -LiteralPath $stageDirectory) {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force
    }
    if (Test-Path -LiteralPath $backupDirectory) {
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $stageDirectory -Force | Out-Null

    $runtimeSource = Join-Path $sourceRuntime $runtimeExecutable
    if (-not (Test-Path -LiteralPath $runtimeSource)) {
        throw "ゲームの実行ファイルが見つかりません: $runtimeSource"
    }
    Copy-Item -LiteralPath $runtimeSource `
        -Destination (Join-Path $stageDirectory $executableName) -Force

    $runtimeManifestName = "nem.runtime-dependencies.json"
    $runtimeManifestPath = Join-Path $sourceRuntime $runtimeManifestName
    if (-not (Test-Path -LiteralPath $runtimeManifestPath)) {
        throw "ランタイム依存関係のマニフェストが見つかりません: $runtimeManifestPath"
    }

    $runtimeManifest = Get-Content -LiteralPath $runtimeManifestPath -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ([int]$runtimeManifest.schemaVersion -ne 1) {
        throw "ランタイム依存関係のマニフェスト形式に対応していません"
    }

    $runtimeFiles = @($runtimeManifest.files | ForEach-Object { [string]$_ })
    if ($runtimeFiles.Count -eq 0 -or $runtimeFiles -notcontains "NEMRuntime.dll") {
        throw "ランタイム依存関係のマニフェストにNEMRuntime.dllが含まれていません"
    }

    $productRuntimeFiles = @($runtimeFiles | Where-Object {
        $_ -ne "dxcompiler.dll" -and $_ -ne "dxil.dll"
    })
    foreach ($runtimeFile in $productRuntimeFiles) {
        $source = Get-ChildPath -Root $sourceRuntime -Relative $runtimeFile
        if (-not (Test-Path -LiteralPath $source)) {
            throw "ランタイムファイルが見つかりません: $source"
        }
        $destination = Get-ChildPath -Root $stageDirectory -Relative $runtimeFile
        $destinationDirectory = [System.IO.Path]::GetDirectoryName($destination)
        New-Item -ItemType Directory -Path $destinationDirectory -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }
    Write-Utf8Json -Path (Join-Path $stageDirectory $runtimeManifestName) -Value ([ordered]@{
        schemaVersion = 1
        configuration = "Release"
        files = $productRuntimeFiles
    })

    if (-not (Test-Path -LiteralPath $managedSource)) {
        throw "C#ランタイムが見つかりません: $managedSource"
    }
    $managedSourceFull = [System.IO.Path]::GetFullPath($managedSource).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    Get-ChildItem -LiteralPath $managedSource -Recurse -File |
        Where-Object { $_.Extension -eq ".dll" -or $_.Extension -eq ".json" } |
        ForEach-Object {
            $relative = $_.FullName.Substring($managedSourceFull.Length).TrimStart(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar)
            $destination = Get-ChildPath -Root (Join-Path $stageDirectory "Managed") -Relative $relative
            New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Force
        }

    foreach ($entry in $manifest.files) {
        $source = [System.IO.Path]::GetFullPath([string]$entry.source)
        $relative = [string]$entry.destination
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
            throw "アセットファイルが見つかりません: $source"
        }
        Assert-FileHash -Path $source -ExpectedSize ([long]$entry.size) -ExpectedSha256 ([string]$entry.sha256)
        $destination = Get-ChildPath -Root $stageDirectory -Relative $relative
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
        Assert-FileHash -Path $destination -ExpectedSize ([long]$entry.size) -ExpectedSha256 ([string]$entry.sha256)
    }

    $cookedShaderRoot = Join-Path $stageDirectory "Cooked\Shaders"
    New-Item -ItemType Directory -Path $cookedShaderRoot -Force | Out-Null
    Write-Output "シェーダーのCookを開始します"
    & $buildToolExecutable --cook-shaders $ManifestPath $cookedShaderRoot
    if ($LASTEXITCODE -ne 0) {
        throw "シェーダーのCookに失敗しました。直前の診断ログを確認してください"
    }

    # MaterialはCook済みPassだけを参照し、製品AssetDatabaseへGraph依存を残さない
    $detachedMaterialCount = 0
    Get-ChildItem -LiteralPath $stageDirectory -Recurse -File -Filter "*.material.json" |
        ForEach-Object {
            $material = Get-Content -LiteralPath $_.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($material.PSObject.Properties.Name -contains "shaderGraph") {
                $material.PSObject.Properties.Remove("shaderGraph")
                Write-Utf8Json -Path $_.FullName -Value $material
                ++$detachedMaterialCount
            }
        }
    Write-Output "Shader Graphのソース参照を解除しました: $detachedMaterialCount"

    # 製品はCook済みDXILのみを使用し、Graph/HLSLソースを配置しない
    Get-ChildItem -LiteralPath $stageDirectory -Recurse -File |
        Where-Object {
            $lower = $_.Name.ToLowerInvariant()
            $lower.EndsWith(".hlsl") -or
            $lower.EndsWith(".hlsli") -or
            $lower.EndsWith(".hlsl.meta") -or
            $lower.EndsWith(".hlsli.meta") -or
            $lower.EndsWith(".shadergraph.json") -or
            $lower.EndsWith(".shadergraph.json.meta")
        } |
        Remove-Item -Force

    $packageDependencies = [ordered]@{}
    $packageLockDependencies = [ordered]@{}
    foreach ($package in $manifest.packages) {
        $name = [string]$package.name
        $version = [string]$package.version
        $packageDependencies[$name] = $version
        $packageLockDependencies[$name] = [ordered]@{
            version = $version
            source = "embedded"
            path = $name
            contentHash = [string]$package.contentHash
        }
    }
    $packagesDirectory = Join-Path $stageDirectory "Packages"
    New-Item -ItemType Directory -Path $packagesDirectory -Force | Out-Null
    Write-Utf8Json -Path (Join-Path $packagesDirectory "manifest.json") -Value ([ordered]@{
        schemaVersion = 1
        dependencies = $packageDependencies
    })
    Write-Utf8Json -Path (Join-Path $packagesDirectory "packages-lock.json") -Value ([ordered]@{
        schemaVersion = 1
        dependencies = $packageLockDependencies
    })

    $runtimeSettingsDirectory = Join-Path $stageDirectory "ProjectSettings\Runtime"
    New-Item -ItemType Directory -Path $runtimeSettingsDirectory -Force | Out-Null
    Write-Utf8Json -Path (Join-Path $runtimeSettingsDirectory "StartupScene.json") -Value @{
        activeScene = [string]$manifest.startupScene
    }
    Write-Utf8Json -Path (Join-Path $runtimeSettingsDirectory "Game.json") -Value @{
        gameName = $productName
        startupFullscreen = [bool]$manifest.startupFullscreen
    }
    $descriptorName = [System.IO.Path]::GetFileNameWithoutExtension($executableName) + ".nemproject"
    Write-Utf8Json -Path (Join-Path $stageDirectory $descriptorName) -Value @{
        schemaVersion = 1
        projectGuid = [string]$manifest.projectGuid
        name = $productName
        assetsDirectory = "GameAssets"
        packagesDirectory = "Packages"
        projectSettingsDirectory = "ProjectSettings"
    }
    Write-Utf8Json -Path (Join-Path $stageDirectory ".nemBuildManifest.json") -Value @{
        schemaVersion = 2
        productName = $productName
        executableName = $executableName
        startupScene = [string]$manifest.startupScene
        startupFullscreen = [bool]$manifest.startupFullscreen
        assetFileCount = @($manifest.files).Count
        packageCount = @($manifest.packages).Count
        cookHash = [string]$manifest.cookHash
        configuration = "Release"
    }
    $stageRootFull = [System.IO.Path]::GetFullPath($stageDirectory).TrimEnd(
        [System.IO.Path]::DirectorySeparatorChar,
        [System.IO.Path]::AltDirectorySeparatorChar)
    $cookFiles = @(Get-ChildItem -LiteralPath $stageDirectory -Recurse -File |
        ForEach-Object {
            $relative = $_.FullName.Substring($stageRootFull.Length).TrimStart(
                [System.IO.Path]::DirectorySeparatorChar,
                [System.IO.Path]::AltDirectorySeparatorChar).Replace('\', '/')
            [ordered]@{
                path = $relative
                size = [long]$_.Length
                sha256 = (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
            }
        } | Sort-Object { $_.path })
    Write-Utf8Json -Path (Join-Path $stageDirectory ".nemCookManifest.json") -Value ([ordered]@{
        schemaVersion = 1
        cookHash = [string]$manifest.cookHash
        files = $cookFiles
    })

    if (Test-Path -LiteralPath $targetDirectory) {
        $marker = Join-Path $targetDirectory ".nemBuildManifest.json"
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
            throw "既存のフォルダーはNEMEngineの製品ビルドではないため上書きできません: $targetDirectory"
        }
        Move-Item -LiteralPath $targetDirectory -Destination $backupDirectory
    }

    try {
        Move-Item -LiteralPath $stageDirectory -Destination $targetDirectory
        $stageDirectory = ""
    }
    catch {
        if (Test-Path -LiteralPath $backupDirectory) {
            Move-Item -LiteralPath $backupDirectory -Destination $targetDirectory
        }
        throw
    }

    if (Test-Path -LiteralPath $backupDirectory) {
        Remove-Item -LiteralPath $backupDirectory -Recurse -Force -ErrorAction SilentlyContinue
    }

    Write-Output "製品ビルドが完了しました: $targetDirectory"
    exit 0
}
catch {
    if ($stageDirectory -and (Test-Path -LiteralPath $stageDirectory)) {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force
    }
    Write-Output ("[NEM_GAME_BUILD_ERROR] " + $_.Exception.Message)
    exit 1
}
