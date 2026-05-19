$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $PSScriptRoot
$fallbackRojo = "C:\Users\windows 10 lc\Documents\Codex\tools\rojo\7.6.1\rojo.exe"

$rojoCommand = Get-Command rojo -ErrorAction SilentlyContinue
if ($rojoCommand) {
	& $rojoCommand.Source @args
	exit $LASTEXITCODE
}

if (Test-Path -LiteralPath $fallbackRojo) {
	& $fallbackRojo @args
	exit $LASTEXITCODE
}

throw "Rojo nao encontrado. Reinicie o Cursor/terminal para atualizar o PATH ou rode scripts/install-rojo.ps1."
