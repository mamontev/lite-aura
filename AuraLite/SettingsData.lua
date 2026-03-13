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
  groupID = groupID:gsub("[^%w_]+", "_")
  groupID = groupID:gsub("_+", "_")
  groupID = groupID:gsub("^_+", "")
  groupID = groupID:gsub("_+$", "")
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

local function normalizeSize(value, fallback, minValue, maxValue)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  n = math.floor(n + 0.5)
  if n < (minValue or 4) then
    n = minValue or 4
  end
  if n > (maxValue or 512) then
    n = maxValue or 512
  end
  return n
end

local function normalizeColorCSV(value)
  local text = U.Trim(tostring(value or ""))
  if text == "" then
    return ""
  end
  local parts = {}
  for token in text:gmatch("[^,%s;]+") do
    local n = tonumber(token)
    if not n then
      return ""
    end
    if n < 0 then
      n = 0
    elseif n > 1 then
      n = 1
    end
    parts[#parts + 1] = string.format("%.2f", n)
    if #parts == 3 then
      break
    end
  end
  if #parts ~= 3 then
    return ""
  end
  return table.concat(parts, ",")
end

local function normalizeBarSide(value)
  value = safeLower(tostring(value or "right"))
  if value == "left" then
    return "left"
  end
  return "right"
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

local function spellIDListsEqual(a, b)
  local left = normalizeSpellIDList(a)
  local right = normalizeSpellIDList(b)
  if #left ~= #right then
    return false
  end
  for i = 1, #left do
    if left[i] ~= right[i] then
      return false
    end
  end
  return true
end

local function normalizeTrackingMode(value, unit)
  local mode = tostring(value or ""):lower()
  unit = tostring(unit or "player"):lower()
  if unit == "target" and mode == "estimated" then
    return "estimated"
  end
  return "confirmed"
end

local function normalizeInstanceUID(text)
  text = U.Trim(tostring(text or ""))
  if text == "" then
    return ""
  end
  text = text:gsub("[^%w_%-%.:]", "")
  if #text > 64 then
    text = text:sub(1, 64)
  end
  return text
end

local function buildInstanceUID(spellID)
  local nowMs = math.floor((GetTime() or 0) * 1000)
  return string.format("a%d_%d_%04d", tonumber(spellID) or 0, nowMs, math.random(0, 9999))
end
local function normalizeClassToken(value)
  local token = safeLower(tostring(value or "")):upper()
  if token == "" or token == "ANY" or token == "*" then
    return ""
  end
  if token:match("^[A-Z_]+$") then
    return token
  end
  return ""
end

local fallbackClassSpecCatalog = {
  { token = "WARRIOR", label = "Warrior", specs = { { id = 71, label = "Arms" }, { id = 72, label = "Fury" }, { id = 73, label = "Protection" } } },
  { token = "PALADIN", label = "Paladin", specs = { { id = 65, label = "Holy" }, { id = 66, label = "Protection" }, { id = 70, label = "Retribution" } } },
  { token = "HUNTER", label = "Hunter", specs = { { id = 253, label = "Beast Mastery" }, { id = 254, label = "Marksmanship" }, { id = 255, label = "Survival" } } },
  { token = "ROGUE", label = "Rogue", specs = { { id = 259, label = "Assassination" }, { id = 260, label = "Outlaw" }, { id = 261, label = "Subtlety" } } },
  { token = "PRIEST", label = "Priest", specs = { { id = 256, label = "Discipline" }, { id = 257, label = "Holy" }, { id = 258, label = "Shadow" } } },
  { token = "DEATHKNIGHT", label = "Death Knight", specs = { { id = 250, label = "Blood" }, { id = 251, label = "Frost" }, { id = 252, label = "Unholy" } } },
  { token = "SHAMAN", label = "Shaman", specs = { { id = 262, label = "Elemental" }, { id = 263, label = "Enhancement" }, { id = 264, label = "Restoration" } } },
  { token = "MAGE", label = "Mage", specs = { { id = 62, label = "Arcane" }, { id = 63, label = "Fire" }, { id = 64, label = "Frost" } } },
  { token = "WARLOCK", label = "Warlock", specs = { { id = 265, label = "Affliction" }, { id = 266, label = "Demonology" }, { id = 267, label = "Destruction" } } },
  { token = "MONK", label = "Monk", specs = { { id = 268, label = "Brewmaster" }, { id = 269, label = "Windwalker" }, { id = 270, label = "Mistweaver" } } },
  { token = "DRUID", label = "Druid", specs = { { id = 102, label = "Balance" }, { id = 103, label = "Feral" }, { id = 104, label = "Guardian" }, { id = 105, label = "Restoration" } } },
  { token = "DEMONHUNTER", label = "Demon Hunter", specs = { { id = 577, label = "Havoc" }, { id = 581, label = "Vengeance" } } },
  { token = "EVOKER", label = "Evoker", specs = { { id = 1467, label = "Devastation" }, { id = 1468, label = "Preservation" }, { id = 1473, label = "Augmentation" } } },
}
local classSpecCatalogCache = nil

local function cloneClassSpecCatalog(src)
  local out = {}
  for i = 1, #(src or {}) do
    local cls = src[i]
    local specs = {}
    for j = 1, #((cls and cls.specs) or {}) do
      local s = cls.specs[j]
      specs[#specs + 1] = {
        id = tonumber(s.id),
        label = tostring(s.label or ""),
      }
    end
    out[#out + 1] = {
      token = tostring((cls and cls.token) or ""),
      label = tostring((cls and cls.label) or ""),
      specs = specs,
    }
  end
  return out
end

local function buildClassSpecCatalog()
  if not GetNumClasses or not GetClassInfo or not GetNumSpecializationsForClassID or not GetSpecializationInfoForClassID then
    return cloneClassSpecCatalog(fallbackClassSpecCatalog)
  end

  local dynamic = {}
  local numClasses = tonumber(GetNumClasses()) or 0
  for classID = 1, numClasses do
    local className, classToken = GetClassInfo(classID)
    classToken = tostring(classToken or ""):upper()
    if classToken ~= "" then
      local row = {
        token = classToken,
        label = tostring(className or classToken),
        specs = {},
      }
      local specCount = tonumber(GetNumSpecializationsForClassID(classID)) or 0
      for specIndex = 1, specCount do
        local specID, specName = GetSpecializationInfoForClassID(classID, specIndex)
        specID = tonumber(specID)
        if specID and specID > 0 then
          row.specs[#row.specs + 1] = {
            id = specID,
            label = tostring(specName or ("Spec " .. tostring(specID))),
          }
        end
      end
      if #row.specs > 0 then
        dynamic[#dynamic + 1] = row
      end
    end
  end

  if #dynamic > 0 then
    table.sort(dynamic, function(a, b)
      return tostring(a.label) < tostring(b.label)
    end)
    return dynamic
  end

  return cloneClassSpecCatalog(fallbackClassSpecCatalog)
end

local function getClassSpecCatalog()
  if not classSpecCatalogCache then
    classSpecCatalogCache = buildClassSpecCatalog()
  end
  return classSpecCatalogCache
end
local function normalizeSpecIDList(input)
  local out = {}
  local seen = {}
  if type(input) == "table" then
    for i = 1, #input do
      local id = tonumber(input[i])
      if id and id > 0 and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  else
    local text = tostring(input or "")
    for token in text:gmatch("[^,%s;]+") do
      local id = tonumber(token)
      if id and id > 0 and not seen[id] then
        seen[id] = true
        out[#out + 1] = id
      end
    end
  end
  return out
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
  if groupID == "" then
    return ""
  end

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
  local out = {
    { value = "", label = "No Group" },
  }
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

function D:GetLoadClassOptions()
  local classSpecCatalog = getClassSpecCatalog()
  local out = {
    { value = "", label = "Any Class" },
  }
  for i = 1, #classSpecCatalog do
    local cls = classSpecCatalog[i]
    out[#out + 1] = { value = cls.token, label = cls.label }
  end
  return out
end

function D:SuggestGroupID(displayName)
  local base = normalizeGroupID(displayName)
  if base == "" then
    base = "new_group"
  end
  if not ns.db.groups[base] then
    return base
  end
  local suffix = 2
  while ns.db.groups[base .. "_" .. suffix] do
    suffix = suffix + 1
  end
  return base .. "_" .. suffix
end

function D:GetLoadSpecMenuOptions(classToken)
  local classSpecCatalog = getClassSpecCatalog()
  local token = normalizeClassToken(classToken)
  local out = {
    { value = "", label = "Any Spec" },
  }
  for i = 1, #classSpecCatalog do
    local cls = classSpecCatalog[i]
    if token == "" or token == cls.token then
      local submenu = {}
      for j = 1, #(cls.specs or {}) do
        local spec = cls.specs[j]
        submenu[#submenu + 1] = {
          value = tonumber(spec.id),
          label = tostring(spec.label),
        }
      end
      if #submenu > 0 then
        out[#out + 1] = {
          label = cls.label,
          menuList = submenu,
        }
      end
    end
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
  local groupName = (group and group.name) or item.groupID or ""
  if auraName ~= "" then
    if groupName ~= "" then
      return ("%s | %s [%s] (%d) | %s"):format(unit:gsub("^%l", string.upper), auraName, spellName, item.spellID or 0, groupName)
    end
    return ("%s | %s [%s] (%d)"):format(unit:gsub("^%l", string.upper), auraName, spellName, item.spellID or 0)
  end
  if groupName ~= "" then
    return ("%s | %s (%d) | %s"):format(unit:gsub("^%l", string.upper), spellName, item.spellID or 0, groupName)
  end
  return ("%s | %s (%d)"):format(unit:gsub("^%l", string.upper), spellName, item.spellID or 0)
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
    trackingMode = normalizeTrackingMode(item.trackingMode, entry.unit),
    castSpellIDs = normalizeSpellIDList(item.castSpellIDs),
    estimatedDuration = normalizeDuration(item.estimatedDuration, 8),
    spellID = tonumber(item.spellID) or 0,
    spellName = ns.AuraAPI:GetSpellName(item.spellID) or "",
    instanceUID = normalizeInstanceUID(item.instanceUID),
    groupID = item.groupID or "",
    layoutGroupEnabled = item.layoutGroupEnabled == true and normalizeGroupID(item.groupID) ~= "",
    loadClassToken = normalizeClassToken(item.loadClassToken),
    loadSpecIDs = normalizeSpecIDList(item.loadSpecIDs),
    inCombatOnly = item.inCombatOnly == true,
    onlyMine = item.onlyMine == true,
    alert = item.alert ~= false,
    iconMode = item.iconMode or "spell",
    displayName = item.displayName or "",
    customTexture = item.customTexture or "",
    barTexture = item.barTexture or "",
    customText = item.customText or "",
    timerVisual = item.timerVisual or "icon",
    iconWidth = tonumber(item.iconWidth) or 36,
    iconHeight = tonumber(item.iconHeight) or 36,
    barWidth = tonumber(item.barWidth) or 94,
    barHeight = tonumber(item.barHeight) or 16,
    showTimerText = item.showTimerText ~= false,
    barColor = tostring(item.barColor or ""),
    barSide = normalizeBarSide(item.barSide),
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
    trackingMode = "confirmed",
    castSpellIDs = {},
    estimatedDuration = 8,
    instanceUID = "",
    groupID = "",
    layoutGroupEnabled = false,
    loadClassToken = "",
    loadSpecIDs = {},
    inCombatOnly = false,
    onlyMine = true,
    alert = true,
    iconMode = "spell",
    displayName = "",
    customTexture = "",
    barTexture = "",
    customText = "",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
    barColor = "",
    barSide = "right",
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

  local groupID = normalizeGroupID(model.groupID)
  local instanceUID = normalizeInstanceUID(model.instanceUID)
  if instanceUID == "" then
    instanceUID = buildInstanceUID(spellID)
  end
  local layoutGroupEnabled = normalizeBool(model.layoutGroupEnabled, false) and groupID ~= ""
  if layoutGroupEnabled and groupID ~= "" then
    groupID = self:EnsureGroup(groupID)
  end
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
    instanceUID = instanceUID,
    groupID = groupID,
    trackingMode = normalizeTrackingMode(model.trackingMode, model.unit),
    castSpellIDs = normalizeSpellIDList(model.castSpellIDs),
    estimatedDuration = normalizeDuration(model.estimatedDuration, 8),
    layoutGroupEnabled = layoutGroupEnabled,
    loadClassToken = normalizeClassToken(model.loadClassToken),
    loadSpecIDs = normalizeSpecIDList(model.loadSpecIDs),
    inCombatOnly = normalizeBool(model.inCombatOnly, false),
    onlyMine = normalizeBool(model.onlyMine, true),
    alert = normalizeBool(model.alert, true),
    displayName = normalizeDisplayName(model.displayName),
    customText = normalizeCustomText(model.customText),
    timerVisual = normalizeTimerVisual(model.timerVisual),
    iconWidth = normalizeSize(model.iconWidth, 36, 12, 256),
    iconHeight = normalizeSize(model.iconHeight, 36, 12, 256),
    barWidth = normalizeSize(model.barWidth, 94, 60, 512),
    barHeight = normalizeSize(model.barHeight, 16, 6, 128),
    showTimerText = normalizeBool(model.showTimerText, true),
    barColor = normalizeColorCSV(model.barColor),
    barSide = normalizeBarSide(model.barSide),
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

function D:DeleteEntriesByInstanceUID(instanceUID, spellID)
  instanceUID = normalizeInstanceUID(instanceUID)
  spellID = tonumber(spellID)
  if instanceUID == "" then
    return 0
  end

  local removed = 0
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = #list, 1, -1 do
      local item = list[i]
      local sameInstance = normalizeInstanceUID(item and item.instanceUID) == instanceUID
      local sameSpell = (not spellID) or (tonumber(item and item.spellID) == spellID)
      if sameInstance and sameSpell then
        table.remove(list, i)
        removed = removed + 1
      end
    end
  end

  if removed > 0 then
    ns:RebuildWatchIndex()
    ns.EventRouter:RefreshAll()
    ns.Debug:Logf("UI DeleteEntriesByInstanceUID instanceUID=%s spellID=%s removed=%d", tostring(instanceUID), tostring(spellID or "nil"), removed)
  end

  return removed
end

function D:DeleteMatchingEntries(unit, model)
  unit = self:NormalizeUnit(unit)
  model = model or {}
  local list = ns.db.watchlist[unit] or {}
  local targetSpellID = tonumber(model.spellID or model.spellInput)
  if not targetSpellID or targetSpellID <= 0 then
    return 0
  end

  local targetDisplayName = normalizeDisplayName(model.displayName or model.name)
  local targetGroupID = normalizeGroupID(model.groupID or model.group)
  local targetTrackingMode = normalizeTrackingMode(model.trackingMode, unit)
  local targetCastSpellIDs = normalizeSpellIDList(model.castSpellIDs)

  local removed = 0
  for i = #list, 1, -1 do
    local item = list[i]
    local sameSpell = tonumber(item and item.spellID) == targetSpellID
    local sameName = normalizeDisplayName(item and item.displayName) == targetDisplayName
    local sameGroup = normalizeGroupID(item and item.groupID) == targetGroupID
    local sameTracking = normalizeTrackingMode(item and item.trackingMode, unit) == targetTrackingMode
    local sameCastList = spellIDListsEqual(item and item.castSpellIDs, targetCastSpellIDs)

    if sameSpell and sameGroup and sameTracking and (sameName or targetDisplayName == "") and sameCastList then
      table.remove(list, i)
      removed = removed + 1
    end
  end

  if removed > 0 then
    ns:RebuildWatchIndex()
    ns.EventRouter:RefreshAll()
    ns.Debug:Logf("UI DeleteMatchingEntries unit=%s spellID=%s removed=%d", tostring(unit), tostring(targetSpellID), removed)
  end

  return removed
end

function D:CleanupOrphanAuraGroups()
  local referenced = {}
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = 1, #list do
      local groupID = normalizeGroupID(list[i] and list[i].groupID)
      if groupID ~= "" then
        referenced[groupID] = true
      end
    end
  end

  local removed = 0
  for groupID, group in pairs(ns.db.groups or {}) do
    local autoGenerated = type(groupID) == "string" and groupID:find("^aura_", 1) == 1
    if autoGenerated and not referenced[groupID] then
      ns.db.groups[groupID] = nil
      if type(ns.db.positions) == "table" then
        ns.db.positions[groupID] = nil
      end
      removed = removed + 1
    end
  end

  if removed > 0 and ns.Debug and ns.Debug.Logf then
    ns.Debug:Logf("UI CleanupOrphanAuraGroups removed=%d", removed)
  end

  return removed
end







