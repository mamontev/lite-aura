Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $repoRoot

$luaCandidates = @(
  "C:\Program Files (x86)\Lua\5.1\lua.exe",
  "C:\Program Files\Lua\5.1\lua.exe",
  "lua.exe"
)

$lua = $null
foreach ($candidate in $luaCandidates) {
  if ($candidate -eq "lua.exe") {
    $cmd = Get-Command lua.exe -ErrorAction SilentlyContinue
    if ($cmd) {
      $lua = $cmd.Source
      break
    }
  } elseif (Test-Path $candidate) {
    $lua = $candidate
    break
  }
}

if (-not $lua) {
  throw "Lua interpreter not found."
}

& $lua "tests/run.lua"
