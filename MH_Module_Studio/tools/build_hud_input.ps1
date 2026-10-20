param([string]$Compiler = 'C:\Ruby32-x64\msys64\ucrt64\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$target = Join-Path $projectRoot 'native'
$null = New-Item -ItemType Directory -Path $target -Force
$previousPath = $env:PATH
try {
  $env:PATH = (Split-Path $Compiler -Parent) + ';' + $previousPath
  & $Compiler -shared -Os -Wall -Wextra -Werror -static-libgcc '-Wl,--no-insert-timestamp' -s (Join-Path $PSScriptRoot 'native\hud_input.c') -o (Join-Path $target 'hud_input_v3.dll') -luser32
  if ($LASTEXITCODE -ne 0) { throw 'HUD native helper build failed.' }
} finally { $env:PATH = $previousPath }
