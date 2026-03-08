local _, ns = ...
local U = ns.Utils

ns.SettingsData = ns.SettingsData or {}
local D = ns.SettingsData

local trackedUnits = { "player", "target", "focus", "pet" }
local validUnits = {
  player = true,
  target = true,
  focus = true,
  pet = true,
}

local function safeLower(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower()
end

local function normalizeGroupID(groupID)
  groupID = safeLower(tostring(groupID or ""))
  if groupID == "" then
    return "important_procs"
  end
  return groupID
end

local function normalizeBool(value, fallback)
  if value == nil then
    return fallback == true
  end
  return value == true
end

local validTimerVisual = {
  icon = true,
  bar = true,
  iconbar = true,
}

local function normalizeTimerVisual(value)
  value = safeLower(tostring(value or "icon"))
  if validTimerVisual[value] then
    return value
  end
  return "icon"
end

local validTextAnchors = {
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  CENTER = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

local function normalizeAnchor(anchor, fallback)
  anchor = tostring(anchor or ""):upper()
  if validTextAnchors[anchor] then
    return anchor
  end
  return fallback
end

local function normalizeOffset(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  n = math.floor(n + 0.5)
  if n > 200 then
    n = 200
  end
  if n < -200 then
    n = -200
  end
  return n
end

local function normalizePercent(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  n = math.floor(n + 0.5)
  if n < 0 then
    n = 0
  end
  if n > 100 then
    n = 100
  end
  return n
end

local function normalizeThreshold(value)
  local n = tonumber(value)
  if not n then
    return 0
  end
  n = math.floor(n + 0.5)
  if n < 0 then
    n = 0
  end
  if n > 60 then
    n = 60
  end
  return n
end

local function normalizeDisplayName(text)
  text = U.Trim(tostring(text or ""))
  if text == "" then
    return ""
  end
  if #text > 64 then
    text = text:sub(1, 64)
  end
  return text
end

local function normalizeCustomText(text)
  text = U.Trim(tostring(text or ""))
  if text == "" then
    return ""
  end
  if #text > 120 then
    text = text:sub(1, 120)
  end
  return text
end

local function parseEntryKey(key)
  if type(key) ~= "string" then
    return nil, nil
  end
  local unit, idx = key:match("^([a-z]+):(%d+)$")
  if not validUnits[unit] then
    return nil, nil
  end
  idx = tonumber(idx)
  if not idx or idx < 1 then
    return nil, nil
  end
  return unit, idx
end

function D:GetTrackedUnits()
  return trackedUnits
end

function D:NormalizeUnit(unit)
  unit = safeLower(tostring(unit or "player"))
  if validUnits[unit] then
    return unit
  end
  return "player"
end

function D:EnsureGroup(groupID, displayName)
  groupID = normalizeGroupID(groupID)

  if not ns.db.groups[groupID] then
    local maxOrder = 0
    for _, cfg in pairs(ns.db.groups) do
      maxOrder = math.max(maxOrder, tonumber(cfg.order) or 0)
    end

    ns.db.groups[groupID] = {
      id = groupID,
      name = displayName and tostring(displayName) or (groupID:gsub("_", " "):gsub("^%l", string.upper)),
      order = maxOrder + 1,
      layout = { iconSize = 36, spacing = 4, direction = "RIGHT" },
    }

    ns.db.positions[groupID] = ns.db.positions[groupID] or {
      point = "CENTER",
      relativePoint = "CENTER",
      x = 0,
      y = -72 - ((maxOrder + 1) * 52),
    }
  elseif displayName and displayName ~= "" then
    ns.db.groups[groupID].name = displayName
  end

  return groupID
end

function D:GetGroupOptions()
  local keys = U.KeysSortedByNumberField(ns.db.groups or {}, "order")
  local out = {}
  for i = 1, #keys do
    local key = keys[i]
    local cfg = ns.db.groups[key] or {}
    out[#out + 1] = {
      value = key,
      label = cfg.name or key,
    }
  end
  return out
end

function D:GetUnitOptions()
  return {
    { value = "player", label = "Player" },
    { value = "target", label = "Target" },
    { value = "focus", label = "Focus" },
    { value = "pet", label = "Pet" },
  }
end

function D:ResolveEntry(key)
  local unit, idx = parseEntryKey(key)
  if not unit then
    return nil
  end
  local list = ns.db and ns.db.watchlist and ns.db.watchlist[unit]
  local item = list and list[idx]
  if not item then
    return nil
  end
  return {
    key = key,
    unit = unit,
    index = idx,
    item = item,
    list = list,
  }
end

function D:BuildEntryLabel(unit, item, index)
  local auraName = normalizeDisplayName(item.displayName)
  local spellName = ns.AuraAPI:GetSpellName(item.spellID) or ("Spell " .. tostring(item.spellID))
  local group = ns.db.groups[item.groupID]
  local groupName = (group and group.name) or item.groupID or "Group"
  if auraName ~= "" then
    return ("%s | %s [%s] (%d) | %s"):format(unit:gsub("^%l", string.upper), auraName, spellName, item.spellID or 0, groupName)
  end
  return ("%s | %s (%d) | %s"):format(unit:gsub("^%l", string.upper), spellName, item.spellID or 0, groupName)
end

function D:ListEntries(filterText)
  local rows = {}
  local filter = safeLower(U.Trim(filterText or ""))

  -- Flatten watchlist tables into a single UI-friendly list with stable keys.
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for idx, item in ipairs(list) do
      local label = self:BuildEntryLabel(unit, item, idx)
      local haystack = safeLower(label .. " " .. tostring(item.spellID or ""))
      if filter == "" or haystack:find(filter, 1, true) then
        rows[#rows + 1] = {
          key = unit .. ":" .. idx,
          unit = unit,
          index = idx,
          item = item,
          label = label,
        }
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.unit == b.unit then
      return a.index < b.index
    end
    return a.unit < b.unit
  end)

  return rows
end

function D:BuildEditableModel(entry)
  if not entry or not entry.item then
    return nil
  end
  local item = entry.item
  return {
    key = entry.key,
    unit = entry.unit,
    spellID = tonumber(item.spellID) or 0,
    spellName = ns.AuraAPI:GetSpellName(item.spellID) or "",
    groupID = item.groupID or "important_procs",
    onlyMine = item.onlyMine == true,
    alert = item.alert ~= false,
    iconMode = item.iconMode or "spell",
    displayName = item.displayName or "",
    customTexture = item.customTexture or "",
    barTexture = item.barTexture or "",
    customText = item.customText or "",
    timerVisual = item.timerVisual or "icon",
    timerAnchor = item.timerAnchor or "BOTTOM",
    timerOffsetX = tonumber(item.timerOffsetX) or 0,
    timerOffsetY = tonumber(item.timerOffsetY) or -1,
    customTextAnchor = item.customTextAnchor or "TOP",
    customTextOffsetX = tonumber(item.customTextOffsetX) or 0,
    customTextOffsetY = tonumber(item.customTextOffsetY) or 2,
    resourceConditionEnabled = item.resourceConditionEnabled == true,
    resourceMinPct = tonumber(item.resourceMinPct) or 0,
    resourceMaxPct = tonumber(item.resourceMaxPct) or 100,
    lowTimeThreshold = tonumber(item.lowTimeThreshold) or 0,
    soundOnGain = item.soundOnGain or "default",
    soundOnLow = item.soundOnLow or "default",
    soundOnExpire = item.soundOnExpire or "default",
  }
end

function D:BuildDefaultCreateModel()
  return {
    spellInput = "",
    unit = "player",
    groupID = "important_procs",
    onlyMine = true,
    alert = true,
    iconMode = "spell",
    displayName = "",
    customTexture = "",
    barTexture = "",
    customText = "",
    timerVisual = "icon",
    timerAnchor = "BOTTOM",
    timerOffsetX = 0,
    timerOffsetY = -1,
    customTextAnchor = "TOP",
    customTextOffsetX = 0,
    customTextOffsetY = 2,
    resourceConditionEnabled = false,
    resourceMinPct = 0,
    resourceMaxPct = 100,
    lowTimeThreshold = 0,
    soundOnGain = "default",
    soundOnLow = "default",
    soundOnExpire = "default",
  }
end

function D:BuildWatchItemFromModel(model)
  local spellID = U.ResolveSpellID(model.spellInput or model.spellID)
  if not spellID and ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
    spellID = ns.SpellCatalog:ResolveNameToSpellID(model.spellInput or model.spellID)
  end
  if not spellID then
    return nil, "Spell non trovato. Usa SpellID o nome corretto."
  end

  local groupID = self:EnsureGroup(model.groupID)
  local iconMode = (model.iconMode == "custom") and "custom" or "spell"
  local customTexture = ""
  if iconMode == "custom" then
    customTexture = ns.AuraAPI:ResolveCustomTexturePath(model.customTexture)
  end
  local barTexture = ns.AuraAPI:ResolveBarTexturePath(model.barTexture)

  local resourceMin = normalizePercent(model.resourceMinPct, 0)
  local resourceMax = normalizePercent(model.resourceMaxPct, 100)
  local lowTimeThreshold = normalizeThreshold(model.lowTimeThreshold)
  if resourceMax < resourceMin then
    resourceMin, resourceMax = resourceMax, resourceMin
  end

  return {
    spellID = spellID,
    groupID = groupID,
    onlyMine = normalizeBool(model.onlyMine, true),
    alert = normalizeBool(model.alert, true),
    displayName = normalizeDisplayName(model.displayName),
    customText = normalizeCustomText(model.customText),
    timerVisual = normalizeTimerVisual(model.timerVisual),
    timerAnchor = normalizeAnchor(model.timerAnchor, "BOTTOM"),
    timerOffsetX = normalizeOffset(model.timerOffsetX, 0),
    timerOffsetY = normalizeOffset(model.timerOffsetY, -1),
    customTextAnchor = normalizeAnchor(model.customTextAnchor, "TOP"),
    customTextOffsetX = normalizeOffset(model.customTextOffsetX, 0),
    customTextOffsetY = normalizeOffset(model.customTextOffsetY, 2),
    resourceConditionEnabled = normalizeBool(model.resourceConditionEnabled, false),
    resourceMinPct = resourceMin,
    resourceMaxPct = resourceMax,
    lowTimeThreshold = lowTimeThreshold,
    soundOnGain = ns.SoundManager:NormalizeToken(model.soundOnGain),
    soundOnLow = ns.SoundManager:NormalizeToken(model.soundOnLow),
    soundOnExpire = ns.SoundManager:NormalizeToken(model.soundOnExpire),
    iconMode = iconMode,
    customTexture = customTexture,
    barTexture = barTexture,
  }
end

function D:AddEntry(model)
  local unit = self:NormalizeUnit(model.unit)
  local item, err = self:BuildWatchItemFromModel(model)
  if not item then
    return nil, err
  end

  local ok, addErr = ns.Registry:AddWatch(unit, item)
  if not ok then
    return nil, addErr or "Impossibile aggiungere aura."
  end

  ns:RebuildWatchIndex()
  ns.EventRouter:RefreshAll()
  ns.Debug:Logf("UI AddEntry unit=%s spellID=%d", unit, item.spellID)

  local list = ns.db.watchlist[unit] or {}
  return unit .. ":" .. #list
end

function D:UpdateEntry(key, model)
  local entry = self:ResolveEntry(key)
  if not entry then
    return nil, "Aura selezionata non valida."
  end

  local item, err = self:BuildWatchItemFromModel(model)
  if not item then
    return nil, err
  end

  local fromUnit = entry.unit
  local toUnit = self:NormalizeUnit(model.unit)
  local removedIndex = entry.index

  if fromUnit == toUnit then
    entry.list[removedIndex] = item
    ns:RebuildWatchIndex()
    ns.EventRouter:RefreshAll()
    ns.Debug:Logf("UI UpdateEntry key=%s unit=%s spellID=%d", tostring(key), tostring(toUnit), item.spellID)
    return key
  end

  -- If unit changes, we move the item across lists and return the new key.
  table.remove(entry.list, removedIndex)
  ns.db.watchlist[toUnit][#ns.db.watchlist[toUnit] + 1] = item

  ns:RebuildWatchIndex()
  ns.EventRouter:RefreshAll()
  ns.Debug:Logf("UI MoveEntry key=%s %s->%s spellID=%d", tostring(key), tostring(fromUnit), tostring(toUnit), item.spellID)
  return toUnit .. ":" .. #ns.db.watchlist[toUnit]
end

function D:DeleteEntry(key)
  local entry = self:ResolveEntry(key)
  if not entry then
    return 0
  end
  table.remove(entry.list, entry.index)
  ns:RebuildWatchIndex()
  ns.EventRouter:RefreshAll()
  ns.Debug:Logf("UI DeleteEntry key=%s", tostring(key))
  return 1
end
