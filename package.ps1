param(
  [string]$ProjectRoot = $PSScriptRoot,
  [string]$AddonDirName = "AuraLite",
  [string]$DistDir = "$PSScriptRoot\dist",
  [string]$Channel = "beta",
  [string]$Label = ""
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-TocValue {
  param(
    [string]$TocPath,
    [string]$Key
  )

  $pattern = "^\s*##\s*" + [Regex]::Escape($Key) + "\s*:\s*(.+?)\s*$"
  foreach ($line in Get-Content -Path $TocPath) {
    if ($line -match $pattern) {
      return $matches[1].Trim()
    }
  }
  throw "Missing TOC key '$Key' in $TocPath"
}

$addonRoot = Join-Path $ProjectRoot $AddonDirName
$tocPath = Join-Path $addonRoot ($AddonDirName + ".toc")

if (-not (Test-Path $addonRoot)) {
  throw "Addon folder not found: $addonRoot"
}
if (-not (Test-Path $tocPath)) {
  throw "TOC not found: $tocPath"
}

$title = Get-TocValue -TocPath $tocPath -Key "Title"
$version = Get-TocValue -TocPath $tocPath -Key "Version"

$safeChannel = ($Channel -replace "[^A-Za-z0-9._-]", "").ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($safeChannel)) {
  $safeChannel = "beta"
}

$suffix = if ([string]::IsNullOrWhiteSpace($Label)) {
  $safeChannel
} else {
  ($safeChannel + "-" + ($Label -replace "[^A-Za-z0-9._-]", ""))
}

$archiveName = "{0}-{1}-{2}.zip" -f $AddonDirName, $version, $suffix
$archivePath = Join-Path $DistDir $archiveName

New-Item -ItemType Directory -Force -Path $DistDir | Out-Null
if (Test-Path $archivePath) {
  Remove-Item -Path $archivePath -Force
}

Compress-Archive -Path $addonRoot -DestinationPath $archivePath -Force

Write-Host ("Package created: {0}" -f $archivePath) -ForegroundColor Green
Write-Host ("Title:   {0}" -f $title)
Write-Host ("Version: {0}" -f $version)
Write-Host ("Channel: {0}" -f $safeChannel)

