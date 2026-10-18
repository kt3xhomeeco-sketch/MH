param([Parameter(Mandatory=$true)][string]$CodeFile, [int]$ExpectedPid = 12360, [int]$ExpectedPort = 63277)
$ErrorActionPreference = 'Stop'
$qaSketchup = Get-Process -Id $ExpectedPid
if ($qaSketchup.ProcessName -ne 'SketchUp') { throw 'Expected a pinned SketchUp process.' }
$rubyCode = Get-Content -LiteralPath $CodeFile -Raw -Encoding utf8
$rubyCode = "raise 'Wrong SketchUp instance' unless Process.pid == $ExpectedPid`n" + $rubyCode
$payload = @{jsonrpc='2.0';id='module-studio-check';method='tools/call';params=@{name='execute_ruby';arguments=@{code=$rubyCode}}} | ConvertTo-Json -Depth 8 -Compress
$reply = Invoke-RestMethod -Uri "http://127.0.0.1:$ExpectedPort/mcp" -Method Post -ContentType 'application/json;charset=utf-8' -Body ([System.Text.Encoding]::UTF8.GetBytes($payload)) -TimeoutSec 120
$reply | ConvertTo-Json -Depth 10
if ($reply.error -or $reply.result.isError) { throw 'Native VBO execution failed. Inspect the returned diagnostic.' }
