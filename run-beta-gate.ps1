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

$reportDir = Join-Path $repoRoot "tests\out"
if (-not (Test-Path $reportDir)) {
  New-Item -ItemType Directory -Path $reportDir | Out-Null
}
$reportPath = Join-Path $reportDir "beta-readiness-report.txt"

$lines = @()
$lines += "AuraLite Beta Readiness Report"
$lines += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss zzz')"
$lines += ""

$syntaxOutput = & $lua -e "local syntax = dofile('tests/lib/syntax_check.lua'); local result = assert(syntax.run('F:/testAddon/AuraLite')); print(string.format('syntax_checked=%d syntax_failed=%d', result.checked, result.failed)); if result.failed > 0 then for i = 1, #result.errors do local e = result.errors[i]; print(e.path .. ' :: ' .. tostring(e.err)); end os.exit(1) end"
$syntaxExit = $LASTEXITCODE
$lines += "[Syntax]"
$lines += $syntaxOutput
$lines += ""

$testOutput = & $lua "tests/run.lua"
$testExit = $LASTEXITCODE
$lines += "[Automated Tests]"
$lines += $testOutput
$lines += ""

$criticalPatterns = @(
  "BuildWatchItemFromModel spellID=",
  "UI UpdateEntry prepare key=",
  "SavePosition key=",
  "ApplyPosition key="
)
$hits = @()
$luaFiles = Get-ChildItem -Path "$repoRoot\AuraLite" -Recurse -File -Filter *.lua | Select-Object -ExpandProperty FullName
foreach ($pattern in $criticalPatterns) {
  $match = Select-String -Path $luaFiles -Pattern $pattern -SimpleMatch -ErrorAction SilentlyContinue
  if ($match -and $match.Count -gt 0) {
    $hits += $pattern
  }
}
$lines += "[Debug Hygiene]"
if ($hits.Count -eq 0) {
  $lines += "ok: no temporary deep-diagnostic log patterns detected"
} else {
  $lines += "warning: found temporary debug patterns:"
  $lines += ($hits | ForEach-Object { "- $_" })
}
$lines += ""

$go = ($syntaxExit -eq 0) -and ($testExit -eq 0) -and ($hits.Count -eq 0)
$lines += "[Exit Criteria]"
$lines += "- syntax gate passes"
$lines += "- regression/stateful proc/group/identity tests pass"
$lines += "- no temporary deep diagnostic log noise remains"
$lines += ""
$lines += if ($go) { "BETA READY: YES" } else { "BETA READY: NO" }

$lines | Set-Content -Path $reportPath -Encoding UTF8
$lines | ForEach-Object { Write-Output $_ }

if (-not $go) {
  exit 1
}
