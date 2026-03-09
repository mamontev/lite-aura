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

local function firstNumber(value)
  if type(value) == "table" then
    return tonumber(value[1])
  end
  return tonumber(value)
end

function B:IsDraftID(auraId)
  return type(auraId) == "string" and auraId:find("^__new__:") ~= nil
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
    triggerType = "cast",
    castSpellIDs = "",
    conditionLogic = "all",
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
    conditionLogic = "all",
    inCombatOnly = false,
    actionMode = "produce",
    duration = 8,
    displayMode = "icon",
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
  local model = {
    spellInput = trim(draft.spellID),
    displayName = trim(draft.name),
    unit = trim(draft.unit) ~= "" and trim(draft.unit) or "player",
    groupID = trim(draft.group) ~= "" and trim(draft.group) or "important_procs",
    loadClassToken = trim(draft.loadClassToken):upper(),
    loadSpecIDs = specIDs,
    layoutGroupEnabled = false,
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
  return model
end

function B:ToRuleModel(draft, auraSpellID)
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

  local baseID = string.format("ui2_%d", auraID)
  local mode = (tostring(draft and draft.actionMode or "produce") == "consume") and "consume" or "produce"

  return {
    id = baseID .. "_" .. mode,
    name = trim((draft and draft.name) or ""),
    castSpellIDs = castIDs,
    auraSpellID = auraID,
    duration = tonumber(draft and draft.duration) or 8,
    conditionMode = (tostring(draft and draft.conditionLogic or "all") == "any") and "any" or "all",
    loadClassToken = trim((draft and draft.loadClassToken) or ""):upper(),
    loadSpecIDs = parseCSVNumbers(draft and draft.loadSpecID),
    requireInCombat = draft and draft.inCombatOnly == true,
    actionMode = mode,
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
  draft.castSpellIDs = table.concat(out, ",")

  local thenActions = rule.thenActions or {}
  local firstType = tostring((thenActions[1] and thenActions[1].type) or "")
  if firstType:lower() == "hideaura" then
    draft.actionMode = "consume"
  else
    draft.actionMode = "produce"
  end

  if thenActions[1] and tonumber(thenActions[1].duration) then
    draft.duration = tonumber(thenActions[1].duration)
  end

  draft.conditionLogic = tostring(rule.conditionMode or "all") == "any" and "any" or "all"
  draft.loadClassToken = tostring(rule.classToken or "")
  local specs = parseCSVNumbers(rule.specIDs)
  draft.loadSpecID = specs[1] or ""

  local requireCombat = false
  for i = 1, #(rule.ifAll or {}) do
    local c = rule.ifAll[i]
    if tostring((c and c.type) or ""):lower() == "incombat" then
      requireCombat = true
      break
    end
  end
  draft.inCombatOnly = requireCombat

  return draft
end

function B:ParseCSVNumbers(value)
  return parseCSVNumbers(value)
end
