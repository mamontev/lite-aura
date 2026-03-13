local _, ns = ...

ns.Registry = ns.Registry or {}
local R = ns.Registry

local function trim(s)
  if type(s) ~= "string" then
    return ""
  end
  return s:gsub("^%s+", ""):gsub("%s+$", "")
end

local validAnchors = {
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

local function normalizeAnchor(value, fallback)
  local anchor = tostring(value or ""):upper()
  if validAnchors[anchor] then
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

local function normalizeDuration(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  if n < 1 then
    n = 1
  end
  if n > 600 then
    n = 600
  end
  return math.floor((n * 10) + 0.5) / 10
end

local function normalizeSpellIDList(value)
  local out = {}
  local seen = {}
  if type(value) == "table" then
    for i = 1, #value do
      local n = tonumber(value[i])
      if n and n > 0 and not seen[n] then
        seen[n] = true
        out[#out + 1] = n
      end
    end
    return out
  end

  local text = tostring(value or "")
  for token in text:gmatch("[^,%s;]+") do
    local n = tonumber(token)
    if n and n > 0 and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  return out
end

local function normalizeTrackingMode(value, unit)
  local mode = tostring(value or ""):lower()
  if tostring(unit or "") == "target" and mode == "estimated" then
    return "estimated"
  end
  return "confirmed"
end

local function normalizeTimerVisual(value)
  value = tostring(value or "icon"):lower()
  if value == "bar" or value == "iconbar" then
    return "bar"
  end
  return "icon"
end

local trackedUnits = {
  player = true,
  target = true,
  focus = true,
  pet = true,
}

function R:IsValidUnit(unit)
  return trackedUnits[unit] == true
end

function R:NormalizeWatchItem(item, unit)
  if type(item) ~= "table" then
    return nil
  end

  local spellID = tonumber(item.spellID)
  local groupID = tostring(item.groupID or "important_procs")
  if not spellID then
    return nil
  end

  local minPct = normalizePercent(item.resourceMinPct, 0)
  local maxPct = normalizePercent(item.resourceMaxPct, 100)
  if maxPct < minPct then
    minPct, maxPct = maxPct, minPct
  end

  return {
    spellID = spellID,
    groupID = groupID,
    trackingMode = normalizeTrackingMode(item.trackingMode, unit),
    castSpellIDs = normalizeSpellIDList(item.castSpellIDs),
    estimatedDuration = normalizeDuration(item.estimatedDuration, 8),
    inCombatOnly = item.inCombatOnly == true,
    onlyMine = item.onlyMine == true,
    alert = item.alert ~= false,
    displayName = trim(item.displayName),
    customText = trim(item.customText),
    timerVisual = normalizeTimerVisual(item.timerVisual),
    timerAnchor = normalizeAnchor(item.timerAnchor, "BOTTOM"),
    timerOffsetX = normalizeOffset(item.timerOffsetX, 0),
    timerOffsetY = normalizeOffset(item.timerOffsetY, -1),
    customTextAnchor = normalizeAnchor(item.customTextAnchor, "TOP"),
    customTextOffsetX = normalizeOffset(item.customTextOffsetX, 0),
    customTextOffsetY = normalizeOffset(item.customTextOffsetY, 2),
    resourceConditionEnabled = item.resourceConditionEnabled == true,
    resourceMinPct = minPct,
    resourceMaxPct = maxPct,
    lowTimeThreshold = normalizeThreshold(item.lowTimeThreshold),
    soundOnGain = ns.SoundManager and ns.SoundManager:NormalizeToken(item.soundOnGain) or "default",
    soundOnLow = ns.SoundManager and ns.SoundManager:NormalizeToken(item.soundOnLow) or "default",
    soundOnExpire = ns.SoundManager and ns.SoundManager:NormalizeToken(item.soundOnExpire) or "default",
    iconMode = (item.iconMode == "custom") and "custom" or "spell",
    customTexture = ns.AuraAPI and ns.AuraAPI:ResolveCustomTexturePath(trim(item.customTexture)) or trim(item.customTexture),
    barTexture = ns.AuraAPI and ns.AuraAPI:ResolveBarTexturePath(trim(item.barTexture)) or trim(item.barTexture),
  }
end

function R:EnsureLists(profile)
  profile.watchlist = type(profile.watchlist) == "table" and profile.watchlist or {}
  for unit in pairs(trackedUnits) do
    profile.watchlist[unit] = type(profile.watchlist[unit]) == "table" and profile.watchlist[unit] or {}
  end
end

function R:Rebuild(profile)
  self.index = {}
  self.byUnitGroup = {}
  self.hasResourceConditions = false
  self:EnsureLists(profile)

  for unit, list in pairs(profile.watchlist) do
    self.index[unit] = self.index[unit] or {}
    self.byUnitGroup[unit] = self.byUnitGroup[unit] or {}

    for i = #list, 1, -1 do
      local normalized = self:NormalizeWatchItem(list[i], unit)
      if not normalized then
        table.remove(list, i)
      else
        list[i] = normalized
      end
    end

    for _, item in ipairs(list) do
      self.index[unit][item.spellID] = true
      self.byUnitGroup[unit][item.groupID] = self.byUnitGroup[unit][item.groupID] or {}
      self.byUnitGroup[unit][item.groupID][#self.byUnitGroup[unit][item.groupID] + 1] = item
      if item.resourceConditionEnabled == true then
        self.hasResourceConditions = true
      end
    end
  end
end

function R:HasResourceConditions()
  return self.hasResourceConditions == true
end

function R:UnitEnabled(unit)
  return ns.db and ns.db.units and ns.db.units[unit] == true
end

function R:TouchesWatchlist(unit, updateInfo)
  if not self.index or not self.index[unit] then
    return true
  end

  if not updateInfo or updateInfo.isFullUpdate then
    return true
  end

  local watched = self.index[unit]

  if updateInfo.addedAuras then
    for _, aura in ipairs(updateInfo.addedAuras) do
      local spellID = ns.AuraAPI:GetAuraSpellID(aura)
      if spellID and watched[spellID] then
        return true
      end
    end
  end

  if updateInfo.updatedAuraInstanceIDs then
    for _, auraInstanceID in ipairs(updateInfo.updatedAuraInstanceIDs) do
      if not ns.AuraAPI:IsSafeNumber(auraInstanceID) then
        -- Secret aura instance IDs cannot be resolved safely; refresh conservatively.
        return true
      end
      local aura = ns.AuraAPI:GetAuraByInstanceID(unit, auraInstanceID)
      local spellID = ns.AuraAPI:GetAuraSpellID(aura)
      if spellID and watched[spellID] then
        return true
      end
    end
  end

  if updateInfo.removedAuraInstanceIDs and #updateInfo.removedAuraInstanceIDs > 0 then
    return true
  end

  return false
end

function R:AddWatch(unit, item)
  if not self:IsValidUnit(unit) then
    return nil, "invalid unit"
  end
  local normalized = self:NormalizeWatchItem(item, unit)
  if not normalized then
    return nil, "invalid watch item"
  end

  ns.db.watchlist[unit][#ns.db.watchlist[unit] + 1] = normalized
  self:Rebuild(ns.db)
  ns.Debug:Logf("AddWatch unit=%s spellID=%d group=%s", unit, normalized.spellID, tostring(normalized.groupID))
  return normalized
end

function R:RemoveWatch(unit, spellID)
  if not self:IsValidUnit(unit) then
    return 0
  end
  spellID = tonumber(spellID)
  if not spellID then
    return 0
  end

  local list = ns.db.watchlist[unit]
  local removed = 0
  for i = #list, 1, -1 do
    if tonumber(list[i].spellID) == spellID then
      table.remove(list, i)
      removed = removed + 1
    end
  end

  if removed > 0 then
    self:Rebuild(ns.db)
    ns.Debug:Logf("RemoveWatch unit=%s spellID=%d removed=%d", unit, spellID, removed)
  end
  return removed
end
