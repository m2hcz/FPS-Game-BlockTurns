$ErrorActionPreference = "Stop"

$version = "7.6.1"
$toolsRoot = "C:\Users\windows 10 lc\Documents\Codex\tools\rojo"
$installDir = Join-Path $toolsRoot $version
$zipPath = Join-Path $toolsRoot "rojo-$version-windows-x86_64.zip"
$url = "https://github.com/rojo-rbx/rojo/releases/download/v$version/rojo-$version-windows-x86_64.zip"

New-Item -ItemType Directory -Force -Path $installDir | Out-Null
Invoke-WebRequest -Uri $url -OutFile $zipPath
Expand-Archive -LiteralPath $zipPath -DestinationPath $installDir -Force

$exe = (Get-ChildItem -LiteralPath $installDir -Recurse -Filter rojo.exe | Select-Object -First 1).FullName
if (-not $exe) {
	throw "rojo.exe nao foi encontrado depois da extracao."
}

$binDir = Split-Path -Parent $exe
$currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
$pathParts = @()
if ($currentPath) {
	$pathParts = $currentPath -split ";" | Where-Object { $_ -ne "" }
}

if ($pathParts -notcontains $binDir) {
	$newPath = ($pathParts + $binDir) -join ";"
	[Environment]::SetEnvironmentVariable("Path", $newPath, "User")
}

& $exe --version
& $exe plugin install
