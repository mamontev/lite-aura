param(
  [string]$Source = "$PSScriptRoot\AuraLite",
  [string]$TargetRoot = "F:\World of Warcraft\_retail_\Interface\AddOns",
  [switch]$Watch
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$target = Join-Path $TargetRoot "AuraLite"

function Sync-Addon {
  param(
    [string]$From,
    [string]$To
  )

  if (-not (Test-Path $From)) {
    throw "Source path not found: $From"
  }

  if (-not (Test-Path $To)) {
    New-Item -ItemType Directory -Force -Path $To | Out-Null
  }

  # Fast-fail if destination is not writable (avoids false "Sync OK" on permission issues).
  $probe = Join-Path $To ".__auralite_write_probe.tmp"
  try {
    Set-Content -Path $probe -Value "x" -Encoding ASCII -NoNewline -ErrorAction Stop
    Remove-Item -Path $probe -Force -ErrorAction Stop
  }
  catch {
    throw "Destination is not writable: $To ($($_.Exception.Message))"
  }

  $args = @(
    $From,
    $To,
    "/MIR",
    "/R:2",
    "/W:1",
    "/NFL",
    "/NDL",
    "/NP",
    "/NJH",
    "/NJS",
    "/XD", ".git", ".vscode",
    "/XF", "*.tmp"
  )

  & robocopy @args | Out-Host
  $code = $LASTEXITCODE
  if ($code -ge 8) {
    throw "Robocopy failed with exit code $code"
  }

  Write-Host ("[{0}] Sync OK -> {1}" -f (Get-Date -Format "HH:mm:ss"), $To) -ForegroundColor Green
}

function Start-Watch {
  param(
    [string]$From,
    [string]$To
  )

  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $From
  $watcher.IncludeSubdirectories = $true
  $watcher.EnableRaisingEvents = $true
  $watcher.NotifyFilter = [IO.NotifyFilters]'FileName, LastWrite, DirectoryName, Size'

  $script:pending = $false
  $lastRun = Get-Date "2000-01-01"

  $handler = {
    $script:pending = $true
  }

  $subs = @(
    Register-ObjectEvent -InputObject $watcher -EventName Changed -Action $handler,
    Register-ObjectEvent -InputObject $watcher -EventName Created -Action $handler,
    Register-ObjectEvent -InputObject $watcher -EventName Deleted -Action $handler,
    Register-ObjectEvent -InputObject $watcher -EventName Renamed -Action $handler
  )

  Write-Host "Watch mode attiva. Premi Ctrl+C per uscire." -ForegroundColor Cyan

  try {
    while ($true) {
      Start-Sleep -Milliseconds 350
      if ($script:pending) {
        $now = Get-Date
        if (($now - $lastRun).TotalMilliseconds -ge 500) {
          $script:pending = $false
          Sync-Addon -From $From -To $To
          $lastRun = Get-Date
        }
      }
    }
  }
  finally {
    foreach ($s in $subs) {
      Unregister-Event -SourceIdentifier $s.SourceIdentifier -ErrorAction SilentlyContinue
      $s | Remove-Job -Force -ErrorAction SilentlyContinue
    }
    $watcher.Dispose()
  }
}

Write-Host "Source: $Source"
Write-Host "Target: $target"

Sync-Addon -From $Source -To $target

if ($Watch) {
  Start-Watch -From $Source -To $target
}
