param(
    [Parameter(Mandatory = $true)]
    [string]$SlnxPath,

    [Parameter(Mandatory = $false)]
    [string]$ScriptCoreProject = "",

    [Parameter(Mandatory = $true)]
    [string]$GameScriptsProject
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

[xml]$xml = Get-Content -LiteralPath $slnxFullPath -Raw
$solution = $xml.Solution

function Add-ProjectIfMissing {
    param(
        [string]$ProjectPath,
        [string]$ProjectId
    )

    $relativePath = Convert-ToSolutionRelativePath $ProjectPath
    if (-not (Test-SolutionProjectPath $relativePath)) {
        Write-Host "[SKIP] C# project was not found: $relativePath"
        return
    }

    foreach ($project in $solution.SelectNodes("Project")) {
        if ($project.Path -ieq $relativePath) {
            return
        }
    }

    $node = $xml.CreateElement("Project")
    $node.SetAttribute("Path", $relativePath)
    $node.SetAttribute("Id", $ProjectId)

    $firstFolder = $solution.SelectSingleNode("Folder")
    if ($null -ne $firstFolder) {
        [void]$solution.InsertBefore($node, $firstFolder)
    } else {
        [void]$solution.AppendChild($node)
    }

    Write-Host "[OK] Added C# project to solution: $relativePath"
}

Add-ProjectIfMissing $ScriptCoreProject "A10F5DB5-63D5-4B9E-9A5D-9AB2EED2E710"
Add-ProjectIfMissing $GameScriptsProject "91B80E31-08F4-4C5E-9A06-5F4E0B9D973E"

$settings = [System.Xml.XmlWriterSettings]::new()
$settings.Indent = $true
$settings.OmitXmlDeclaration = $true
$writer = [System.Xml.XmlWriter]::Create($slnxFullPath, $settings)
$xml.Save($writer)
$writer.Close()
