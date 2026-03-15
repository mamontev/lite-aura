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

local function cloneSavedPosition(pos)
  if type(pos) ~= "table" then
    return nil
  end
  return {
    point = tostring(pos.point or "CENTER"),
    relativePoint = tostring(pos.relativePoint or "CENTER"),
    x = tonumber(pos.x) or 0,
    y = tonumber(pos.y) or 0,
  }
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

local function normalizeGroupDirection(value)
  value = tostring(value or "RIGHT"):upper()
  if value == "LEFT" or value == "UP" or value == "DOWN" then
    return value
  end
  return "RIGHT"
end

local function normalizeGroupSort(value)
  value = safeLower(tostring(value or "list"))
  if value == "name" or value == "spell" or value == "manual" then
    return value
  end
  return "list"
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

local fallbackInstanceSeq = 1

local function encodeBase36(value)
  value = math.floor(math.max(tonumber(value) or 0, 0))
  if value == 0 then
    return "0"
  end
  local digits = "0123456789abcdefghijklmnopqrstuvwxyz"
  local out = {}
  while value > 0 do
    local index = (value % 36) + 1
    out[#out + 1] = digits:sub(index, index)
    value = math.floor(value / 36)
  end
  local text = ""
  for i = #out, 1, -1 do
    text = text .. out[i]
  end
  return text
end

local function decodeBase36(text)
  text = safeLower(tostring(text or ""))
  if text == "" then
    return nil
  end
  local value = 0
  for i = 1, #text do
    local byte = text:byte(i)
    local digit
    if byte >= 48 and byte <= 57 then
      digit = byte - 48
    elseif byte >= 97 and byte <= 122 then
      digit = byte - 87
    else
      return nil
    end
    value = (value * 36) + digit
  end
  return value
end

local function extractInstanceSequence(instanceUID)
  local seqToken = tostring(instanceUID or ""):match("^a%d+_s([0-9a-z]+)$")
  if not seqToken then
    return nil
  end
  return decodeBase36(seqToken)
end

local function ensureInstanceSequenceState()
  if not ns.db then
    return nil
  end
  local current = tonumber(ns.db.nextInstanceSeq)
  if current and current >= 1 then
    current = math.floor(current)
  else
    current = 1
  end

  local maxSeq = 0
  local watchlist = ns.db.watchlist or {}
  for _, unit in ipairs(trackedUnits) do
    local list = watchlist[unit] or {}
    for i = 1, #list do
      local item = list[i]
      local seq = extractInstanceSequence(item and item.instanceUID)
      if seq and seq > maxSeq then
        maxSeq = seq
      end
    end
  end

  if current <= maxSeq then
    current = maxSeq + 1
  end

  ns.db.nextInstanceSeq = current
  return ns.db.nextInstanceSeq
end

local function reserveNextInstanceSequence()
  local current = ensureInstanceSequenceState()
  if current then
    ns.db.nextInstanceSeq = current + 1
    return current
  end
  local seq = fallbackInstanceSeq
  fallbackInstanceSeq = seq + 1
  return seq
end

local function registerExistingInstanceUID(instanceUID)
  local seq = extractInstanceSequence(instanceUID)
  if not seq then
    return
  end
  if ns.db then
    local nextSeq = ensureInstanceSequenceState() or 1
    if seq >= nextSeq then
      ns.db.nextInstanceSeq = seq + 1
    end
    return
  end
  if seq >= fallbackInstanceSeq then
    fallbackInstanceSeq = seq + 1
  end
end

local function buildInstanceUID(spellID)
  local seq = reserveNextInstanceSequence()
  return string.format("a%d_s%s", tonumber(spellID) or 0, encodeBase36(seq))
end

local function sanitizeStandaloneToken(text)
  text = safeLower(tostring(text or ""))
  text = text:gsub("[^%w_]+", "_")
  text = text:gsub("_+", "_")
  text = text:gsub("^_+", "")
  text = text:gsub("_+$", "")
  return text
end

local function buildStandaloneContainerKey(unit, item)
  local unitToken = sanitizeStandaloneToken(unit or "player")
  local instanceUID = normalizeInstanceUID(item and item.instanceUID)
  if instanceUID ~= "" then
    return string.format("aura_%s_%s", unitToken, instanceUID)
  end

  local spellID = tonumber(item and item.spellID) or 0
  local groupToken = sanitizeStandaloneToken(item and item.groupID or "")
  local nameToken = sanitizeStandaloneToken(item and item.displayName or "")
  if nameToken == "" then
    nameToken = "spell" .. tostring(spellID)
  end
  return string.format("aura_%s_%s_%d_%s", unitToken, groupToken, spellID, nameToken)
end

local function ensureEntryInstanceUID(unit, item)
  if type(item) ~= "table" then
    return nil
  end
  local current = normalizeInstanceUID(item.instanceUID)
  if current ~= "" then
    item.instanceUID = current
    registerExistingInstanceUID(current)
    return current
  end

  local legacyKey = buildStandaloneContainerKey(unit, item)
  local newUID = buildInstanceUID(item.spellID)
  item.instanceUID = newUID
  local newKey = buildStandaloneContainerKey(unit, item)

  if ns.db and type(ns.db.positions) == "table" and legacyKey ~= newKey then
    local legacyPos = ns.db.positions[legacyKey]
    if type(legacyPos) == "table" and type(ns.db.positions[newKey]) ~= "table" then
      ns.db.positions[newKey] = {
        point = legacyPos.point,
        relativePoint = legacyPos.relativePoint,
        x = legacyPos.x,
        y = legacyPos.y,
      }
    end
  end

  return newUID
end

function D:EnsureWatchItemIdentity(unit, item)
  return ensureEntryInstanceUID(unit, item)
end

function D:EnsureIdentityState()
  return ensureInstanceSequenceState() or 1
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
      layout = {
        iconSize = 36,
        spacing = 4,
        direction = "RIGHT",
        sort = "list",
        wrapAfter = 0,
        nudgeX = 0,
        nudgeY = 0,
      },
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

function D:GetGroupConfig(groupID)
  groupID = normalizeGroupID(groupID)
  if groupID == "" then
    return {
      id = "",
      name = "",
      order = 9999,
      layout = {
        iconSize = 36,
        spacing = 4,
        direction = "RIGHT",
        sort = "list",
        wrapAfter = 0,
        nudgeX = 0,
        nudgeY = 0,
      },
    }
  end

  local cfg = ns.db.groups[groupID]
  if not cfg then
    return {
      id = groupID,
      name = groupID:gsub("_", " "):gsub("^%l", string.upper),
      order = 9999,
      layout = {
        iconSize = 36,
        spacing = 4,
        direction = "RIGHT",
        sort = "list",
        wrapAfter = 0,
        nudgeX = 0,
        nudgeY = 0,
      },
    }
  end

  local layout = cfg.layout or {}
  return {
    id = groupID,
    name = normalizeDisplayName(cfg.name ~= nil and cfg.name or groupID:gsub("_", " "):gsub("^%l", string.upper)),
    order = tonumber(cfg.order) or 9999,
    layout = {
      iconSize = normalizeSize(layout.iconSize, 36, 12, 256),
      spacing = normalizeSize(layout.spacing, 4, 0, 64),
      direction = normalizeGroupDirection(layout.direction),
      sort = normalizeGroupSort(layout.sort),
      wrapAfter = normalizeSize(layout.wrapAfter, 0, 0, 20),
      nudgeX = normalizeOffset(layout.nudgeX, 0),
      nudgeY = normalizeOffset(layout.nudgeY, 0),
    },
  }
end

function D:UpdateGroupConfig(groupID, model)
  groupID = normalizeGroupID(groupID)
  if groupID == "" then
    return ""
  end

  self:EnsureGroup(groupID, model and model.groupName)
  local cfg = ns.db.groups[groupID]
  if not cfg then
    return ""
  end

  local current = self:GetGroupConfig(groupID)
  cfg.name = normalizeDisplayName((model and model.groupName) or current.name)
  cfg.layout = cfg.layout or {}
  cfg.layout.iconSize = current.layout.iconSize
  cfg.layout.spacing = normalizeSize(model and model.groupSpacing, current.layout.spacing, 0, 64)
  cfg.layout.direction = normalizeGroupDirection(model and model.groupDirection or current.layout.direction)
  cfg.layout.sort = normalizeGroupSort(model and model.groupSort or current.layout.sort)
  cfg.layout.wrapAfter = normalizeSize(model and model.groupWrapAfter, current.layout.wrapAfter, 0, 20)
  cfg.layout.nudgeX = normalizeOffset(model and model.groupOffsetX, current.layout.nudgeX)
  cfg.layout.nudgeY = normalizeOffset(model and model.groupOffsetY, current.layout.nudgeY)

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

function D:CountGroupMembers(groupID)
  groupID = normalizeGroupID(groupID)
  if groupID == "" then
    return 0
  end
  local count = 0
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = 1, #list do
      if normalizeGroupID(list[i] and list[i].groupID) == groupID then
        count = count + 1
      end
    end
  end
  return count
end

function D:ListGroupsDetailed()
  local out = {}
  local keys = U.KeysSortedByNumberField(ns.db.groups or {}, "order")
  for i = 1, #keys do
    local groupID = keys[i]
    local cfg = self:GetGroupConfig(groupID)
    out[#out + 1] = {
      id = groupID,
      name = cfg.name or groupID,
      count = self:CountGroupMembers(groupID),
      direction = cfg.layout.direction or "RIGHT",
      spacing = tonumber(cfg.layout.spacing) or 4,
      sort = cfg.layout.sort or "list",
      wrapAfter = tonumber(cfg.layout.wrapAfter) or 0,
      offsetX = tonumber(cfg.layout.nudgeX) or 0,
      offsetY = tonumber(cfg.layout.nudgeY) or 0,
    }
  end
  return out
end

function D:DeleteGroup(groupID)
  groupID = normalizeGroupID(groupID)
  if groupID == "" or not ns.db.groups[groupID] then
    return 0
  end

  local changed = 0
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = 1, #list do
      local item = list[i]
      if normalizeGroupID(item and item.groupID) == groupID then
        item.groupID = ""
        item.groupOrder = nil
        changed = changed + 1
      end
    end
  end

  ns.db.groups[groupID] = nil
  if type(ns.db.positions) == "table" then
    ns.db.positions[groupID] = nil
  end
  if ns.Dragger and ns.Dragger.pendingPositions then
    ns.Dragger.pendingPositions[groupID] = nil
  end
  if ns.GroupManager then
    if ns.GroupManager.frames then
      ns.GroupManager.frames[groupID] = nil
    end
    if ns.GroupManager.layoutSigByGroup then
      ns.GroupManager.layoutSigByGroup[groupID] = nil
    end
  end

  if changed > 0 then
    ns:RebuildWatchIndex()
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  return changed
end

function D:ListGroupMembers(groupID)
  groupID = normalizeGroupID(groupID)
  local rows = {}
  if groupID == "" then
    return rows
  end

  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for index = 1, #list do
      local item = list[index]
      if normalizeGroupID(item and item.groupID) == groupID then
        local name = normalizeDisplayName(item and item.displayName)
        if name == "" then
          name = ns.AuraAPI:GetSpellName(item.spellID) or ("Spell " .. tostring(item.spellID or "?"))
        end
        rows[#rows + 1] = {
          key = unit .. ":" .. index,
          unit = unit,
          spellID = tonumber(item and item.spellID) or 0,
          name = name,
          groupOrder = tonumber(item and item.groupOrder) or 0,
        }
      end
    end
  end

  table.sort(rows, function(a, b)
    local ao = tonumber(a.groupOrder) or 0
    local bo = tonumber(b.groupOrder) or 0
    if ao ~= bo then
      return ao < bo
    end
    return tostring(a.name) < tostring(b.name)
  end)
  return rows
end

function D:SetEntryGroup(key, groupID)
  local entry = self:ResolveEntry(key)
  if not entry or not entry.item then
    return false
  end
  local oldGroupID = normalizeGroupID(entry.item.groupID)
  groupID = normalizeGroupID(groupID)
  if groupID ~= "" then
    self:EnsureGroup(groupID)
  end
  entry.item.groupID = groupID
  if groupID == "" then
    entry.item.groupOrder = nil
  else
    local members = self:ListGroupMembers(groupID)
    entry.item.groupOrder = #members + 1
  end
  if oldGroupID ~= "" and oldGroupID ~= groupID and ns.GroupManager and ns.GroupManager.layoutSigByGroup then
    ns.GroupManager.layoutSigByGroup[oldGroupID] = nil
  end
  if groupID ~= "" and ns.GroupManager and ns.GroupManager.layoutSigByGroup then
    ns.GroupManager.layoutSigByGroup[groupID] = nil
  end
  ns:RebuildWatchIndex()
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  return true
end

function D:MoveGroupMember(groupID, entryKey, direction)
  groupID = normalizeGroupID(groupID)
  if groupID == "" then
    return false
  end
  local members = self:ListGroupMembers(groupID)
  local currentIndex = nil
  for i = 1, #members do
    if members[i].key == entryKey then
      currentIndex = i
      break
    end
  end
  if not currentIndex then
    return false
  end

  local otherIndex = (direction == "up") and (currentIndex - 1) or (currentIndex + 1)
  if not otherIndex or otherIndex < 1 or otherIndex > #members then
    return false
  end

  local currentEntry = self:ResolveEntry(members[currentIndex].key)
  local otherEntry = self:ResolveEntry(members[otherIndex].key)
  if not currentEntry or not otherEntry then
    return false
  end

  local currentOrder = tonumber(currentEntry.item.groupOrder)
  if not currentOrder or currentOrder <= 0 then
    currentOrder = currentIndex
  end
  local otherOrder = tonumber(otherEntry.item.groupOrder)
  if not otherOrder or otherOrder <= 0 then
    otherOrder = otherIndex
  end
  currentEntry.item.groupOrder = otherOrder
  otherEntry.item.groupOrder = currentOrder

  ns:RebuildWatchIndex()
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  return true
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
  ensureEntryInstanceUID(unit, item)
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
      ensureEntryInstanceUID(unit, item)
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
  local groupConfig = self:GetGroupConfig(item.groupID or "")
  return {
    key = entry.key,
    unit = entry.unit,
    trackingMode = normalizeTrackingMode(item.trackingMode, entry.unit),
    castSpellIDs = normalizeSpellIDList(item.castSpellIDs),
    estimatedDuration = normalizeDuration(item.estimatedDuration, 8),
    timerBehavior = "reset",
    maxDuration = 0,
    stackBehavior = "replace",
    stackAmount = 1,
    maxStacks = 1,
    consumeBehavior = "hide",
    spellID = tonumber(item.spellID) or 0,
    spellName = ns.AuraAPI:GetSpellName(item.spellID) or "",
    instanceUID = normalizeInstanceUID(item.instanceUID),
    groupID = item.groupID or "",
    groupName = groupConfig.name or "",
    groupDirection = groupConfig.layout.direction or "RIGHT",
    groupSpacing = tonumber(groupConfig.layout.spacing) or 4,
    groupSort = groupConfig.layout.sort or "list",
    groupWrapAfter = tonumber(groupConfig.layout.wrapAfter) or 0,
    groupOffsetX = tonumber(groupConfig.layout.nudgeX) or 0,
    groupOffsetY = tonumber(groupConfig.layout.nudgeY) or 0,
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
    groupOrder = tonumber(item.groupOrder) or 0,
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
    savedPosition = cloneSavedPosition(item.savedPosition),
  }
end

function D:BuildDefaultCreateModel()
  return {
    spellInput = "",
    unit = "player",
    trackingMode = "confirmed",
    castSpellIDs = {},
    estimatedDuration = 8,
    timerBehavior = "reset",
    maxDuration = 0,
    stackBehavior = "replace",
    stackAmount = 1,
    maxStacks = 1,
    consumeBehavior = "hide",
    instanceUID = "",
    groupID = "",
    groupName = "",
    groupDirection = "RIGHT",
    groupSpacing = 4,
    groupSort = "list",
    groupWrapAfter = 0,
    groupOffsetX = 0,
    groupOffsetY = 0,
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
    groupOrder = 0,
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
    savedPosition = nil,
  }
end

function D:BuildWatchItemFromModel(model, options)
  options = type(options) == "table" and options or {}
  local spellID = U.ResolveSpellID(model.spellInput or model.spellID)
  if not spellID and ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
    spellID = ns.SpellCatalog:ResolveNameToSpellID(model.spellInput or model.spellID)
  end
  if not spellID then
    return nil, "Spell non trovato. Usa SpellID o nome corretto."
  end

  local groupID = normalizeGroupID(model.groupID)
  local existingItem = type(options.existingItem) == "table" and options.existingItem or nil
  local existingItemUID = normalizeInstanceUID(existingItem and existingItem.instanceUID)
  local modelUID = normalizeInstanceUID(model.instanceUID)
  local instanceUID = existingItemUID
  if instanceUID == "" then
    instanceUID = modelUID
  end
  if instanceUID == "" then
    instanceUID = buildInstanceUID(spellID)
  else
    registerExistingInstanceUID(instanceUID)
  end
  if groupID ~= "" then
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
    loadClassToken = normalizeClassToken(model.loadClassToken),
    loadSpecIDs = normalizeSpecIDList(model.loadSpecIDs),
    inCombatOnly = normalizeBool(model.inCombatOnly, false),
    onlyMine = normalizeBool(model.onlyMine, true),
    alert = normalizeBool(model.alert, true),
    displayName = normalizeDisplayName(model.displayName),
    customText = normalizeCustomText(model.customText),
    groupOrder = tonumber(model.groupOrder) or 0,
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
    savedPosition = cloneSavedPosition(model.savedPosition) or cloneSavedPosition(existingItem and existingItem.savedPosition),
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

  local list = ns.db.watchlist[unit] or {}
  return unit .. ":" .. #list
end

function D:FindEntryBySpell(unit, spellID, displayName)
  unit = self:NormalizeUnit(unit)
  spellID = tonumber(spellID)
  displayName = normalizeDisplayName(displayName)
  if not spellID then
    return nil
  end
  local list = ns.db.watchlist[unit] or {}
  for index = 1, #list do
    local item = list[index]
    if tonumber(item and item.spellID) == spellID then
      if displayName == "" or normalizeDisplayName(item and item.displayName) == displayName then
        return {
          key = unit .. ":" .. index,
          unit = unit,
          index = index,
          item = item,
          list = list,
        }
      end
    end
  end
  return nil
end

function D:InstallWarriorExamples()
  local examples = {
    {
      entry = {
        spellInput = 386030,
        unit = "player",
        displayName = "Brace for Impact",
        groupID = "",
        timerVisual = "iconbar",
        estimatedDuration = 16,
        castSpellIDs = { 23922 },
        lowTimeThreshold = 3,
      },
      rule = {
        id = "ui2_386030_produce",
        name = "Brace for Impact",
        castSpellIDs = { 23922 },
        auraSpellID = 386030,
        duration = 16,
        conditionMode = "all",
        actionMode = "produce",
        stackBehavior = "add",
        stackAmount = 1,
        maxStacks = 5,
        timerBehavior = "reset",
        maxDuration = 0,
      },
    },
    {
      entry = {
        spellInput = 2565,
        unit = "player",
        displayName = "Shield Block",
        groupID = "",
        timerVisual = "iconbar",
        estimatedDuration = 6,
        castSpellIDs = { 2565 },
        lowTimeThreshold = 3,
      },
      rule = {
        id = "ui2_2565_produce",
        name = "Shield Block",
        castSpellIDs = { 2565 },
        auraSpellID = 2565,
        duration = 6,
        conditionMode = "all",
        actionMode = "produce",
        stackBehavior = "replace",
        stackAmount = 1,
        maxStacks = 1,
        timerBehavior = "extend",
        maxDuration = 18,
      },
    },
  }

  local changed = 0
  for i = 1, #examples do
    local spec = examples[i]
    local existing = self:FindEntryBySpell(spec.entry.unit, spec.entry.spellInput, spec.entry.displayName)
    if existing and existing.item then
      ensureEntryInstanceUID(existing.unit, existing.item)
      existing.item.displayName = spec.entry.displayName
      existing.item.groupID = ""
      existing.item.castSpellIDs = normalizeSpellIDList(spec.entry.castSpellIDs)
      existing.item.timerVisual = normalizeTimerVisual(spec.entry.timerVisual)
      existing.item.estimatedDuration = normalizeDuration(spec.entry.estimatedDuration, 8)
      changed = changed + 1
    else
      self:AddEntry(spec.entry)
      changed = changed + 1
    end

    if ns.ProcRules and ns.ProcRules.AddSimpleIfRuleEx then
      ns.ProcRules:AddSimpleIfRuleEx(spec.rule)
    end
  end

  ns:RebuildWatchIndex()
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  return changed
end

function D:UpdateEntry(key, model)
  local entry = self:ResolveEntry(key)
  if not entry then
    return nil, "Aura selezionata non valida."
  end
  local oldContainerKey = buildStandaloneContainerKey(entry.unit, entry.item)
  local oldSavedPosition = cloneSavedPosition(entry.item and entry.item.savedPosition)
  local oldDbPosition = ns.db and ns.db.positions and cloneSavedPosition(ns.db.positions[oldContainerKey]) or nil

  if type(model) == "table" then
    local existingUID = normalizeInstanceUID(entry.item and entry.item.instanceUID)
    if existingUID ~= "" then
      model.instanceUID = existingUID
    end
    if not model.savedPosition then
      model.savedPosition = oldSavedPosition or oldDbPosition
    end
  end

  local item, err = self:BuildWatchItemFromModel(model, { existingItem = entry.item })
  if not item then
    return nil, err
  end

  local existingUID = normalizeInstanceUID(entry.item and entry.item.instanceUID)
  local newUID = normalizeInstanceUID(item and item.instanceUID)
  if existingUID ~= "" and newUID ~= existingUID then
    item.instanceUID = existingUID
  end
  if not item.savedPosition then
    item.savedPosition = oldSavedPosition or oldDbPosition
  end

  local fromUnit = entry.unit
  local toUnit = self:NormalizeUnit(model.unit)
  local removedIndex = entry.index

  if fromUnit == toUnit then
    entry.list[removedIndex] = item
    local newContainerKey = buildStandaloneContainerKey(toUnit, item)
    if ns.db and ns.db.positions and oldContainerKey ~= newContainerKey then
      local preservedPos = oldDbPosition or cloneSavedPosition(item.savedPosition)
      if preservedPos then
        ns.db.positions[newContainerKey] = cloneSavedPosition(preservedPos)
      end
    end
    ns:RebuildWatchIndex()
    ns.EventRouter:RefreshAll()
    return key
  end

  -- If unit changes, we move the item across lists and return the new key.
  table.remove(entry.list, removedIndex)
  ns.db.watchlist[toUnit][#ns.db.watchlist[toUnit] + 1] = item
  local movedContainerKey = buildStandaloneContainerKey(toUnit, item)
  if ns.db and ns.db.positions then
    local preservedPos = oldDbPosition or cloneSavedPosition(item.savedPosition)
    if preservedPos then
      ns.db.positions[movedContainerKey] = cloneSavedPosition(preservedPos)
    end
  end

  ns:RebuildWatchIndex()
  ns.EventRouter:RefreshAll()
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

  return removed
end

function D:CleanupLegacyPositionKeys()
  if not ns.db or type(ns.db.positions) ~= "table" then
    return 0
  end

  local validStandalone = {}
  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = 1, #list do
      local item = list[i]
      if type(item) == "table" then
        ensureEntryInstanceUID(unit, item)
        local key = buildStandaloneContainerKey(unit, item)
        if key ~= "" then
          validStandalone[key] = true
        end
      end
    end
  end

  local removed = 0
  for key in pairs(ns.db.positions) do
    if type(key) == "string" and key:find("^aura_", 1) == 1 and not validStandalone[key] then
      ns.db.positions[key] = nil
      removed = removed + 1
      if ns.Dragger and ns.Dragger.pendingPositions then
        ns.Dragger.pendingPositions[key] = nil
      end
      if ns.GroupManager then
        if ns.GroupManager.frames then
          ns.GroupManager.frames[key] = nil
        end
        if ns.GroupManager.layoutSigByGroup then
          ns.GroupManager.layoutSigByGroup[key] = nil
        end
      end
    end
  end

  return removed
end

function D:MigrateGroupLayoutState()
  if not ns.db or type(ns.db.watchlist) ~= "table" then
    return 0
  end

  local changed = 0
  local referenced = {}

  for _, unit in ipairs(trackedUnits) do
    local list = ns.db.watchlist[unit] or {}
    for i = 1, #list do
      local item = list[i]
      if type(item) == "table" then
        local groupID = normalizeGroupID(item.groupID)
        local instanceUID = normalizeInstanceUID(item.instanceUID)
        if instanceUID == "" then
          local legacyKey = buildStandaloneContainerKey(unit, item)
          instanceUID = buildInstanceUID(item.spellID)
          item.instanceUID = instanceUID
          local stableKey = buildStandaloneContainerKey(unit, item)
          if type(ns.db.positions) == "table"
            and stableKey ~= ""
            and stableKey ~= legacyKey
            and type(ns.db.positions[stableKey]) ~= "table"
            and type(ns.db.positions[legacyKey]) == "table"
          then
            ns.db.positions[stableKey] = ns.db.positions[legacyKey]
          end
          changed = changed + 1
        else
          item.instanceUID = instanceUID
          registerExistingInstanceUID(instanceUID)
        end
        if groupID ~= "" then
          if item.layoutGroupEnabled ~= nil then
            item.layoutGroupEnabled = nil
            changed = changed + 1
          end
          item.groupID = groupID
          referenced[groupID] = true
          self:EnsureGroup(groupID)
        else
          if item.layoutGroupEnabled ~= nil then
            item.layoutGroupEnabled = nil
            changed = changed + 1
          end
          item.groupID = ""
        end
      end
    end
  end

  for groupID in pairs(ns.db.groups or {}) do
    local autoGenerated = type(groupID) == "string" and groupID:find("^aura_", 1) == 1
    if autoGenerated and not referenced[groupID] then
      ns.db.groups[groupID] = nil
      if type(ns.db.positions) == "table" then
        ns.db.positions[groupID] = nil
      end
      changed = changed + 1
    end
  end

  changed = changed + self:CleanupLegacyPositionKeys()

  return changed
end







