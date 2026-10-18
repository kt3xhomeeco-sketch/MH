param([string]$Compiler = 'C:\Ruby32-x64\msys64\ucrt64\bin\gcc.exe')
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$previousPath = $env:PATH
try {
  $env:PATH = (Split-Path $Compiler -Parent) + ';' + $previousPath
  & $Compiler -shared -Os -Wall -Wextra -Werror -static-libgcc '-Wl,--no-insert-timestamp' -s (Join-Path $PSScriptRoot 'native\assembly_input.c') -o (Join-Path $projectRoot 'native\assembly_input_v2.dll') -luser32
  if ($LASTEXITCODE -ne 0) { throw 'Assembly input build failed.' }
} finally { $env:PATH = $previousPath }
