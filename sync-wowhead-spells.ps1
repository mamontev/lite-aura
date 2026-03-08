param(
  [string]$OutputPath = "$PSScriptRoot\AuraLite\SpellCatalogData.lua",
  [int]$MaxEntries = 8000
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($MaxEntries -lt 200) {
  throw "MaxEntries troppo basso. Usa almeno 200."
}

$terms = @(
  "a","b","c","d","e","f","g","h","i","j","k","l","m",
  "n","o","p","q","r","s","t","u","v","w","x","y","z",
  "shield","aura","ward","blessing","curse","pain","fire","frost","arcane","holy","shadow","nature","storm","blood","totem"
)

function Get-WowheadSpellRows {
  param([string]$Term)

  $url = "https://www.wowhead.com/spells?filter=na=$([uri]::EscapeDataString($Term))"
  $html = (Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 45).Content
  $m = [regex]::Match($html, "(?s)var\s+listviewspells\s*=\s*(\[.*?\]);\s*new Listview\(\{template:\s*'spell'")
  if (-not $m.Success) {
    return @()
  }

  $rows = $m.Groups[1].Value | ConvertFrom-Json
  return @($rows)
}

$byID = @{}

foreach ($term in $terms) {
  Write-Host ("[sync] term={0}" -f $term) -ForegroundColor Cyan
  $rows = Get-WowheadSpellRows -Term $term
  foreach ($row in $rows) {
    $id = [int]$row.id
    if ($id -le 0) {
      continue
    }
    $name = [string]$row.name
    if ([string]::IsNullOrWhiteSpace($name)) {
      continue
    }

    $popularity = 0
    if ($null -ne $row.popularity) {
      $popularity = [int]$row.popularity
    }

    if ($byID.ContainsKey($id)) {
      if ($popularity -gt $byID[$id].popularity) {
        $byID[$id].popularity = $popularity
      }
      if ($byID[$id].name.Length -lt $name.Length) {
        $byID[$id].name = $name
      }
    }
    else {
      $byID[$id] = [PSCustomObject]@{
        id = $id
        name = $name
        popularity = $popularity
      }
    }
  }
}

$list = $byID.Values |
  Sort-Object @{Expression="popularity";Descending=$true}, @{Expression="name";Descending=$false}, @{Expression="id";Descending=$false}

if ($list.Count -gt $MaxEntries) {
  $list = @($list | Select-Object -First $MaxEntries)
}
else {
  $list = @($list)
}

$outDir = Split-Path -Parent $OutputPath
if (-not (Test-Path $outDir)) {
  New-Item -ItemType Directory -Path $outDir -Force | Out-Null
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("local _, ns = ...")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Generated from Wowhead spell list pages.")
[void]$sb.AppendLine(("-- Source date (UTC): {0}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")))
[void]$sb.AppendLine(("-- Entries: {0}" -f $list.Count))
[void]$sb.AppendLine("ns.SpellCatalogData = {")

foreach ($row in $list) {
  $name = [string]$row.name
  $name = $name.Replace("\", "\\").Replace("""", "\""")
  [void]$sb.AppendLine(("  {{ id = {0}, name = ""{1}"", popularity = {2} }}," -f $row.id, $name, $row.popularity))
}

[void]$sb.AppendLine("}")
[void]$sb.AppendLine("")

[IO.File]::WriteAllText($OutputPath, $sb.ToString(), [Text.Encoding]::ASCII)
Write-Host ("[sync] Wrote {0} rows -> {1}" -f $list.Count, $OutputPath) -ForegroundColor Green
