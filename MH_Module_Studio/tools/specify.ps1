# Run the pinned, isolated Spec Kit installation from this project's directory.
$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$specifyExe = Join-Path $projectRoot '.devtools\spec-kit\Scripts\specify.exe'
if (-not (Test-Path -LiteralPath $specifyExe)) {
    throw 'Spec Kit is missing. See TOOLING.md for the local installation command.'
}
$previousInitDir = $env:SPECIFY_INIT_DIR
Push-Location -LiteralPath $projectRoot
try {
    $env:SPECIFY_INIT_DIR = $projectRoot
    & $specifyExe @args
    $toolExitCode = $LASTEXITCODE
} finally {
    $env:SPECIFY_INIT_DIR = $previousInitDir
    Pop-Location
}
exit $toolExitCode
