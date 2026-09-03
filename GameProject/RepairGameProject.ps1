# NEMEngine SDK support: repair/sync game-project side files.
# Can be run from a game root:
#   powershell -ExecutionPolicy Bypass -File .\External\NEMEngine\GameProject\RepairGameProject.ps1
# Or from NEMEngine:
#   powershell -ExecutionPolicy Bypass -File .\Tools\RepairGameProject.ps1 -GameRoot C:\path\to\Game

param(
    [string]$GameRoot = "",
    [string]$SupportRoot = ""
)

try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}
$ErrorActionPreference = "Stop"

function Write-Utf8NoBom([string]$Path, [string]$Text) {
    $dir = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($dir)) {
        New-Item -ItemType Directory -Force -Path $dir | Out-Null
    }
    [System.IO.File]::WriteAllText($Path, $Text, [System.Text.UTF8Encoding]::new($false))
}

function Resolve-GameRoot([string]$Path) {
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $cwd = (Get-Location).Path
    if (Test-Path -LiteralPath (Join-Path $cwd "Project")) {
        return $cwd
    }

    if (Test-Path -LiteralPath (Join-Path $PSScriptRoot "Project")) {
        return $PSScriptRoot
    }

    throw "Could not resolve the game project root. Specify -GameRoot."
}

function Resolve-SupportRoot([string]$Path, [string]$ResolvedGameRoot) {
    if (-not [string]::IsNullOrWhiteSpace($Path)) {
        return (Resolve-Path -LiteralPath $Path).Path
    }

    $scriptPremake = Join-Path $PSScriptRoot "Premake\premake5.lua"
    if (Test-Path -LiteralPath $scriptPremake) {
        $text = [System.IO.File]::ReadAllText($scriptPremake)
        if ($text.Contains("__GAME_NAME__")) {
            return $PSScriptRoot
        }
    }

    $sdkSupport = Join-Path $ResolvedGameRoot "External\NEMEngine\GameProject"
    if (Test-Path -LiteralPath (Join-Path $sdkSupport "Premake\premake5.lua")) {
        return (Resolve-Path -LiteralPath $sdkSupport).Path
    }

    throw "Could not resolve GameProject support files. Update the SDK first or specify -SupportRoot."
}

function Get-GameProjectName([string]$ResolvedGameRoot) {
    $premakePath = Join-Path $ResolvedGameRoot "Premake\premake5.lua"
    if (Test-Path -LiteralPath $premakePath) {
        $text = [System.IO.File]::ReadAllText($premakePath)
        $match = [regex]::Match($text, 'GAME_NAME\s*=\s*GAME_NAME\s*or\s*"([^"]+)"')
        if ($match.Success -and $match.Groups[1].Value -ne "__GAME_NAME__") {
            return $match.Groups[1].Value
        }
    }

    $projectRoot = Join-Path $ResolvedGameRoot "Project"
    if (Test-Path -LiteralPath $projectRoot) {
        $scriptProject = Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction SilentlyContinue |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName "Scripts\GameScripts.csproj") } |
            Select-Object -First 1
        if ($scriptProject) {
            return $scriptProject.Name
        }
    }

    return Split-Path -Leaf $ResolvedGameRoot
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

function Copy-TemplateFile([string]$Source, [string]$Destination) {
    if (-not (Test-Path -LiteralPath $Source)) {
        return $false
    }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
    Copy-Item -Force -LiteralPath $Source -Destination $Destination
    return $true
}

function Ensure-ProjectDescriptor([string]$ResolvedGameRoot, [string]$GameName) {
    $appRoot = Join-Path $ResolvedGameRoot "Project\$GameName"
    if (-not (Test-Path -LiteralPath $appRoot)) {
        throw "Game application directory was not found: $appRoot"
    }

    $descriptorPath = Join-Path $appRoot ($GameName + ".nemproject")
    if (-not (Test-Path -LiteralPath $descriptorPath)) {
        $descriptor = [ordered]@{
            schemaVersion = 1
            projectGuid = [Guid]::NewGuid().ToString("N")
            name = $GameName
            sceneStorage = "ExternalActors"
            assetsDirectory = "GameAssets"
            packagesDirectory = "Packages"
            projectSettingsDirectory = "ProjectSettings"
        }
        Write-Utf8NoBom $descriptorPath (($descriptor | ConvertTo-Json) + [Environment]::NewLine)
        Write-Host "  Created: Project\$GameName\$GameName.nemproject"
    }

    foreach ($directoryName in @("GameAssets", "Packages", "ProjectSettings")) {
        New-Item -ItemType Directory -Force -Path (Join-Path $appRoot $directoryName) | Out-Null
    }
}

function Sync-PremakeFiles([string]$ResolvedGameRoot, [string]$ResolvedSupportRoot, [string]$GameName) {
    $gamePremakeDir = Join-Path $ResolvedGameRoot "Premake"
    New-Item -ItemType Directory -Force -Path $gamePremakeDir | Out-Null

    $srcPremakeLua = Join-Path $ResolvedSupportRoot "Premake\premake5.lua"
    if (Test-Path -LiteralPath $srcPremakeLua) {
        $text = [System.IO.File]::ReadAllText($srcPremakeLua).Replace("__GAME_NAME__", $GameName)
        Write-Utf8NoBom (Join-Path $gamePremakeDir "premake5.lua") $text
        Write-Host "  Updated: Premake\premake5.lua"
    }

    if (Copy-TemplateFile (Join-Path $ResolvedSupportRoot "Premake\generate_vs2026.bat") (Join-Path $gamePremakeDir "generate_vs2026.bat")) {
        Write-Host "  Updated: Premake\generate_vs2026.bat"
    }
}

function Sync-ToolSupportFiles([string]$ResolvedGameRoot, [string]$ResolvedSupportRoot) {
    $sourceTools = Join-Path $ResolvedSupportRoot "Tools"
    $gameTools = Join-Path $ResolvedGameRoot "Tools"
    foreach ($fileName in @("SDK更新.bat", "UpdateSdk.ps1")) {
        if (Copy-TemplateFile (Join-Path $sourceTools $fileName) (Join-Path $gameTools $fileName)) {
            Write-Host "  Updated: Tools\$fileName"
        }
    }

    # 旧SDKがゲームルートへ配置していた入口を除去する
    foreach ($fileName in @("SDK更新.bat", "UpdateSdk.ps1", "RepairGameProject.ps1", "ゲームプロジェクト修復.bat")) {
        $legacyPath = Join-Path $ResolvedGameRoot $fileName
        if (Test-Path -LiteralPath $legacyPath) {
            Remove-Item -Force -LiteralPath $legacyPath -ErrorAction SilentlyContinue
            if (-not (Test-Path -LiteralPath $legacyPath)) {
                Write-Host "  Removed: $fileName"
            }
        }
    }

    $gitIgnorePath = Join-Path $ResolvedGameRoot ".gitignore"
    $gitIgnoreChanged = Add-TextFileRule $gitIgnorePath "Project/**/Library/" "# NEMEngine local editor/runtime data"
    $gitIgnoreChanged = (Add-TextFileRule $gitIgnorePath "Project/**/Saved/" "# NEMEngine local editor/runtime data") -or $gitIgnoreChanged
    $gitIgnoreChanged = (Add-TextFileRule $gitIgnorePath "Project/**/UserSettings/" "# NEMEngine local editor/runtime data") -or $gitIgnoreChanged
    if ($gitIgnoreChanged) {
        Write-Host "  Updated: .gitignore"
    }

    $gitAttributesChanged = Add-TextFileRule (Join-Path $ResolvedGameRoot ".gitattributes") "*.bat text eol=crlf" "# NEMEngine Windows scripts"
    if ($gitAttributesChanged) {
        Write-Host "  Updated: .gitattributes"
    }
}

$resolvedGameRoot = Resolve-GameRoot $GameRoot
$resolvedSupportRoot = Resolve-SupportRoot $SupportRoot $resolvedGameRoot
$gameName = Get-GameProjectName $resolvedGameRoot

Write-Host "============================================"
Write-Host "  NEMEngine Game Project Repair"
Write-Host "============================================"
Write-Host "  GameRoot    : $resolvedGameRoot"
Write-Host "  SupportRoot : $resolvedSupportRoot"
Write-Host "  GameName    : $gameName"
Write-Host ""

Ensure-ProjectDescriptor $resolvedGameRoot $gameName
Sync-PremakeFiles $resolvedGameRoot $resolvedSupportRoot $gameName
Sync-ToolSupportFiles $resolvedGameRoot $resolvedSupportRoot

Write-Host ""
Write-Host "[Done] Synced game-project SDK support files and Git settings."
