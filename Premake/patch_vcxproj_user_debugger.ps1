param(
    [Parameter(Mandatory = $true)]
    [string]$ProjectUserPath,

    [string]$WorkingDirectory = "..",

    [string]$DebuggerType = "NativeWithManagedCore",

    # デバッガ起動時に渡す追加の環境変数(例: "NEMENGINE_ROOT=C:\...\Project")。空なら設定しない。
    # 取り込みゲームは作業ディレクトリがゲームフォルダになるため、エンジンのProjectルートをこの変数で示す。
    [string]$EnvironmentVariables = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Ensure-PropertyGroup {
    param(
        [xml]$Document,
        [string]$Condition
    )

    # 新規作成直後の <Project/> は PropertyGroup を持たない。StrictMode 下では
    # $Document.Project.PropertyGroup の直接アクセスが「メンバー無し」で throw するため、
    # ChildNodes を走査して存在チェックする（不在でも空集合で安全に進む）
    $group = @($Document.Project.ChildNodes | Where-Object { $_.LocalName -eq 'PropertyGroup' -and $_.Condition -eq $Condition }) | Select-Object -First 1
    if ($null -ne $group) {
        return $group
    }

    $group = $Document.CreateElement("PropertyGroup", $Document.Project.NamespaceURI)
    $conditionAttribute = $Document.CreateAttribute("Condition")
    $conditionAttribute.Value = $Condition
    [void]$group.Attributes.Append($conditionAttribute)
    [void]$Document.Project.AppendChild($group)
    return $group
}

function Set-ChildValue {
    param(
        $Parent,
        [string]$Name,
        [string]$Value
    )

    $child = $null
    foreach ($node in $Parent.ChildNodes) {
        if ($node.LocalName -eq $Name) {
            $child = $node
            break
        }
    }
    if ($null -eq $child) {
        $child = $Parent.OwnerDocument.CreateElement($Name, $Parent.NamespaceURI)
        [void]$Parent.AppendChild($child)
    }
    $child.InnerText = $Value
}

$resolvedUserPath = (Resolve-Path -LiteralPath $ProjectUserPath -ErrorAction SilentlyContinue)
if ($null -ne $resolvedUserPath) {
    [xml]$document = Get-Content -LiteralPath $resolvedUserPath.Path
} else {
    $document = New-Object xml
    [void]$document.LoadXml('<?xml version="1.0" encoding="utf-8"?><Project ToolsVersion="Current" xmlns="http://schemas.microsoft.com/developer/msbuild/2003" />')
}

$conditions = @(
    "'`$(Configuration)|`$(Platform)'=='Debug|x64'",
    "'`$(Configuration)|`$(Platform)'=='Develop|x64'",
    "'`$(Configuration)|`$(Platform)'=='Release|x64'"
)

foreach ($condition in $conditions) {
    $group = Ensure-PropertyGroup -Document $document -Condition $condition
    Set-ChildValue -Parent $group -Name "LocalDebuggerWorkingDirectory" -Value $WorkingDirectory
    Set-ChildValue -Parent $group -Name "DebuggerFlavor" -Value "WindowsLocalDebugger"
    Set-ChildValue -Parent $group -Name "LocalDebuggerDebuggerType" -Value $DebuggerType

    # 既存の環境変数(VS既定)も引き継げるよう $(LocalDebuggerEnvironment) を末尾に残す
    if (-not [string]::IsNullOrWhiteSpace($EnvironmentVariables)) {
        Set-ChildValue -Parent $group -Name "LocalDebuggerEnvironment" -Value ($EnvironmentVariables + "`n" + '$(LocalDebuggerEnvironment)')
    }
}

$directory = Split-Path -Parent $ProjectUserPath
if (-not [string]::IsNullOrWhiteSpace($directory)) {
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
}

$utf8NoBom = New-Object System.Text.UTF8Encoding($false)
[System.IO.File]::WriteAllText($ProjectUserPath, $document.OuterXml, $utf8NoBom)

[xml]$verifyDocument = Get-Content -LiteralPath $ProjectUserPath -Raw
foreach ($condition in $conditions) {
    $group = @($verifyDocument.Project.ChildNodes | Where-Object { $_.LocalName -eq 'PropertyGroup' -and $_.Condition -eq $condition }) | Select-Object -First 1
    if ($null -eq $group) {
        throw "Debugger property group was not written: $condition"
    }

    if ($group.LocalDebuggerDebuggerType -ne $DebuggerType) {
        throw "Debugger type verification failed for $condition. Actual value: $($group.LocalDebuggerDebuggerType)"
    }
}

Write-Host "[OK] Patched debugger settings: $ProjectUserPath"
