# Remove legacy root tools after the SDK update process exits

param(
    [Parameter(Mandatory = $true)]
    [string]$GameRoot,
    [Parameter(Mandatory = $true)]
    [int]$WaitForProcessID
)

$ErrorActionPreference = "SilentlyContinue"
$resolvedGameRoot = [System.IO.Path]::GetFullPath($GameRoot)
if (-not (Test-Path -LiteralPath (Join-Path $resolvedGameRoot "Project") -PathType Container) -or
    -not (Test-Path -LiteralPath (Join-Path $resolvedGameRoot "Tools\UpdateSdk.ps1") -PathType Leaf) -or
    -not (Test-Path -LiteralPath (Join-Path $resolvedGameRoot "Tools\FinalizeSdkToolMigration.ps1") -PathType Leaf)) {
    exit 1
}

Wait-Process -Id $WaitForProcessID -ErrorAction SilentlyContinue
Start-Sleep -Milliseconds 500

$sdkUpdateBat = "SDK$([char]0x66F4)$([char]0x65B0).bat"
$repairBat = "$([char]0x30B2)$([char]0x30FC)$([char]0x30E0)$([char]0x30D7)$([char]0x30ED)" +
    "$([char]0x30B8)$([char]0x30A7)$([char]0x30AF)$([char]0x30C8)$([char]0x4FEE)$([char]0x5FA9).bat"
$legacyFiles = @($sdkUpdateBat, "UpdateSdk.ps1", "RepairGameProject.ps1", $repairBat)
for ($attempt = 0; $attempt -lt 20; ++$attempt) {
    foreach ($fileName in $legacyFiles) {
        $legacyPath = Join-Path $resolvedGameRoot $fileName
        if (Test-Path -LiteralPath $legacyPath -PathType Leaf) {
            Remove-Item -Force -LiteralPath $legacyPath -ErrorAction SilentlyContinue
        }
    }

    $remaining = $legacyFiles | Where-Object {
        Test-Path -LiteralPath (Join-Path $resolvedGameRoot $_) -PathType Leaf
    }
    if ($remaining.Count -eq 0) {
        exit 0
    }
    Start-Sleep -Milliseconds 500
}
exit 1
