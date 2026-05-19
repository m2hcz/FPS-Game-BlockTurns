$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$pluginSource = Join-Path $projectRoot "tools\Rojo.rbxm"
$pluginDir = Join-Path $env:LOCALAPPDATA "Roblox\Plugins"
$pluginTarget = Join-Path $pluginDir "Rojo.rbxm"

if (-not (Test-Path -LiteralPath $pluginSource)) {
	throw "Plugin local nao encontrado em $pluginSource. Rode scripts/install-rojo.ps1 ou baixe Rojo.rbxm do release oficial."
}

New-Item -ItemType Directory -Force -Path $pluginDir | Out-Null
Copy-Item -LiteralPath $pluginSource -Destination $pluginTarget -Force

Get-Item -LiteralPath $pluginTarget | Select-Object FullName,Length,LastWriteTime
