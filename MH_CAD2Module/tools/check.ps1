$ErrorActionPreference = 'Stop'
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    python -m pytest test -q --disable-warnings
    if ($LASTEXITCODE -ne 0) { throw 'pytest failed' }
    ruby -Itest -e 'Dir["./test/*_test.rb"].sort.each { |path| require_relative path }'
    if ($LASTEXITCODE -ne 0) { throw 'Ruby tests failed' }
    $taskSources = @(Get-ChildItem -LiteralPath . -Filter '*.rb' | ForEach-Object FullName)
    $taskSources += (Resolve-Path -LiteralPath ../MH_CAD2Module.rb).Path
    rubocop --config .rubocop.yml --format simple --force-exclusion @taskSources
    if ($LASTEXITCODE -ne 0) { throw 'RuboCop failed' }
} finally { Pop-Location }
