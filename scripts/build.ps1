$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$outDir = Join-Path $projectRoot "out"
$outFile = Join-Path $outDir "BlockTurns.rbxl"

New-Item -ItemType Directory -Force -Path $outDir | Out-Null
Set-Location -LiteralPath $projectRoot

& "$PSScriptRoot\rojo.ps1" build default.project.json --output $outFile
