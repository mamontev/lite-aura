param(
  [string]$OutputPath = "$PSScriptRoot\AuraLite\SpellCatalogData.lua",
  [int]$MaxEntries = 20000,
  [string[]]$ImportCsvPaths = @(),
  [string]$TermsPath = "",
  [string[]]$ExtraTerms = @(),
  [switch]$SkipWowheadSeed
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

if ($MaxEntries -lt 500) {
  throw "MaxEntries troppo basso. Usa almeno 500."
}

$defaultTerms = @(
  "a","b","c","d","e","f","g","h","i","j","k","l","m",
  "n","o","p","q","r","s","t","u","v","w","x","y","z",
  "ability","aura","barrier","blast","blood","bolt","brand","burst","charge","clap","cleave","curse",
  "debuff","echo","empower","fire","flame","focus","frost","guardian","heal","holy","hunt","ice","impact",
  "lash","light","mark","mend","nature","nova","pain","poison","proc","protection","rage","rend","roar",
  "seal","shield","shock","slam","smash","spirit","storm","surge","strike","target","thunder","totem",
  "venom","ward","whirl","wind","wrath",
  "thunder clap","thunder blast","bloodthirst","mortal strike","execute","shield slam","rend","avatar"
)

function Get-TermList {
  $terms = New-Object System.Collections.Generic.List[string]
  foreach ($term in $defaultTerms) {
    if (-not [string]::IsNullOrWhiteSpace($term)) {
      [void]$terms.Add($term.Trim())
    }
  }
  foreach ($term in $ExtraTerms) {
    if (-not [string]::IsNullOrWhiteSpace($term)) {
      [void]$terms.Add($term.Trim())
    }
  }
  if (-not [string]::IsNullOrWhiteSpace($TermsPath) -and (Test-Path $TermsPath)) {
    foreach ($line in (Get-Content -Path $TermsPath)) {
      if (-not [string]::IsNullOrWhiteSpace($line)) {
        [void]$terms.Add($line.Trim())
      }
    }
  }
  return @($terms | Where-Object { $_ -ne "" } | Sort-Object -Unique)
}

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

function Find-FirstPropertyName {
  param(
    $Row,
    [string[]]$Candidates
  )

  foreach ($candidate in $Candidates) {
    if ($null -ne ($Row.PSObject.Properties[$candidate])) {
      return $candidate
    }
  }
  return $null
}

function Add-OrUpdateSpell {
  param(
    [hashtable]$ByID,
    [int]$ID,
    [string]$Name,
    [int]$Popularity,
    [string]$Source
  )

  if ($ID -le 0 -or [string]::IsNullOrWhiteSpace($Name)) {
    return
  }

  if ($ByID.ContainsKey($ID)) {
    if ($Popularity -gt $ByID[$ID].popularity) {
      $ByID[$ID].popularity = $Popularity
    }
    if ($ByID[$ID].name.Length -lt $Name.Length) {
      $ByID[$ID].name = $Name
    }
    if ($Source -and -not $ByID[$ID].sources.Contains($Source)) {
      [void]$ByID[$ID].sources.Add($Source)
    }
    return
  }

  $ByID[$ID] = [PSCustomObject]@{
    id = $ID
    name = $Name
    popularity = $Popularity
    sources = (New-Object System.Collections.Generic.List[string])
  }
  if ($Source) {
    [void]$ByID[$ID].sources.Add($Source)
  }
}

function Import-SpellsFromCsv {
  param(
    [hashtable]$ByID,
    [string[]]$Paths
  )

  $idCandidates = @("id","ID","spellID","SpellID","SpellId")
  $nameCandidates = @(
    "name","Name","Name_lang","Name_lang_enUS","Name_lang_enus","Name_lang_enGB","DisplayName",
    "SpellName","enUS","enGb"
  )
  $popularityCandidates = @("popularity","Popularity","rank","Rank")

  foreach ($path in $Paths) {
    if ([string]::IsNullOrWhiteSpace($path)) {
      continue
    }
    $resolved = Resolve-Path -Path $path -ErrorAction Stop
    Write-Host ("[sync] import csv={0}" -f $resolved) -ForegroundColor Yellow
    $rows = Import-Csv -Path $resolved
    foreach ($row in $rows) {
      $idName = Find-FirstPropertyName -Row $row -Candidates $idCandidates
      $spellNameName = Find-FirstPropertyName -Row $row -Candidates $nameCandidates
      if (-not $idName -or -not $spellNameName) {
        continue
      }

      $id = 0
      [void][int]::TryParse([string]$row.$idName, [ref]$id)
      $name = [string]$row.$spellNameName
      if ([string]::IsNullOrWhiteSpace($name)) {
        continue
      }

      $popularity = 2000000
      $popName = Find-FirstPropertyName -Row $row -Candidates $popularityCandidates
      if ($popName) {
        $tmp = 0
        if ([int]::TryParse([string]$row.$popName, [ref]$tmp)) {
          $popularity = [Math]::Max($popularity, $tmp)
        }
      }

      Add-OrUpdateSpell -ByID $ByID -ID $id -Name $name -Popularity $popularity -Source ("csv:" + [IO.Path]::GetFileName([string]$resolved))
    }
  }
}

$byID = @{}

if ($ImportCsvPaths.Count -gt 0) {
  Import-SpellsFromCsv -ByID $byID -Paths $ImportCsvPaths
}

if (-not $SkipWowheadSeed) {
  $terms = Get-TermList
  foreach ($term in $terms) {
    Write-Host ("[sync] wowhead term={0}" -f $term) -ForegroundColor Cyan
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

      Add-OrUpdateSpell -ByID $byID -ID $id -Name $name -Popularity $popularity -Source ("wowhead:" + $term)
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

$sourceSummary = @()
if ($ImportCsvPaths.Count -gt 0) {
  $sourceSummary += "CSV imports"
}
if (-not $SkipWowheadSeed) {
  $sourceSummary += "Wowhead seeded search"
}
if ($sourceSummary.Count -eq 0) {
  throw "Nessuna sorgente attiva. Usa Wowhead seed di default o passa ImportCsvPaths."
}

$sb = New-Object System.Text.StringBuilder
[void]$sb.AppendLine("local _, ns = ...")
[void]$sb.AppendLine("")
[void]$sb.AppendLine("-- Generated spell catalog.")
[void]$sb.AppendLine(("-- Source date (UTC): {0}" -f (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss")))
[void]$sb.AppendLine(("-- Sources: {0}" -f ($sourceSummary -join ", ")))
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
