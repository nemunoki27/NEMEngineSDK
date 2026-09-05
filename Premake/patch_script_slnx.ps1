param(
    [Parameter(Mandatory = $true)]
    [string]$SlnxPath,

    [Parameter(Mandatory = $false)]
    [string]$ScriptCoreProject = "",

    [Parameter(Mandatory = $true)]
    [string]$GameScriptsProject,

    [Parameter(Mandatory = $false)]
    [string]$GameScriptsSolutionFolder = "",

    [Parameter(Mandatory = $false)]
    [string]$DependentProject = ""
)

$ErrorActionPreference = "Stop"
try { [Console]::OutputEncoding = [System.Text.Encoding]::UTF8 } catch {}

if (-not (Test-Path -LiteralPath $SlnxPath)) {
    throw "ソリューションが見つかりません: $SlnxPath"
}

$slnxFullPath = (Resolve-Path -LiteralPath $SlnxPath).Path
$slnxDirectory = Split-Path -Parent $slnxFullPath

function Get-RelativePath {
    param(
        [string]$BaseDirectory,
        [string]$TargetPath
    )

    $basePath = [System.IO.Path]::GetFullPath($BaseDirectory)
    $separator = [string][System.IO.Path]::DirectorySeparatorChar
    if (-not $basePath.EndsWith($separator)) {
        $basePath += $separator
    }

    $targetFullPath = [System.IO.Path]::GetFullPath($TargetPath)
    $baseUri = [System.Uri]$basePath
    $targetUri = [System.Uri]$targetFullPath
    return [System.Uri]::UnescapeDataString($baseUri.MakeRelativeUri($targetUri).ToString()).Replace("/", "\")
}

function Convert-ToSolutionRelativePath {
    param([string]$ProjectPath)

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        return $null
    }

    $resolvedPath = $ProjectPath
    if ([System.IO.Path]::IsPathRooted($ProjectPath)) {
        $resolvedPath = Get-RelativePath $slnxDirectory $ProjectPath
    } else {
        $candidateFromSolution = Join-Path $slnxDirectory $ProjectPath
        if (-not (Test-Path -LiteralPath $candidateFromSolution)) {
            $candidateFromCurrentDirectory = Resolve-Path -LiteralPath $ProjectPath -ErrorAction SilentlyContinue
            if ($null -ne $candidateFromCurrentDirectory) {
                $resolvedPath = Get-RelativePath $slnxDirectory $candidateFromCurrentDirectory.Path
            }
        }
    }

    return $resolvedPath.Replace("/", "\")
}

function Test-SolutionProjectPath {
    param([string]$RelativePath)

    if ([string]::IsNullOrWhiteSpace($RelativePath)) {
        return $false
    }

    $fullPath = if ([System.IO.Path]::IsPathRooted($RelativePath)) {
        $RelativePath
    } else {
        Join-Path $slnxDirectory $RelativePath
    }
    return Test-Path -LiteralPath $fullPath
}

function Convert-ToSolutionFolderName {
    param([string]$FolderName)

    if ([string]::IsNullOrWhiteSpace($FolderName)) {
        return ""
    }

    $normalized = $FolderName.Replace("\", "/").Trim("/")
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return ""
    }
    return "/$normalized/"
}

function New-DeterministicProjectId {
    param([string]$RelativePath)

    $normalized = "NEMEngine.GameScripts:" + $RelativePath.Replace("/", "\").ToLowerInvariant()
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $hash = $sha256.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($normalized))
    }
    finally {
        $sha256.Dispose()
    }

    $guidBytes = New-Object byte[] 16
    [System.Array]::Copy($hash, $guidBytes, $guidBytes.Length)
    return ([System.Guid]::new($guidBytes)).ToString().ToUpperInvariant()
}

[xml]$xml = Get-Content -LiteralPath $slnxFullPath -Raw
$solution = $xml.Solution

function Get-OrCreateSolutionFolder {
    param([string]$FolderName)

    $normalized = Convert-ToSolutionFolderName $FolderName
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return $solution
    }

    foreach ($folder in $solution.SelectNodes("//Folder")) {
        if ($folder.Name -ieq $normalized) {
            return $folder
        }
    }

    $node = $xml.CreateElement("Folder")
    $node.SetAttribute("Name", $normalized)
    [void]$solution.AppendChild($node)
    return $node
}

function Add-ProjectIfMissing {
    param(
        [string]$ProjectPath,
        [string]$ProjectId,
        [string]$SolutionFolder = ""
    )

    if ([string]::IsNullOrWhiteSpace($ProjectPath)) {
        return
    }

    $relativePath = Convert-ToSolutionRelativePath $ProjectPath
    if (-not (Test-SolutionProjectPath $relativePath)) {
        Write-Host "[スキップ] C#プロジェクトが見つかりません: $relativePath"
        return
    }

    if ([string]::IsNullOrWhiteSpace($ProjectId)) {
        $ProjectId = New-DeterministicProjectId $relativePath
    }
    $parent = Get-OrCreateSolutionFolder $SolutionFolder

    foreach ($project in $solution.SelectNodes("//Project")) {
        if ($project.Path -ieq $relativePath) {
            $project.SetAttribute("Id", $ProjectId)
            if (-not [object]::ReferenceEquals($project.ParentNode, $parent)) {
                [void]$parent.AppendChild($project)
                Write-Host "[成功] C#プロジェクトをソリューション内で移動しました: $relativePath"
            }
            return
        }
    }

    $node = $xml.CreateElement("Project")
    $node.SetAttribute("Path", $relativePath)
    $node.SetAttribute("Id", $ProjectId)

    if ([object]::ReferenceEquals($parent, $solution)) {
        $firstFolder = $solution.SelectSingleNode("Folder")
        if ($null -ne $firstFolder) {
            [void]$solution.InsertBefore($node, $firstFolder)
        } else {
            [void]$solution.AppendChild($node)
        }
    } else {
        [void]$parent.AppendChild($node)
    }

    Write-Host "[成功] C#プロジェクトをソリューションへ追加しました: $relativePath"
}

function Add-BuildDependency {
    param(
        [string]$ProjectPath,
        [string]$DependencyPath
    )

    if ([string]::IsNullOrWhiteSpace($ProjectPath) -or
        [string]::IsNullOrWhiteSpace($DependencyPath)) {
        return
    }

    $relativeProject = Convert-ToSolutionRelativePath $ProjectPath
    $relativeDependency = Convert-ToSolutionRelativePath $DependencyPath
    $project = @($solution.SelectNodes("//Project") | Where-Object {
        $_.Path -ieq $relativeProject
    }) | Select-Object -First 1
    if ($null -eq $project) {
        throw "依存元プロジェクトがソリューションに見つかりません: $relativeProject"
    }

    $existing = @($project.SelectNodes("BuildDependency") | Where-Object {
        $_.Project -ieq $relativeDependency
    }) | Select-Object -First 1
    if ($null -ne $existing) {
        return
    }

    $dependency = $xml.CreateElement("BuildDependency")
    $dependency.SetAttribute("Project", $relativeDependency)
    [void]$project.AppendChild($dependency)
    Write-Host "[成功] C#プロジェクトのビルド依存を追加しました: $relativeProject"
}

Add-ProjectIfMissing $ScriptCoreProject "A10F5DB5-63D5-4B9E-9A5D-9AB2EED2E710"
$gameScriptsProjectId = if ([string]::IsNullOrWhiteSpace($GameScriptsSolutionFolder)) {
    "91B80E31-08F4-4C5E-9A06-5F4E0B9D973E"
} else {
    ""
}
Add-ProjectIfMissing $GameScriptsProject $gameScriptsProjectId $GameScriptsSolutionFolder
Add-BuildDependency $DependentProject $GameScriptsProject

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$writer = [System.Xml.XmlWriter]::Create($slnxFullPath, $settings)
$xml.Save($writer)
$writer.Close()
