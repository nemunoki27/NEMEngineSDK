param(
    [Parameter(Mandatory = $true)]
    [string]$SlnxPath,

    [Parameter(Mandatory = $false)]
    [string]$ScriptCoreProject = "",

    [Parameter(Mandatory = $true)]
    [string]$GameScriptsProject,

    [Parameter(Mandatory = $false)]
    [string]$GameScriptsSolutionFolder = ""
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path -LiteralPath $SlnxPath)) {
    throw "Solution file was not found: $SlnxPath"
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
        Write-Host "[SKIP] C# project was not found: $relativePath"
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
                Write-Host "[OK] Moved C# project in solution: $relativePath"
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

    Write-Host "[OK] Added C# project to solution: $relativePath"
}

Add-ProjectIfMissing $ScriptCoreProject "A10F5DB5-63D5-4B9E-9A5D-9AB2EED2E710"
$gameScriptsProjectId = if ([string]::IsNullOrWhiteSpace($GameScriptsSolutionFolder)) {
    "91B80E31-08F4-4C5E-9A06-5F4E0B9D973E"
} else {
    ""
}
Add-ProjectIfMissing $GameScriptsProject $gameScriptsProjectId $GameScriptsSolutionFolder

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$writer = [System.Xml.XmlWriter]::Create($slnxFullPath, $settings)
$xml.Save($writer)
$writer.Close()
