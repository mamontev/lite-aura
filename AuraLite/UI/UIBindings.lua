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

function B:IsDraftID(auraId)
  return type(auraId) == "string" and auraId:find("^__new__:") ~= nil
end

function B:IsDirectAuraTracking(draft)
  if type(draft) ~= "table" then
    return false
  end
  if tostring(draft.triggerType or "") == "aura" then
    return true
  end
  return tostring(draft.unit or "player") == "target"
end

function B:DraftFromEditableModel(model)
  model = model or {}
  local specList = parseCSVNumbers(model.loadSpecIDs)
  return {
    id = tostring(model.key or ""),
    name = tostring(model.displayName or ""),
    spellID = tostring(model.spellID or ""),
    unit = tostring(model.unit or "player"),
    group = tostring(model.groupID or "important_procs"),
    triggerType = (tostring(model.unit or "player") == "target") and "aura" or "cast",
    castSpellIDs = "",
    ruleName = "",
    ruleID = "",
    conditionLogic = "all",
    talentSpellIDs = "",
    requiredAuraSpellIDs = "",
    inCombatOnly = false,
    actionMode = "produce",
    duration = tonumber(model.lowTimeThreshold) and math.max(1, tonumber(model.lowTimeThreshold)) or 8,
    displayMode = tostring(model.timerVisual or "icon"),
    lowTime = tonumber(model.lowTimeThreshold) or 0,
    soundOnShow = tostring(model.soundOnGain or "default"),
    soundOnExpire = tostring(model.soundOnExpire or "none"),
    loadClassToken = tostring(model.loadClassToken or ""),
    loadSpecID = specList[1] or "",
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
    group = "important_procs",
    triggerType = "cast",
    castSpellIDs = "",
    ruleName = "",
    ruleID = "",
    conditionLogic = "all",
    talentSpellIDs = "",
    requiredAuraSpellIDs = "",
    inCombatOnly = false,
    actionMode = "produce",
    duration = 8,
    displayMode = "iconbar",
    lowTime = 3,
    soundOnShow = "default",
    soundOnExpire = "none",
    loadClassToken = "",
    loadSpecID = "",
    notes = "",
    debug = false,
  }
end

function B:ToSettingsDataModel(draft)
  draft = draft or {}
  local specIDs = parseCSVNumbers(draft.loadSpecID)
  local normalizedUnit = trim(draft.unit) ~= "" and trim(draft.unit) or "player"
  if ns.Debug and ns.Debug.Logf then
    ns.Debug:Logf("UIBindings ToSettingsDataModel draft.id=%s draft.unit=%s normalized.unit=%s spellID=%s", tostring(draft.id or ""), tostring(draft.unit or ""), tostring(normalizedUnit), tostring(draft.spellID or ""))
  end
  return {
    spellInput = trim(draft.spellID),
    displayName = trim(draft.name),
    unit = normalizedUnit,
    groupID = trim(draft.group) ~= "" and trim(draft.group) or "important_procs",
    loadClassToken = trim(draft.loadClassToken):upper(),
    loadSpecIDs = specIDs,
    layoutGroupEnabled = draft.layoutGroupEnabled ~= false,
    instanceUID = trim(draft.instanceUID),
    onlyMine = draft.onlyMine == true,
    alert = true,
    iconMode = "spell",
    customTexture = "",
    barTexture = "",
    timerVisual = (draft.displayMode == "bar" or draft.displayMode == "iconbar") and draft.displayMode or "icon",
    customText = "",
    resourceConditionEnabled = false,
    resourceMinPct = 0,
    resourceMaxPct = 100,
    lowTimeThreshold = tonumber(draft.lowTime) or 0,
    timerAnchor = "BOTTOM",
    timerOffsetX = 0,
    timerOffsetY = -1,
    customTextAnchor = "TOP",
    customTextOffsetX = 0,
    customTextOffsetY = 2,
    soundOnGain = draft.soundOnShow or "default",
    soundOnLow = "default",
    soundOnExpire = draft.soundOnExpire or "none",
  }
end

function B:ToRuleModel(draft, auraSpellID)
  if self:IsDirectAuraTracking(draft) then
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
  draft.actionMode = firstType:lower() == "hideaura" and "consume" or "produce"

  if thenActions[1] and tonumber(thenActions[1].duration) then
    draft.duration = tonumber(thenActions[1].duration)
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



