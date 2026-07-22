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
        $found = & $vswhere -latest -products * -requires Microsoft.Component.MSBuild -find "MSBuild\**\Bin\MSBuild.exe" |
            Select-Object -First 1
        if ($found -and (Test-Path -LiteralPath $found)) {
            return $found
        }
    }

    $command = Get-Command "MSBuild.exe" -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    throw "MSBuild.exe was not found"
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
        throw "Path escapes the output directory: $Relative"
    }
    return $childFull
}

$stageDirectory = ""
try {
    if (-not (Test-Path -LiteralPath $ManifestPath)) {
        throw "Game build manifest was not found"
    }

    $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
    $projectPath = [System.IO.Path]::GetFullPath([string]$manifest.projectPath)
    $sourceRuntime = [System.IO.Path]::GetFullPath([string]$manifest.sourceRuntime)
    $outputRoot = [System.IO.Path]::GetFullPath([string]$manifest.outputRoot)
    $productName = [string]$manifest.productName
    $runtimeExecutable = [string]$manifest.runtimeExecutable
    $executableName = [string]$manifest.executableName

    if (-not (Test-Path -LiteralPath $projectPath)) {
        throw "Game project was not found: $projectPath"
    }

    $msbuild = Get-MSBuildPath
    Write-Output "Starting Release build"
    & $msbuild $projectPath /t:Build /p:Configuration=Release /p:Platform=x64 /m /nodeReuse:false /v:minimal
    if ($LASTEXITCODE -ne 0) {
        throw "Release build failed"
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

    $runtimeFiles = @(
        $runtimeExecutable,
        "NEMEngine.dll",
        "dxcompiler.dll",
        "dxil.dll",
        "nethost.dll"
    )
    foreach ($runtimeFile in $runtimeFiles) {
        $source = Join-Path $sourceRuntime $runtimeFile
        if (-not (Test-Path -LiteralPath $source)) {
            throw "Runtime file is missing: $source"
        }
        $destinationName = if ($runtimeFile -eq $runtimeExecutable) { $executableName } else { $runtimeFile }
        Copy-Item -LiteralPath $source -Destination (Join-Path $stageDirectory $destinationName) -Force
    }

    $managedSource = Join-Path $sourceRuntime "Managed"
    if (-not (Test-Path -LiteralPath $managedSource)) {
        throw "Managed runtime was not found: $managedSource"
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
            throw "Asset file is missing: $source"
        }
        $destination = Get-ChildPath -Root $stageDirectory -Relative $relative
        New-Item -ItemType Directory -Path ([System.IO.Path]::GetDirectoryName($destination)) -Force | Out-Null
        Copy-Item -LiteralPath $source -Destination $destination -Force
    }

    $configDirectory = Join-Path $stageDirectory "Config"
    New-Item -ItemType Directory -Path $configDirectory -Force | Out-Null
    Write-Utf8Json -Path (Join-Path $configDirectory "activeScene.exeConfig.json") -Value @{
        activeScene = [string]$manifest.startupScene
    }
    Write-Utf8Json -Path (Join-Path $configDirectory "gameBuild.exeConfig.json") -Value @{
        gameName = $productName
        startupFullscreen = [bool]$manifest.startupFullscreen
    }
    Write-Utf8Json -Path (Join-Path $stageDirectory ".nemBuildManifest.json") -Value @{
        productName = $productName
        executableName = $executableName
        startupScene = [string]$manifest.startupScene
        startupFullscreen = [bool]$manifest.startupFullscreen
        assetFileCount = @($manifest.files).Count
        configuration = "Release"
    }

    if (Test-Path -LiteralPath $targetDirectory) {
        $marker = Join-Path $targetDirectory ".nemBuildManifest.json"
        if (-not (Test-Path -LiteralPath $marker -PathType Leaf)) {
            throw "Existing directory is not a NEMEngine product build: $targetDirectory"
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

    Write-Output "Product build completed: $targetDirectory"
    exit 0
}
catch {
    if ($stageDirectory -and (Test-Path -LiteralPath $stageDirectory)) {
        Remove-Item -LiteralPath $stageDirectory -Recurse -Force
    }
    Write-Output ("[NEM_GAME_BUILD_ERROR] " + $_.Exception.Message)
    exit 1
}
