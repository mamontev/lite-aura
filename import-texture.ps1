param(
  [Parameter(Mandatory = $true)]
  [string]$SourcePath,
  [string]$Name,
  [switch]$Deploy
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoRoot = $PSScriptRoot
$addonMedia = Join-Path $repoRoot "AuraLite\Media\Custom"
if (-not (Test-Path $addonMedia)) {
  New-Item -ItemType Directory -Path $addonMedia -Force | Out-Null
}

$resolvedSource = Resolve-Path $SourcePath -ErrorAction Stop
$srcFile = Get-Item $resolvedSource
$ext = $srcFile.Extension.ToLowerInvariant()

if ([string]::IsNullOrWhiteSpace($Name)) {
  $Name = [IO.Path]::GetFileNameWithoutExtension($srcFile.Name)
}

# Keep only safe file-name chars for WoW texture path usage.
$safeName = ($Name -replace '[^a-zA-Z0-9_\-]', '_').Trim('_')
if ([string]::IsNullOrWhiteSpace($safeName)) {
  throw "Invalid output name after sanitization."
}

$destBase = Join-Path $addonMedia $safeName
$destTga = "$destBase.tga"
$destBlp = "$destBase.blp"

if ($ext -eq ".tga") {
  Copy-Item -Path $srcFile.FullName -Destination $destTga -Force
  $finalFile = $destTga
}
elseif ($ext -eq ".blp") {
  Copy-Item -Path $srcFile.FullName -Destination $destBlp -Force
  $finalFile = $destBlp
}
elseif ($ext -in @(".png", ".jpg", ".jpeg", ".bmp", ".webp")) {
  $magick = Get-Command magick -ErrorAction SilentlyContinue
  if (-not $magick) {
    throw "Source is $ext. Install ImageMagick (magick) or provide .tga/.blp."
  }

  & $magick.Source $srcFile.FullName -alpha on -type TrueColorAlpha $destTga
  if ($LASTEXITCODE -ne 0 -or -not (Test-Path $destTga)) {
    throw "Image conversion failed via ImageMagick."
  }
  $finalFile = $destTga
}
else {
  throw "Unsupported extension '$ext'. Supported: .tga .blp .png .jpg .jpeg .bmp .webp"
}

$textureToken = "Interface\AddOns\AuraLite\Media\Custom\$safeName"

Write-Host "Imported texture: $finalFile" -ForegroundColor Green
Write-Host "Use this in AuraLite custom image field: $textureToken" -ForegroundColor Cyan
Write-Host "You can also type only: $safeName" -ForegroundColor Cyan

if ($Deploy) {
  $deployScript = Join-Path $repoRoot "deploy.ps1"
  if (-not (Test-Path $deployScript)) {
    throw "deploy.ps1 not found at $deployScript"
  }
  powershell -NoProfile -ExecutionPolicy Bypass -File $deployScript
}
