local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.Bindings = UI.Bindings or {}
local B = UI.Bindings

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function parseCSVNumbers(value)
  local out, seen = {}, {}
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

local function toCSV(list)
  local parts = {}
  for i = 1, #(list or {}) do
    parts[#parts + 1] = tostring(list[i])
  end
  return table.concat(parts, ",")
end

local function firstNumber(value)
  if type(value) == "table" then
    return tonumber(value[1])
  end
  return tonumber(value)
end

local function normalizeTrackingMode(value, unit)
  local mode = tostring(value or ""):lower()
  unit = tostring(unit or "player")
  if unit == "target" and mode == "estimated" then
    return "estimated"
  end
  return "confirmed"
end

local function defaultIconWidth(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return 36
end

local function defaultIconHeight(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return 36
end

local function defaultBarWidth(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return 94
end

local function defaultBarHeight(value)
  local n = tonumber(value)
  if n and n > 0 then
    return n
  end
  return 16
end

function B:IsDraftID(auraId)
  return type(auraId) == "string" and auraId:find("^__new__:") ~= nil
end

function B:IsDirectAuraTracking(draft)
  if type(draft) ~= "table" then
    return false
  end
  if self:IsEstimatedTargetDebuffTracking(draft) then
    return false
  end
  if tostring(draft.triggerType or "") == "aura" then
    return true
  end
  return tostring(draft.unit or "player") == "target"
end

function B:IsEstimatedTargetDebuffTracking(draft)
  if type(draft) ~= "table" then
    return false
  end
  return tostring(draft.unit or "player") == "target"
    and normalizeTrackingMode(draft.trackingMode, draft.unit) == "estimated"
end

function B:DraftFromEditableModel(model)
  model = model or {}
  local specList = parseCSVNumbers(model.loadSpecIDs)
  local unit = tostring(model.unit or "player")
  local trackingMode = normalizeTrackingMode(model.trackingMode, unit)
  local displayName = tostring(model.displayName or "")
  local groupID = tostring(model.groupID or "")
  return {
    id = tostring(model.key or ""),
    name = displayName,
    displayName = displayName,
    spellID = tostring(model.spellID or ""),
    unit = unit,
    group = groupID,
    groupID = groupID,
    groupName = tostring(model.groupName or ""),
    groupDirection = tostring(model.groupDirection or "RIGHT"),
    groupSpacing = tonumber(model.groupSpacing) or 4,
    groupSort = tostring(model.groupSort or "list"),
    groupWrapAfter = tonumber(model.groupWrapAfter) or 0,
    groupOffsetX = tonumber(model.groupOffsetX) or 0,
    groupOffsetY = tonumber(model.groupOffsetY) or 0,
    triggerType = (unit == "target" and trackingMode ~= "estimated") and "aura" or "cast",
    trackingMode = trackingMode,
    castSpellIDs = toCSV(model.castSpellIDs),
    ruleName = "",
    ruleID = "",
    conditionLogic = "all",
    talentSpellIDs = "",
    requiredAuraSpellIDs = "",
    inCombatOnly = model.inCombatOnly == true,
    actionMode = "produce",
    duration = tonumber(model.lowTimeThreshold) and math.max(1, tonumber(model.lowTimeThreshold)) or 8,
    estimatedDuration = tonumber(model.estimatedDuration) or 8,
    timerBehavior = "reset",
    maxDuration = tonumber(model.maxDuration) or 0,
    stackBehavior = "replace",
    stackAmount = 1,
    maxStacks = 1,
    consumeBehavior = "hide",
    displayMode = tostring(model.timerVisual or "icon"),
    lowTime = tonumber(model.lowTimeThreshold) or 0,
    soundOnShow = tostring(model.soundOnGain or "default"),
    soundOnLow = tostring(model.soundOnLow or "default"),
    soundOnExpire = tostring(model.soundOnExpire or "none"),
    loadClassToken = tostring(model.loadClassToken or ""),
    loadSpecID = specList[1] or "",
    loadSpecIDs = specList,
    instanceUID = tostring(model.instanceUID or ""),
    onlyMine = model.onlyMine == true,
    alert = model.alert ~= false,
    iconMode = tostring(model.iconMode or "spell"),
    customTexture = tostring(model.customTexture or ""),
    barTexture = tostring(model.barTexture or ""),
    customText = tostring(model.customText or ""),
    timerVisual = tostring(model.timerVisual or "icon"),
    iconWidth = defaultIconWidth(model.iconWidth),
    iconHeight = defaultIconHeight(model.iconHeight),
    barWidth = defaultBarWidth(model.barWidth),
    barHeight = defaultBarHeight(model.barHeight),
    showTimerText = model.showTimerText ~= false,
    barColor = tostring(model.barColor or ""),
    barSide = tostring(model.barSide or "right"),
    timerAnchor = tostring(model.timerAnchor or "BOTTOM"),
    timerOffsetX = tonumber(model.timerOffsetX) or 0,
    timerOffsetY = tonumber(model.timerOffsetY) or -1,
    customTextAnchor = tostring(model.customTextAnchor or "TOP"),
    customTextOffsetX = tonumber(model.customTextOffsetX) or 0,
    customTextOffsetY = tonumber(model.customTextOffsetY) or 2,
    resourceConditionEnabled = model.resourceConditionEnabled == true,
    resourceMinPct = tonumber(model.resourceMinPct) or 0,
    resourceMaxPct = tonumber(model.resourceMaxPct) or 100,
    notes = "",
    debug = false,
  }
end

function B:NewDraft(auraId)
  return {
    id = tostring(auraId or ""),
    name = "New Aura",
    spellID = "",
    unit = "player",
    group = "",
    groupID = "",
    groupName = "",
    groupDirection = "RIGHT",
    groupSpacing = 4,
    groupSort = "list",
    groupWrapAfter = 0,
    groupOffsetX = 0,
    groupOffsetY = 0,
    triggerType = "cast",
    trackingMode = "confirmed",
    castSpellIDs = "",
    ruleName = "",
    ruleID = "",
    conditionLogic = "all",
    talentSpellIDs = "",
    requiredAuraSpellIDs = "",
    inCombatOnly = false,
    actionMode = "produce",
    duration = 8,
    estimatedDuration = 8,
    timerBehavior = "reset",
    maxDuration = 0,
    stackBehavior = "replace",
    stackAmount = 1,
    maxStacks = 1,
    consumeBehavior = "hide",
    displayMode = "iconbar",
    lowTime = 3,
    soundOnShow = "default",
    soundOnExpire = "none",
    loadClassToken = "",
    loadSpecID = "",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
    barColor = "",
    barSide = "right",
    notes = "",
    debug = false,
  }
end

function B:ToSettingsDataModel(draft)
  draft = draft or {}
  local specIDs = parseCSVNumbers(draft.loadSpecID)
  local normalizedUnit = trim(draft.unit) ~= "" and trim(draft.unit) or "player"
  return {
    spellInput = trim(draft.spellID),
    displayName = trim(draft.name),
    unit = normalizedUnit,
    trackingMode = normalizeTrackingMode(draft.trackingMode, normalizedUnit),
    castSpellIDs = parseCSVNumbers(draft.castSpellIDs),
    estimatedDuration = tonumber(draft.estimatedDuration or draft.duration) or 8,
    groupID = trim(draft.groupID or draft.group),
    groupName = trim(draft.groupName),
    groupDirection = tostring(draft.groupDirection or "RIGHT"),
    groupSpacing = tonumber(draft.groupSpacing) or 4,
    groupSort = tostring(draft.groupSort or "list"),
    groupWrapAfter = tonumber(draft.groupWrapAfter) or 0,
    groupOffsetX = tonumber(draft.groupOffsetX) or 0,
    groupOffsetY = tonumber(draft.groupOffsetY) or 0,
    loadClassToken = trim(draft.loadClassToken):upper(),
    loadSpecIDs = draft.loadSpecIDs or specIDs,
    inCombatOnly = draft.inCombatOnly == true,
    instanceUID = trim(draft.instanceUID),
    onlyMine = self:IsEstimatedTargetDebuffTracking(draft) or draft.onlyMine == true,
    alert = draft.alert ~= false,
    iconMode = draft.iconMode or "spell",
    customTexture = draft.customTexture or "",
    barTexture = draft.barTexture or "",
    timerVisual = draft.timerVisual or ((draft.displayMode == "bar" or draft.displayMode == "iconbar") and draft.displayMode or "icon"),
    iconWidth = defaultIconWidth(draft.iconWidth),
    iconHeight = defaultIconHeight(draft.iconHeight),
    barWidth = defaultBarWidth(draft.barWidth),
    barHeight = defaultBarHeight(draft.barHeight),
    showTimerText = draft.showTimerText ~= false,
    barColor = draft.barColor or "",
    barSide = tostring(draft.barSide or "right"),
    customText = draft.customText or "",
    resourceConditionEnabled = draft.resourceConditionEnabled == true,
    resourceMinPct = tonumber(draft.resourceMinPct) or 0,
    resourceMaxPct = tonumber(draft.resourceMaxPct) or 100,
    lowTimeThreshold = tonumber(draft.lowTime) or 0,
    timerAnchor = draft.timerAnchor or "BOTTOM",
    timerOffsetX = tonumber(draft.timerOffsetX) or 0,
    timerOffsetY = tonumber(draft.timerOffsetY) or -1,
    customTextAnchor = draft.customTextAnchor or "TOP",
    customTextOffsetX = tonumber(draft.customTextOffsetX) or 0,
    customTextOffsetY = tonumber(draft.customTextOffsetY) or 2,
    soundOnGain = draft.soundOnShow or "default",
    soundOnLow = draft.soundOnLow or "default",
    soundOnExpire = draft.soundOnExpire or "none",
    groupOrder = tonumber(draft.groupOrder) or 0,
  }
end

function B:ToRuleModel(draft, auraSpellID)
  if self:IsDirectAuraTracking(draft) or self:IsEstimatedTargetDebuffTracking(draft) then
    return nil
  end

  local castIDs = parseCSVNumbers(draft and draft.castSpellIDs)
  if #castIDs == 0 then
    local n = firstNumber(draft and draft.spellID)
    if n and n > 0 then
      castIDs[1] = n
    end
  end

  local auraID = tonumber(auraSpellID) or firstNumber(draft and draft.spellID)
  if not auraID or auraID <= 0 then
    return nil
  end

  local mode = (tostring(draft and draft.actionMode or "produce") == "consume") and "consume" or "produce"
  local baseID = trim((draft and draft.ruleID) or "")
  if baseID == "" then
    baseID = string.format("ui2_%d", auraID)
  else
    baseID = baseID:gsub("_produce$", ""):gsub("_consume$", "")
  end
  local finalID = baseID .. "_" .. mode

  return {
    id = finalID,
    name = trim((draft and draft.ruleName) or (draft and draft.name) or ""),
    castSpellIDs = castIDs,
    auraSpellID = auraID,
    duration = tonumber(draft and draft.duration) or 8,
    timerBehavior = tostring(draft and draft.timerBehavior or "reset"),
    maxDuration = tonumber(draft and draft.maxDuration) or 0,
    stackBehavior = tostring(draft and draft.stackBehavior or "replace"),
    stackAmount = tonumber(draft and draft.stackAmount) or 1,
    maxStacks = tonumber(draft and draft.maxStacks) or 1,
    consumeBehavior = tostring(draft and draft.consumeBehavior or "hide"),
    conditionMode = (tostring(draft and draft.conditionLogic or "all") == "any") and "any" or "all",
    loadClassToken = trim((draft and draft.loadClassToken) or ""):upper(),
    loadSpecIDs = parseCSVNumbers(draft and draft.loadSpecID),
    talentSpellIDs = parseCSVNumbers(draft and draft.talentSpellIDs),
    requiredAuraSpellIDs = parseCSVNumbers(draft and draft.requiredAuraSpellIDs),
    requireInCombat = draft and draft.inCombatOnly == true,
    actionMode = mode,
    idBase = baseID,
  }
end

function B:ApplyRuleToDraft(draft, rule)
  if type(draft) ~= "table" or type(rule) ~= "table" then
    return draft
  end

  local eventSpellIDs = rule.eventSpellIDs or {}
  local out = {}
  for i = 1, #eventSpellIDs do
    local n = tonumber(eventSpellIDs[i])
    if n and n > 0 then
      out[#out + 1] = tostring(n)
    end
  end
  if #out == 0 and tonumber(rule.eventSpellID) then
    out[1] = tostring(tonumber(rule.eventSpellID))
  end
  draft.castSpellIDs = toCSV(out)
  draft.triggerType = (#out > 0) and "cast" or (draft.triggerType or "cast")

  local rid = tostring(rule.id or "")
  draft.ruleID = rid:gsub("_produce$", ""):gsub("_consume$", "")
  draft.ruleName = tostring(rule.name or "")

  local thenActions = rule.thenActions or {}
  local firstType = tostring((thenActions[1] and thenActions[1].type) or "")
  local normalizedFirstType = firstType:lower()
  draft.actionMode = (normalizedFirstType == "hideaura" or normalizedFirstType == "decrementaura") and "consume" or "produce"
  draft.consumeBehavior = (normalizedFirstType == "decrementaura") and "decrement" or "hide"

  if thenActions[1] and tonumber(thenActions[1].duration) then
    draft.duration = tonumber(thenActions[1].duration)
  end
  if thenActions[1] then
    draft.timerBehavior = tostring(thenActions[1].timerBehavior or "reset")
    draft.maxDuration = tonumber(thenActions[1].maxDuration) or 0
    draft.stackBehavior = tostring(thenActions[1].stackBehavior or (((tonumber(thenActions[1].maxStacks) or 1) > 1) and "add" or "replace"))
    draft.stackAmount = tonumber(thenActions[1].stackAmount or thenActions[1].stacks) or 1
    draft.maxStacks = tonumber(thenActions[1].maxStacks) or 1
  end

  draft.conditionLogic = tostring(rule.conditionMode or "all") == "any" and "any" or "all"
  draft.loadClassToken = tostring(rule.classToken or "")
  local specs = parseCSVNumbers(rule.specIDs)
  draft.loadSpecID = specs[1] or ""

  local talents = {}
  local reqAuras = {}
  local requireCombat = false
  for i = 1, #(rule.ifAll or {}) do
    local c = rule.ifAll[i] or {}
    local cType = tostring(c.type or ""):lower()
    if cType == "intalenttree" or cType == "istalented" then
      local sid = tonumber(c.spellID)
      if sid and sid > 0 then
        talents[#talents + 1] = sid
      end
    elseif cType == "auraactive" then
      local sid = tonumber(c.spellID)
      if sid and sid > 0 then
        reqAuras[#reqAuras + 1] = sid
      end
    elseif cType == "incombat" then
      requireCombat = true
    end
  end

  draft.talentSpellIDs = toCSV(talents)
  draft.requiredAuraSpellIDs = toCSV(reqAuras)
  draft.inCombatOnly = requireCombat
  return draft
end

function B:ParseCSVNumbers(value)
  return parseCSVNumbers(value)
end



