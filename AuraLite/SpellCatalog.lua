local _, ns = ...
local U = ns.Utils

ns.SpellCatalog = ns.SpellCatalog or {}
local C = ns.SpellCatalog

C._normalized = C._normalized or nil
C._nameToID = C._nameToID or {}

local function normalizeText(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function addUnique(out, seen, row)
  if not row or not row.id then
    return
  end
  local key = tostring(row.id) .. "|" .. normalizeText(row.name or "")
  if seen[key] then
    return
  end
  seen[key] = true
  out[#out + 1] = row
end

local function isUsableSpellName(normalized)
  if normalized == "" then
    return false
  end
  if normalized:find("dnt", 1, true) then
    return false
  end
  if normalized:find("dummy", 1, true) then
    return false
  end
  if normalized:find("test", 1, true) then
    return false
  end
  if normalized:find("unused", 1, true) then
    return false
  end
  return true
end

function C:BuildStaticIndex()
  if self._normalized then
    return
  end

  local rows = {}
  local nameToID = {}
  for _, row in ipairs(ns.SpellCatalogData or {}) do
    local id = tonumber(row.id)
    local name = tostring(row.name or "")
    if id and name ~= "" then
      local normalized = normalizeText(name)
      if isUsableSpellName(normalized) then
      rows[#rows + 1] = {
        id = id,
        name = name,
        normalized = normalized,
        popularity = tonumber(row.popularity) or 0,
      }
      if normalized ~= "" and not nameToID[normalized] then
        nameToID[normalized] = id
      end
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.popularity ~= b.popularity then
      return a.popularity > b.popularity
    end
    if a.name == b.name then
      return a.id < b.id
    end
    return a.name < b.name
  end)

  self._normalized = rows
  self._nameToID = nameToID
end

function C:GatherProfileSpells()
  local out = {}
  local seen = {}
  if not ns.db or not ns.db.watchlist then
    return out
  end

  for unit, list in pairs(ns.db.watchlist) do
    for _, item in ipairs(list) do
      local spellID = tonumber(item.spellID)
      if spellID then
        local name = ns.AuraAPI:GetSpellName(spellID) or ("Spell " .. spellID)
        addUnique(out, seen, {
          id = spellID,
          name = name,
          normalized = normalizeText(name),
          popularity = 999999,
          unit = unit,
          fromProfile = true,
        })
      end
    end
  end

  return out
end

function C:ResolveNameToSpellID(name)
  self:BuildStaticIndex()
  local n = normalizeText(name)
  if n == "" then
    return nil
  end
  return self._nameToID[n]
end

function C:Search(query, maxCount)
  self:BuildStaticIndex()
  maxCount = tonumber(maxCount) or 8
  if maxCount < 1 then
    maxCount = 1
  end
  if maxCount > 30 then
    maxCount = 30
  end

  local text = U.Trim(query or "")
  local normalized = normalizeText(text)
  if normalized == "" then
    return {}
  end

  local isNumeric = tonumber(normalized) ~= nil
  local out = {}
  local seen = {}

  local dynamic = self:GatherProfileSpells()
  for i = 1, #dynamic do
    local row = dynamic[i]
    local idMatch = tostring(row.id):find(normalized, 1, true) ~= nil
    local nameMatch = row.normalized:find(normalized, 1, true) ~= nil
    if (isNumeric and idMatch) or (not isNumeric and nameMatch) then
      addUnique(out, seen, row)
      if #out >= maxCount then
        return out
      end
    end
  end

  if isNumeric then
    local exactID = tonumber(normalized)
    if exactID then
      local name = ns.AuraAPI:GetSpellName(exactID)
      if name then
        addUnique(out, seen, {
          id = exactID,
          name = name,
          normalized = normalizeText(name),
          popularity = 1000000,
        })
      end
    end
  end

  for i = 1, #self._normalized do
    local row = self._normalized[i]
    local idMatch = tostring(row.id):find(normalized, 1, true) ~= nil
    local nameMatch = row.normalized:find(normalized, 1, true) ~= nil
    if (isNumeric and idMatch) or (not isNumeric and nameMatch) then
      addUnique(out, seen, row)
      if #out >= maxCount then
        break
      end
    end
  end

  return out
end
