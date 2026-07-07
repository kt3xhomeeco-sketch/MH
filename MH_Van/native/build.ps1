Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Push-Location $Root
try {
  if (-not (Get-Command ruby -ErrorAction SilentlyContinue)) {
    $rubyRoot = "C:\Ruby32-x64"
    if (Test-Path (Join-Path $rubyRoot "bin\ruby.exe")) {
      $env:Path = (Join-Path $rubyRoot "bin") + ";" +
        (Join-Path $rubyRoot "msys64\ucrt64\bin") + ";" +
        (Join-Path $rubyRoot "msys64\usr\bin") + ";" +
        $env:Path
    } else {
      throw "ruby is not available in PATH. Use a Ruby version matching SketchUp Ruby."
    }
  }

  $rubyInfo = ruby -rrbconfig -e "puts RUBY_VERSION; puts RbConfig::CONFIG['arch']; puts RbConfig::CONFIG['MAKE']"
  $rubyVersion = $rubyInfo[0]
  $rubyArch = $rubyInfo[1]
  $makeTool = $rubyInfo[2]
  if (-not $makeTool) {
    $makeTool = "make"
  }

  Write-Host "Ruby: $rubyVersion ($rubyArch)"
  Write-Host "Make: $makeTool"

  $makeCommand = ($makeTool -split '\s+')[0]
  if (-not (Get-Command $makeCommand -ErrorAction SilentlyContinue)) {
    throw "$makeCommand is not available in PATH. Use the compiler/devkit that belongs to this Ruby."
  }

  ruby .\extconf.rb
  & $makeCommand
} finally {
  Pop-Location
}
