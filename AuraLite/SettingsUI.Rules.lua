local _, ns = ...
local U = ns.Utils
local C = ns.UIComponents
local D = ns.SettingsData
local L = ns.Localization

ns.SettingsUI = ns.SettingsUI or {}
local UI = ns.SettingsUI

local function info(text)
  if ns.ConfigUI and ns.ConfigUI.Message then
    ns.ConfigUI:Message(text)
  end
end

local function tr(key)
  if L and L.T then
    return L:T(key)
  end
  return key
end

local function safeLower(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower()
end

local function parseSpellIDList(text)
  local out = {}
  local seen = {}
  text = tostring(text or "")
  for token in text:gmatch("[^,%s;]+") do
    local id = tonumber(U.Trim(token))
    if id and id > 0 and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end
  return out
end

local function joinSpellIDList(ids)
  if type(ids) ~= "table" or #ids == 0 then
    return ""
  end
  local out = {}
  for i = 1, #ids do
    out[#out + 1] = tostring(ids[i])
  end
  return table.concat(out, ",")
end

local function firstSpecID(raw)
  if type(raw) == "table" then
    local sid = tonumber(raw[1])
    if sid and sid > 0 then
      return sid
    end
    return nil
  end
  local text = tostring(raw or "")
  for token in text:gmatch("[^,%s;]+") do
    local sid = tonumber(token)
    if sid and sid > 0 then
      return sid
    end
  end
  return nil
end

function UI:RefreshRuleLoadSpecDropdown(selectedSpecID, resetSelection)
  if not self.rulesFrame or not self.rulesFrame.ddLoadSpec then
    return
  end
  local f = self.rulesFrame
  local classToken = (f.ddLoadClass and f.ddLoadClass:GetValue()) or ""
  f.ddLoadSpec:SetOptions(D:GetLoadSpecMenuOptions(classToken))
  if resetSelection then
    f.ddLoadSpec:SetValue("")
    return
  end
  local sid = tonumber(selectedSpecID)
  if sid and sid > 0 then
    f.ddLoadSpec:SetValue(sid)
  else
    f.ddLoadSpec:SetValue("")
  end
end
local function inferRuleType(rule)
  if type(rule) ~= "table" then
    return nil
  end
  local thenActions = type(rule.thenActions) == "table" and rule.thenActions or {}
  local firstThen = thenActions[1]
  if firstThen and tostring(firstThen.type or ""):lower() == "showaura" then
    return "if"
  end
  if firstThen and tostring(firstThen.type or ""):lower() == "hideaura" then
    return "consume"
  end
  return nil
end

local function inferSimpleRuleModel(rule)
  local ruleType = inferRuleType(rule)
  if not ruleType then
    return nil
  end
  local model = {
    type = ruleType,
    id = tostring(rule.id or ""),
    name = tostring(rule.name or ""),
    castSpellIDs = {},
    conditionMode = (tostring(rule.conditionMode or "all"):lower() == "any") and "any" or "all",
    talentSpellIDs = {},
    requiredAuraSpellIDs = {},
    requireInCombat = false,
    auraSpellID = nil,
    duration = 0,
    loadClassToken = tostring(rule.classToken or ""),
    loadSpecIDs = {},
  }

  if type(rule.eventSpellIDs) == "table" then
    for i = 1, #rule.eventSpellIDs do
      local id = tonumber(rule.eventSpellIDs[i])
      if id then
        model.castSpellIDs[#model.castSpellIDs + 1] = id
      end
    end
  end
  if #model.castSpellIDs == 0 then
    local single = tonumber(rule.eventSpellID)
    if single then
      model.castSpellIDs[1] = single
    end
  end

  local ifAll = type(rule.ifAll) == "table" and rule.ifAll or {}
  local thenActions = type(rule.thenActions) == "table" and rule.thenActions or {}
  local firstThen = thenActions[1] or {}

  if ruleType == "if" then
    model.auraSpellID = tonumber(firstThen.auraSpellID) or nil
    model.duration = tonumber(firstThen.duration) or 0
    for i = 1, #ifAll do
      local cond = ifAll[i]
      local condType = tostring(cond.type or ""):lower()
      if condType == "istalented" then
        local id = tonumber(cond.spellID)
        if id then
          model.talentSpellIDs[#model.talentSpellIDs + 1] = id
        end
      elseif condType == "auraactive" then
        local id = tonumber(cond.spellID)
        if id then
          model.requiredAuraSpellIDs[#model.requiredAuraSpellIDs + 1] = id
        end
      elseif condType == "incombat" then
        model.requireInCombat = true
      end
    end
  else
    model.auraSpellID = tonumber(firstThen.auraSpellID) or nil
    for i = 1, #ifAll do
      local cond = ifAll[i]
      local condType = tostring(cond.type or ""):lower()
      if condType == "istalented" then
        local id = tonumber(cond.spellID)
        if id then
          model.talentSpellIDs[#model.talentSpellIDs + 1] = id
        end
      elseif condType == "auraactive" then
        local id = tonumber(cond.spellID)
        if id then
          model.requiredAuraSpellIDs[#model.requiredAuraSpellIDs + 1] = id
        end
      elseif condType == "incombat" then
        model.requireInCombat = true
      end
    end
  end

  if type(rule.specSet) == "table" then
    for specID in pairs(rule.specSet) do
      local sid = tonumber(specID)
      if sid and sid > 0 then
        model.loadSpecIDs[#model.loadSpecIDs + 1] = sid
      end
    end
    table.sort(model.loadSpecIDs)
  end
  return model
end

function UI:BuildRulePresetModel(presetType)
  if not self.rulesFrame then
    return nil
  end
  local f = self.rulesFrame
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  if not auraSpellID and f.editAuraSpell then
    auraSpellID = tonumber(U.Trim(f.editAuraSpell:GetText() or ""))
  end
  if not auraSpellID then
    return nil
  end

  local castSpellIDs = parseSpellIDList((f.editCastSpell and f.editCastSpell:GetText()) or "")
  local duration = tonumber(U.Trim((f.editDuration and f.editDuration:GetText()) or "")) or 8
  if duration <= 0 then
    duration = 8
  end

  local model = {
    id = string.format("a%d_%s", auraSpellID, tostring(presetType or "rule")),
    name = string.format("Aura %d %s", auraSpellID, tostring(presetType or "rule")),
    castSpellIDs = castSpellIDs,
    conditionMode = "all",
    talentSpellIDs = {},
    requiredAuraSpellIDs = {},
    requireInCombat = true,
    auraSpellID = auraSpellID,
    duration = duration,
    loadClassToken = "",
    loadSpecIDs = {},
    type = "if",
  }

  if presetType == "consume" then
    model.type = "consume"
    model.requiredAuraSpellIDs = { auraSpellID }
    model.requireInCombat = false
  elseif presetType == "show_talent" then
    model.type = "if"
    model.talentSpellIDs = { auraSpellID }
  else
    model.type = "if"
  end

  return model
end

function UI:ApplyRulePreset(presetType)
  local model = self:BuildRulePresetModel(presetType)
  if not model then
    info(tr("msg_rule_select_aura"))
    return
  end
  self:ApplyRuleFormModel(model)
  if presetType == "consume" then
    self:SetRulesSubTab("actions", false)
  else
    self:SetRulesSubTab("trigger", false)
  end
end

function UI:RefreshRulesTypeVisibility()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local ruleType = (f.ddType and f.ddType:GetValue()) or "if"
  local subTab = tostring(f.activeSubTab or "trigger")
  local guided = ns.db and ns.db.options and ns.db.options.uiGuidedMode == true

  local onTrigger = subTab == "trigger"
  local onConditions = subTab == "conditions"
  local onActions = subTab == "actions"

  if guided then
    -- Guided mode keeps the rule builder linear and WA-like: core fields only.
    onTrigger = true
    onConditions = false
    onActions = false
  end

  local function setShown(ctrl, shown)
    if ctrl then
      ctrl:SetShown(shown == true)
    end
  end

  setShown(f.rulesSegment, not guided)

  setShown(f.lblType, onTrigger and not guided)
  setShown(f.ddType, onTrigger and not guided)
  setShown(f.lblRuleName, onTrigger)
  setShown(f.editRuleName, onTrigger)
  setShown(f.lblRuleID, onTrigger and not guided)
  setShown(f.editRuleID, onTrigger and not guided)
  setShown(f.lblCastSpell, onTrigger)
  setShown(f.editCastSpell, onTrigger)
  setShown(f.lblPresets, onTrigger)
  setShown(f.btnPresetShow, onTrigger)
  setShown(f.btnPresetTalent, onTrigger)
  setShown(f.btnPresetConsume, onTrigger)

  local showConditionMode = onConditions and not guided
  local showTalent = onConditions and not guided
  local showRequiredAura = onConditions and not guided
  local showLoad = (onConditions and not guided) or guided

  setShown(f.lblConditionMode, showConditionMode)
  setShown(f.ddConditionMode, showConditionMode)
  setShown(f.lblTalentSpell, showTalent)
  setShown(f.editTalentSpell, showTalent)
  setShown(f.lblConditionAura, showRequiredAura)
  setShown(f.editConditionAura, showRequiredAura)
  setShown(f.lblLoadClass, showLoad)
  setShown(f.ddLoadClass, showLoad)
  setShown(f.lblLoadSpec, showLoad)
  setShown(f.ddLoadSpec, showLoad)
  setShown(f.cbConditionCombat, showLoad)
  setShown(f.csvHint, (onConditions and not guided))

  local showActionsCore = onActions or guided
  setShown(f.lblAuraSpell, showActionsCore)
  setShown(f.editAuraSpell, showActionsCore)
  setShown(f.lblDuration, showActionsCore and ruleType == "if")
  setShown(f.editDuration, showActionsCore and ruleType == "if")
end

function UI:RelayoutRulesPanel()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local panelW = math.floor(f:GetWidth() or 0)
  local panelH = math.floor(f:GetHeight() or 0)
  if panelW <= 0 or panelH <= 0 then
    return
  end

  local listW = math.max(220, math.min(300, math.floor(panelW * 0.34)))
  local formX = listW + 54
  local formW = math.max(280, panelW - formX - 12)
  local colGap = 14
  local colW = math.max(132, math.floor((formW - colGap) / 2))
  local colB = formX + colW + colGap

  local yTypeLabel = -104
  local yTypeInput = -120
  local yNameLabel = -146
  local yNameInput = -162
  local yRuleLabel = -188
  local yRuleInput = -204
  local yFieldLabel = -230
  local yFieldInput = -246

  local yCondTalentLabel = yTypeInput - 28
  local yCondTalentInput = yCondTalentLabel - 16
  local yCondAuraLabel = yCondTalentInput - 26
  local yCondAuraInput = yCondAuraLabel - 16
  local yCondLoadLabel = yCondAuraInput - 26
  local yCondLoadInput = yCondLoadLabel - 16
  if guided then
    -- Guided mode shows trigger + action + load in one vertical flow.
    yCondLoadLabel = yFieldInput - 28
    yCondLoadInput = yCondLoadLabel - 16
  end

  f.listBaseWidth = listW

  if f.editFilter then
    f.editFilter:ClearAllPoints()
    f.editFilter:SetPoint("TOPLEFT", 8, -46)
    f.editFilter:SetWidth(math.max(120, listW - 32))
  end

  if f.listScroll then
    f.listScroll:ClearAllPoints()
    f.listScroll:SetPoint("TOPLEFT", 10, -72)
    f.listScroll:SetSize(listW, math.max(160, panelH - 118))
    local sb = f.listScroll.ScrollBar
    if sb then
      sb:ClearAllPoints()
      sb:SetPoint("TOPLEFT", f.listScroll, "TOPRIGHT", 1, -16)
      sb:SetPoint("BOTTOMLEFT", f.listScroll, "BOTTOMRIGHT", 1, 16)
    end
  end
  if f.listContent then
    f.listContent:SetSize(math.max(112, listW - 42), math.max(24, #(f.ruleRows or {}) * 24))
  end

  if f.rulesSegment then
    f.rulesSegment:ClearAllPoints()
    f.rulesSegment:SetPoint("TOPLEFT", formX, -30)
    f.rulesSegment:SetWidth(math.min(340, formW))
  end
  if f.ruleNarrative then
    f.ruleNarrative:ClearAllPoints()
    f.ruleNarrative:SetPoint("TOPLEFT", formX, -56)
    f.ruleNarrative:SetWidth(formW)
  end

  if f.lblPresets then
    f.lblPresets:ClearAllPoints()
    f.lblPresets:SetPoint("TOPLEFT", formX, -82)
  end
  if f.btnPresetShow then
    f.btnPresetShow:ClearAllPoints()
    f.btnPresetShow:SetPoint("TOPLEFT", formX, -100)
  end
  if f.btnPresetTalent and f.btnPresetShow then
    f.btnPresetTalent:ClearAllPoints()
    f.btnPresetTalent:SetPoint("LEFT", f.btnPresetShow, "RIGHT", 8, 0)
  end
  if f.btnPresetConsume and f.btnPresetTalent then
    f.btnPresetConsume:ClearAllPoints()
    f.btnPresetConsume:SetPoint("LEFT", f.btnPresetTalent, "RIGHT", 8, 0)
  end

  if f.lblType then
    f.lblType:ClearAllPoints()
    f.lblType:SetPoint("TOPLEFT", formX, yTypeLabel)
    f.lblType:SetWidth(formW)
  end
  if f.ddType then
    f.ddType:ClearAllPoints()
    f.ddType:SetPoint("TOPLEFT", formX - 16, yTypeInput)
    f.ddType:SetWidth(formW)
  end

  if f.lblRuleName then
    f.lblRuleName:ClearAllPoints()
    f.lblRuleName:SetPoint("TOPLEFT", formX, yNameLabel)
    f.lblRuleName:SetWidth(formW)
  end
  if f.editRuleName then
    f.editRuleName:ClearAllPoints()
    f.editRuleName:SetPoint("TOPLEFT", formX, yNameInput)
    f.editRuleName:SetWidth(formW)
  end
  if f.lblRuleID then
    f.lblRuleID:ClearAllPoints()
    f.lblRuleID:SetPoint("TOPLEFT", formX, yRuleLabel)
    f.lblRuleID:SetWidth(formW)
  end
  if f.editRuleID then
    f.editRuleID:ClearAllPoints()
    f.editRuleID:SetPoint("TOPLEFT", formX, yRuleInput)
    f.editRuleID:SetWidth(formW)
  end

  if f.lblCastSpell then
    f.lblCastSpell:ClearAllPoints()
    f.lblCastSpell:SetPoint("TOPLEFT", formX, yFieldLabel)
    f.lblCastSpell:SetWidth(formW)
  end
  if f.editCastSpell then
    f.editCastSpell:ClearAllPoints()
    f.editCastSpell:SetPoint("TOPLEFT", formX, yFieldInput)
    f.editCastSpell:SetWidth(formW)
  end

  if f.lblConditionMode then
    f.lblConditionMode:ClearAllPoints()
    f.lblConditionMode:SetPoint("TOPLEFT", formX, yTypeLabel)
    f.lblConditionMode:SetWidth(formW)
  end
  if f.ddConditionMode then
    f.ddConditionMode:ClearAllPoints()
    f.ddConditionMode:SetPoint("TOPLEFT", formX - 16, yTypeInput)
    f.ddConditionMode:SetWidth(colW)
  end
  if f.lblTalentSpell then
    f.lblTalentSpell:ClearAllPoints()
    f.lblTalentSpell:SetPoint("TOPLEFT", formX, yCondTalentLabel)
    f.lblTalentSpell:SetWidth(formW)
  end
  if f.editTalentSpell then
    f.editTalentSpell:ClearAllPoints()
    f.editTalentSpell:SetPoint("TOPLEFT", formX, yCondTalentInput)
    f.editTalentSpell:SetWidth(formW)
  end
  if f.lblConditionAura then
    f.lblConditionAura:ClearAllPoints()
    f.lblConditionAura:SetPoint("TOPLEFT", formX, yCondAuraLabel)
    f.lblConditionAura:SetWidth(formW)
  end
  if f.editConditionAura then
    f.editConditionAura:ClearAllPoints()
    f.editConditionAura:SetPoint("TOPLEFT", formX, yCondAuraInput)
    f.editConditionAura:SetWidth(formW)
  end
  if f.lblLoadClass then
    f.lblLoadClass:ClearAllPoints()
    f.lblLoadClass:SetPoint("TOPLEFT", formX, yCondLoadLabel)
    f.lblLoadClass:SetWidth(colW)
  end
  if f.ddLoadClass then
    f.ddLoadClass:ClearAllPoints()
    f.ddLoadClass:SetPoint("TOPLEFT", formX - 16, yCondLoadInput)
    f.ddLoadClass:SetWidth(colW)
  end
  if f.lblLoadSpec then
    f.lblLoadSpec:ClearAllPoints()
    f.lblLoadSpec:SetPoint("TOPLEFT", colB, yCondLoadLabel)
    f.lblLoadSpec:SetWidth(colW)
  end
  if f.ddLoadSpec then
    f.ddLoadSpec:ClearAllPoints()
    f.ddLoadSpec:SetPoint("TOPLEFT", colB - 16, yCondLoadInput)
    f.ddLoadSpec:SetWidth(colW)
  end
  if f.cbConditionCombat then
    f.cbConditionCombat:ClearAllPoints()
    if guided then
      f.cbConditionCombat:SetPoint("TOPLEFT", formX, yCondLoadInput - 30)
    elseif f.ddLoadSpec then
      f.cbConditionCombat:SetPoint("TOPLEFT", f.ddLoadSpec, "BOTTOMLEFT", 0, -6)
    elseif f.editConditionAura then
      f.cbConditionCombat:SetPoint("TOPLEFT", f.editConditionAura, "BOTTOMLEFT", 0, -6)
    else
      f.cbConditionCombat:SetPoint("TOPLEFT", formX, yCondLoadInput - 30)
    end
  end
  if f.csvHint then
    f.csvHint:ClearAllPoints()
    if f.cbConditionCombat then
      f.csvHint:SetPoint("TOPLEFT", f.cbConditionCombat, "BOTTOMLEFT", 0, -4)
    else
      f.csvHint:SetPoint("TOPLEFT", formX, yCondLoadInput - 54)
    end
    f.csvHint:SetWidth(formW)
  end

  if f.lblAuraSpell then
    f.lblAuraSpell:ClearAllPoints()
    f.lblAuraSpell:SetPoint("TOPLEFT", formX, yRuleLabel)
    f.lblAuraSpell:SetWidth(colW)
  end
  if f.editAuraSpell then
    f.editAuraSpell:ClearAllPoints()
    f.editAuraSpell:SetPoint("TOPLEFT", formX, yRuleInput)
    f.editAuraSpell:SetWidth(colW)
  end
  if f.lblDuration then
    f.lblDuration:ClearAllPoints()
    f.lblDuration:SetPoint("TOPLEFT", colB, yRuleLabel)
    f.lblDuration:SetWidth(colW)
  end
  if f.editDuration then
    f.editDuration:ClearAllPoints()
    f.editDuration:SetPoint("TOPLEFT", colB, yRuleInput)
    f.editDuration:SetWidth(colW)
  end

  if f.btnSave then
    f.btnSave:ClearAllPoints()
    f.btnSave:SetPoint("BOTTOMLEFT", formX, 10)
  end
  if f.btnRemove and f.btnSave then
    f.btnRemove:ClearAllPoints()
    f.btnRemove:SetPoint("LEFT", f.btnSave, "RIGHT", 8, 0)
  end

  self:RefreshRulesList()
  self:RefreshRulesTypeVisibility()
end
function UI:SetRulesSubTab(tabKey, emit)
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  if tabKey ~= "trigger" and tabKey ~= "conditions" and tabKey ~= "actions" then
    tabKey = "trigger"
  end
  f.activeSubTab = tabKey
  if f.rulesSegment then
    f.rulesSegment:SetValue(tabKey, emit == true)
  end
  self:RelayoutRulesPanel()
  self:RefreshRulesTypeVisibility()
end

function UI:ApplyRuleFormModel(model)
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local boundAuraSpellID = self:GetActiveRuleAuraSpellID()
  model = model or {
    type = "if",
    id = "",
    name = "",
    castSpellIDs = {},
    conditionMode = "all",
    talentSpellIDs = {},
    requiredAuraSpellIDs = {},
    requireInCombat = false,
    auraSpellID = boundAuraSpellID or "",
    duration = 8,
    loadClassToken = "",
    loadSpecIDs = {},
  }
  if f.ddType then
    f.ddType:SetValue(model.type or "if")
  end
  if f.editRuleName then
    f.editRuleName:SetText(tostring(model.name or ""))
  end
  if f.editRuleID then
    f.editRuleID:SetText(tostring(model.id or ""))
  end
  if f.editCastSpell then
    f.editCastSpell:SetText(joinSpellIDList(model.castSpellIDs))
  end
  if f.editTalentSpell then
    f.editTalentSpell:SetText(joinSpellIDList(model.talentSpellIDs))
  end
  if f.ddConditionMode then
    f.ddConditionMode:SetValue((model.conditionMode == "any") and "any" or "all")
  end
  if f.editConditionAura then
    f.editConditionAura:SetText(joinSpellIDList(model.requiredAuraSpellIDs))
  end
  if f.ddLoadClass then
    f.ddLoadClass:SetValue(tostring(model.loadClassToken or ""))
  end
  self:RefreshRuleLoadSpecDropdown(firstSpecID(model.loadSpecIDs), false)
  if f.cbConditionCombat then
    f.cbConditionCombat:SetChecked(model.requireInCombat == true)
  end
  if f.editAuraSpell then
    local auraForRule = boundAuraSpellID or model.auraSpellID
    f.editAuraSpell:SetText(tostring(auraForRule or ""))
  end
  if f.editDuration then
    local d = tonumber(model.duration) or 0
    if d <= 0 then
      d = 8
    end
    f.editDuration:SetText(tostring(d))
  end
  f.selectedRuleID = tostring(model.id or "")
  self:SyncRuleAuraBinding()
  self:RefreshRuleNarrative(model)
  self:RefreshRulesTypeVisibility()
end

function UI:RefreshRuleNarrative(model)
  if not self.rulesFrame or not self.rulesFrame.ruleNarrative then
    return
  end
  model = model or {}
  local ruleType = tostring(model.type or "if")
  local castText = joinSpellIDList(model.castSpellIDs or {})
  if castText == "" then
    castText = "?"
  end
  local ifText = tr("rule_condition_and")
  if tostring(model.conditionMode or "all") == "any" then
    ifText = tr("rule_condition_or")
  end
  local auraText = tostring(model.auraSpellID or "?")
  local tail = ""
  if ruleType == "if" then
    tail = string.format("%s %ss", tr("rule_narrative_show"), tostring(tonumber(model.duration) or 8))
  else
    tail = tr("rule_narrative_consume")
  end
  self.rulesFrame.ruleNarrative:SetText(string.format("%s %s | %s %s | %s %s", tr("rule_narrative_when"), castText, tr("rule_narrative_if"), ifText, tr("rule_narrative_then"), tail .. " #" .. auraText))
end

function UI:CollectRuleFormModel()
  if not self.rulesFrame then
    return nil, tr("msg_rule_invalid")
  end
  local f = self.rulesFrame
  local boundAuraSpellID = self:GetActiveRuleAuraSpellID()
  local castSpellIDs = parseSpellIDList((f.editCastSpell and f.editCastSpell:GetText()) or "")
  local talentSpellIDs = parseSpellIDList((f.editTalentSpell and f.editTalentSpell:GetText()) or "")
  local requiredAuraSpellIDs = parseSpellIDList((f.editConditionAura and f.editConditionAura:GetText()) or "")
  local model = {
    type = f.ddType and f.ddType:GetValue() or "if",
    id = U.Trim((f.editRuleID and f.editRuleID:GetText()) or ""),
    name = U.Trim((f.editRuleName and f.editRuleName:GetText()) or ""),
    castSpellIDs = castSpellIDs,
    conditionMode = (f.ddConditionMode and f.ddConditionMode:GetValue()) or "all",
    talentSpellIDs = talentSpellIDs,
    requiredAuraSpellIDs = requiredAuraSpellIDs,
    loadClassToken = U.Trim((f.ddLoadClass and f.ddLoadClass:GetValue()) or ""):upper(),
    loadSpecIDs = (f.ddLoadSpec and f.ddLoadSpec:GetValue()) or "",
    requireInCombat = (f.cbConditionCombat and f.cbConditionCombat:GetChecked() == true) or false,
    auraSpellID = boundAuraSpellID or tonumber(U.Trim((f.editAuraSpell and f.editAuraSpell:GetText()) or "")),
    duration = tonumber(U.Trim((f.editDuration and f.editDuration:GetText()) or "")) or 0,
  }
  if model.conditionMode ~= "any" then
    model.conditionMode = "all"
  end
  if model.id == "" or #model.castSpellIDs == 0 or not model.auraSpellID then
    return nil, tr("msg_rule_invalid")
  end
  if model.type == "if" then
    if model.duration <= 0 then
      model.duration = 8
    end
  end
  self:RefreshRuleNarrative(model)
  return model
end

function UI:RefreshRulesList()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  if f.lblList then
    if auraSpellID then
      f.lblList:SetText(string.format("%s (%d)", tr("rules_list"), auraSpellID))
    else
      f.lblList:SetText(tr("rules_list"))
    end
  end
  local rules = {}
  if ns.ProcRules and auraSpellID and ns.ProcRules.GetUserRulesForAura then
    rules = ns.ProcRules:GetUserRulesForAura(auraSpellID) or {}
  end
  local filter = U.Trim((f.editFilter and f.editFilter:GetText()) or "")
  local filterLower = safeLower(filter)
  if filterLower ~= "" then
    local filtered = {}
    for i = 1, #rules do
      local rule = rules[i]
      local idText = tostring(rule and rule.id or "")
      local nameText = tostring(rule and rule.name or "")
      local desc = (ns.ProcRules and ns.ProcRules.DescribeUserRule and ns.ProcRules:DescribeUserRule(rule)) or ""
      local haystack = safeLower(idText .. " " .. nameText .. " " .. tostring(desc))
      if haystack:find(filterLower, 1, true) then
        filtered[#filtered + 1] = rule
      end
    end
    rules = filtered
  end
  f.ruleRows = rules
  f.ruleButtons = f.ruleButtons or {}

  local rowWidth = math.max(132, math.floor((f.listBaseWidth or 244) - 48))
  for i = 1, #rules do
    local rule = rules[i]
    local btn = f.ruleButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, f.listContent, "BackdropTemplate")
      btn:SetSize(rowWidth, 22)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      self:ApplyListButtonState(btn, "normal")
      btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.text:SetPoint("LEFT", 6, 0)
      btn.text:SetPoint("RIGHT", -10, 0)
      btn.text:SetJustifyH("LEFT")
      btn.text:SetWordWrap(false)
      btn:SetScript("OnEnter", function(selfBtn)
        if selfBtn.ruleID ~= f.selectedRuleID then
          self:ApplyListButtonState(selfBtn, "hover")
        end
      end)
      btn:SetScript("OnLeave", function(selfBtn)
        if selfBtn.ruleID ~= f.selectedRuleID then
          self:ApplyListButtonState(selfBtn, "normal")
        end
      end)
      btn:SetScript("OnMouseDown", function(selfBtn)
        f.selectedRuleID = selfBtn.ruleID
        local model = inferSimpleRuleModel(selfBtn.rule)
        if model then
          self:ApplyRuleFormModel(model)
        else
          info("Unsupported rule format in UI. You can still remove it.")
          if f.editRuleID then
            f.editRuleID:SetText(tostring(selfBtn.ruleID or ""))
          end
        end
        self:RefreshRulesList()
      end)
      f.ruleButtons[i] = btn
    end

    btn.rule = rule
    btn.ruleID = tostring(rule.id or ("rule_" .. tostring(i)))
    btn:SetSize(rowWidth, 22)
    btn:SetPoint("TOPLEFT", 0, -((i - 1) * 24))
    local label = ns.ProcRules:DescribeUserRule(rule)
    local maxChars = math.max(18, math.floor((rowWidth - 12) / 6.5))
    if #label > maxChars then
      label = label:sub(1, maxChars - 3) .. "..."
    end
    btn.text:SetText(label)
    if btn.ruleID == f.selectedRuleID then
      self:ApplyListButtonState(btn, "selected")
    else
      self:ApplyListButtonState(btn, "normal")
    end
    btn:Show()
  end

  for i = #rules + 1, #f.ruleButtons do
    f.ruleButtons[i]:Hide()
  end

  f.listContent:SetSize(math.max(112, rowWidth), math.max(24, #rules * 24))
end

function UI:SaveRuleFromPanel()
  if not ns.ProcRules then
    return
  end
  local model, err = self:CollectRuleFormModel()
  if not model then
    info(err or tr("msg_rule_invalid"))
    return
  end
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  if not auraSpellID then
    info(tr("msg_select_missing"))
    return
  end

  local ok, saveErr
  if model.type == "if" then
    ok, saveErr = ns.ProcRules:AddSimpleIfRuleEx(model)
  else
    ok, saveErr = ns.ProcRules:AddSimpleConsumeRuleEx(model)
  end

  if not ok then
    info(saveErr or tr("msg_rule_invalid"))
    return
  end
  self.rulesFrame.selectedRuleID = model.id
  self:RefreshRulesList()
  ns.EventRouter:RefreshAll()
  info(tr("msg_rule_saved"))
end

function UI:RemoveSelectedRuleFromPanel()
  if not ns.ProcRules or not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  local ruleID = U.Trim((f.editRuleID and f.editRuleID:GetText()) or f.selectedRuleID or "")
  if ruleID == "" then
    info(tr("msg_rule_pick"))
    return
  end
  local removed = ns.ProcRules:RemoveUserRule(ruleID, auraSpellID)
  ns.EventRouter:RefreshAll()
  info(string.format(tr("msg_rule_removed"), removed))
  self:ApplyRuleFormModel(nil)
  self:RefreshRulesList()
end

function UI:ClearRulesFromPanel()
  if not ns.ProcRules then
    return
  end
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  ns.ProcRules:ClearUserRules(auraSpellID)
  ns.EventRouter:RefreshAll()
  info(tr("msg_rule_clear"))
  self:ApplyRuleFormModel(nil)
  self:RefreshRulesList()
end

function UI:RefreshRulesPanelTexts()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  if f.title then
    f.title:SetText(tr("rules_title"))
  end
  if f.lblList then
    f.lblList:SetText(tr("rules_list"))
  end
  if f.lblType then
    f.lblType:SetText(tr("rules_type"))
  end
  if f.lblRuleName then
    f.lblRuleName:SetText(tr("rule_name"))
  end
  if f.lblRuleID then
    f.lblRuleID:SetText(tr("rule_id"))
  end
  if f.lblCastSpell then
    f.lblCastSpell:SetText(tr("rule_cast_spell"))
  end
  if f.lblTalentSpell then
    f.lblTalentSpell:SetText(tr("rule_talent_spell"))
  end
  if f.lblConditionMode then
    f.lblConditionMode:SetText(tr("rule_condition_mode"))
  end
  if f.lblConditionAura then
    f.lblConditionAura:SetText(tr("rule_condition_aura"))
  end
  if f.lblLoadClass then
    f.lblLoadClass:SetText(tr("lbl_load_class"))
  end
  if f.lblLoadSpec then
    f.lblLoadSpec:SetText(tr("lbl_load_spec"))
  end
  if f.cbConditionCombat and f.cbConditionCombat.text then
    f.cbConditionCombat.text:SetText(tr("rule_condition_combat"))
  end
  if f.lblAuraSpell then
    f.lblAuraSpell:SetText(tr("rule_aura_spell"))
  end
  if f.lblDuration then
    f.lblDuration:SetText(tr("rule_duration"))
  end
  if f.csvHint then
    f.csvHint:SetText(tr("rule_csv_hint"))
  end
  if f.btnSave then
    f.btnSave:SetText(tr("rules_save"))
  end
  if f.btnRemove then
    f.btnRemove:SetText(tr("rules_remove"))
  end
  if f.btnClear then
    f.btnClear:SetText(tr("rules_clear"))
  end
  if f.btnClose then
    f.btnClose:SetText(tr("rules_close"))
  end
  if f.btnNew then
    f.btnNew:SetText(tr("rules_new"))
  end
  if f.lblPresets then
    f.lblPresets:SetText(tr("rules_presets"))
  end
  if f.btnPresetShow then
    f.btnPresetShow:SetText(tr("rules_preset_show"))
  end
  if f.btnPresetTalent then
    f.btnPresetTalent:SetText(tr("rules_preset_talent"))
  end
  if f.btnPresetConsume then
    f.btnPresetConsume:SetText(tr("rules_preset_consume"))
  end
  if f.ddType then
    f.ddType:SetOptions({
      { value = "if", label = tr("rule_type_if") },
      { value = "consume", label = tr("rule_type_consume") },
    })
    if not f.ddType:GetValue() then
      f.ddType:SetValue("if")
    end
  end
  if f.ddConditionMode then
    f.ddConditionMode:SetOptions({
      { value = "all", label = tr("rule_condition_and") },
      { value = "any", label = tr("rule_condition_or") },
    })
    if not f.ddConditionMode:GetValue() then
      f.ddConditionMode:SetValue("all")
    end
  end
  if f.rulesSegment then
    local current = f.rulesSegment:GetValue() or f.activeSubTab or "trigger"
    f.rulesSegment:SetOptions({
      { value = "trigger", label = tr("rules_tab_trigger") },
      { value = "conditions", label = tr("rules_tab_conditions") },
      { value = "actions", label = tr("rules_tab_actions") },
    })
    f.rulesSegment:SetValue(current, false)
  end
  self:RefreshRulesTypeVisibility()
end

function UI:BuildRulesPanel()
  if self.rulesFrame then
    return
  end

  local parent = self.right or self.frame
  local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  f:SetPoint("TOPLEFT", parent, "TOPLEFT", 12, -112)
  f:SetSize(math.max(620, math.floor(parent:GetWidth() - 24)), math.max(300, math.floor(parent:GetHeight() - 144)))
  f:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  f:SetBackdropColor(0.05, 0.10, 0.16, 0.36)
  f:SetBackdropBorderColor(0.20, 0.56, 0.82, 0.50)
  f:SetClipsChildren(true)
  f:Hide()

  f.title = C:CreateLabel(f, "", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", 8, -8)

  f.lblList = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblList:SetPoint("TOPLEFT", 8, -30)

  f.editFilter = C:CreateEditBox(f, 204, 20, false)
  f.editFilter:SetPoint("TOPLEFT", 8, -46)
  f.editFilter:SetScript("OnTextChanged", function()
    self:RefreshRulesList()
  end)

  local panelW = f:GetWidth()
  local panelH = f:GetHeight()
  local listW = 244
  local formX = listW + 52
  local formW = math.max(280, panelW - formX - 12)
  local colGap = 14
  local colW = math.max(132, math.floor((formW - colGap) / 2))
  local colA = formX
  local colB = colA + colW + colGap
  local function fitRuleLabel(label, width)
    if not label then
      return
    end
    label:SetWidth(width)
    label:SetJustifyH("LEFT")
    if label.SetWordWrap then
      label:SetWordWrap(false)
    end
  end

  f.listScroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  f.listScroll:SetPoint("TOPLEFT", 10, -72)
  f.listScroll:SetSize(listW, math.max(160, panelH - 118))
  f.listContent = CreateFrame("Frame", nil, f.listScroll)
  f.listContent:SetSize(math.max(112, listW - 42), 10)
  f.listScroll:SetScrollChild(f.listContent)
  f.ruleButtons = {}
  f.ruleRows = {}
  f.listBaseWidth = listW

  f.rulesSegment = C:CreateSegmentedControl(f, math.min(340, formW), 20, {
    { value = "trigger", label = tr("rules_tab_trigger") },
    { value = "conditions", label = tr("rules_tab_conditions") },
    { value = "actions", label = tr("rules_tab_actions") },
  }, function(value)
    self:SetRulesSubTab(value, false)
  end)
  f.rulesSegment:SetPoint("TOPLEFT", colA, -30)

  f.ruleNarrative = C:CreateLabel(f, "", "GameFontDisableSmall")
  f.ruleNarrative:SetPoint("TOPLEFT", colA, -56)
  f.ruleNarrative:SetWidth(formW)
  f.ruleNarrative:SetJustifyH("LEFT")

  f.lblPresets = C:CreateLabel(f, tr("rules_presets"), "GameFontHighlightSmall")
  f.lblPresets:SetPoint("TOPLEFT", colA, -82)

  f.btnPresetShow = C:CreateButton(f, tr("rules_preset_show"), 108, 20, function()
    self:ApplyRulePreset("show")
  end)
  f.btnPresetShow:SetPoint("TOPLEFT", colA, -100)

  f.btnPresetTalent = C:CreateButton(f, tr("rules_preset_talent"), 132, 20, function()
    self:ApplyRulePreset("show_talent")
  end)
  f.btnPresetTalent:SetPoint("LEFT", f.btnPresetShow, "RIGHT", 8, 0)

  f.btnPresetConsume = C:CreateButton(f, tr("rules_preset_consume"), 126, 20, function()
    self:ApplyRulePreset("consume")
  end)
  f.btnPresetConsume:SetPoint("LEFT", f.btnPresetTalent, "RIGHT", 8, 0)

  f.lblType = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblType:SetPoint("TOPLEFT", colA, -84)
  fitRuleLabel(f.lblType, formW)
  f.ddType = C:CreateDropdown(f, formW)
  f.ddType:SetPoint("TOPLEFT", colA - 16, -100)
  f.ddType:SetOnValueChanged(function()
    self:RefreshRulesTypeVisibility()
  end)

  f.lblRuleName = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblRuleName:SetPoint("TOPLEFT", colA, -140)
  fitRuleLabel(f.lblRuleName, formW)
  f.editRuleName = C:CreateEditBox(f, formW, 20, false)
  f.editRuleName:SetPoint("TOPLEFT", colA, -156)

  f.lblRuleID = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblRuleID:SetPoint("TOPLEFT", colA, -140)
  fitRuleLabel(f.lblRuleID, formW)
  f.editRuleID = C:CreateEditBox(f, formW, 20, false)
  f.editRuleID:SetPoint("TOPLEFT", colA, -156)

  f.lblCastSpell = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblCastSpell:SetPoint("TOPLEFT", colA, -188)
  fitRuleLabel(f.lblCastSpell, colW)
  f.editCastSpell = C:CreateEditBox(f, colW, 20, false)
  f.editCastSpell:SetPoint("TOPLEFT", colA, -204)

  f.lblAuraSpell = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblAuraSpell:SetPoint("TOPLEFT", colA, -140)
  fitRuleLabel(f.lblAuraSpell, colW)
  f.editAuraSpell = C:CreateEditBox(f, colW, 20, false)
  f.editAuraSpell:SetPoint("TOPLEFT", colA, -156)

  f.lblTalentSpell = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblTalentSpell:SetPoint("TOPLEFT", colA, -140)
  fitRuleLabel(f.lblTalentSpell, formW)
  f.editTalentSpell = C:CreateEditBox(f, formW, 20, false)
  f.editTalentSpell:SetPoint("TOPLEFT", colA, -156)

  f.lblDuration = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblDuration:SetPoint("TOPLEFT", colA, -188)
  fitRuleLabel(f.lblDuration, colW)
  f.editDuration = C:CreateEditBox(f, colW, 20, false)
  f.editDuration:SetPoint("TOPLEFT", colA, -204)

  f.lblConditionMode = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblConditionMode:SetPoint("TOPLEFT", colA, -92)
  fitRuleLabel(f.lblConditionMode, formW)
  f.ddConditionMode = C:CreateDropdown(f, colW)
  f.ddConditionMode:SetPoint("TOPLEFT", colA - 16, -108)

  f.lblConditionAura = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblConditionAura:SetPoint("TOPLEFT", colA, -188)
  fitRuleLabel(f.lblConditionAura, formW)
  f.editConditionAura = C:CreateEditBox(f, formW, 20, false)
  f.editConditionAura:SetPoint("TOPLEFT", colA, -204)

  f.lblLoadClass = C:CreateLabel(f, tr("lbl_load_class"), "GameFontHighlightSmall")
  f.lblLoadClass:SetPoint("TOPLEFT", colA, -236)
  fitRuleLabel(f.lblLoadClass, colW)
  f.ddLoadClass = C:CreateDropdown(f, colW)
  f.ddLoadClass:SetPoint("TOPLEFT", colA - 16, -252)
  f.ddLoadClass:SetOptions(D:GetLoadClassOptions())

  f.lblLoadSpec = C:CreateLabel(f, tr("lbl_load_spec"), "GameFontHighlightSmall")
  f.lblLoadSpec:SetPoint("TOPLEFT", colB, -236)
  fitRuleLabel(f.lblLoadSpec, colW)
  f.ddLoadSpec = C:CreateDropdown(f, colW)
  f.ddLoadSpec:SetPoint("TOPLEFT", colB - 16, -252)
  f.ddLoadSpec:SetOptions(D:GetLoadSpecMenuOptions(""))
  f.ddLoadSpec:SetValue("")
  f.ddLoadClass:SetOnValueChanged(function()
    self:RefreshRuleLoadSpecDropdown(nil, true)
  end)


  f.cbConditionCombat = C:CreateCheckBox(f, "", function() end)
  f.cbConditionCombat:SetPoint("TOPLEFT", f.editConditionAura, "BOTTOMLEFT", 0, -12)
  if f.cbConditionCombat.text then
    f.cbConditionCombat.text:SetWidth(math.max(160, formW))
  end

  f.csvHint = C:CreateLabel(f, "CSV example: 6343,23922", "GameFontDisableSmall")
  f.csvHint:SetPoint("TOPLEFT", f.cbConditionCombat, "BOTTOMLEFT", 0, -8)
  f.csvHint:SetWidth(formW)
  f.csvHint:SetJustifyH("LEFT")

  f.btnNew = C:CreateButton(f, "", 104, 24, function()
    f.selectedRuleID = nil
    self:ApplyRuleFormModel(nil)
    self:RefreshRulesList()
  end)
  f.btnNew:SetPoint("BOTTOMLEFT", 8, 10)

  f.btnClear = C:CreateButton(f, "", 104, 24, function()
    self:ClearRulesFromPanel()
  end)
  f.btnClear:SetPoint("LEFT", f.btnNew, "RIGHT", 8, 0)

  f.btnSave = C:CreateButton(f, "", 118, 24, function()
    self:SaveRuleFromPanel()
  end)
  f.btnSave:SetPoint("BOTTOMLEFT", colA, 10)

  f.btnRemove = C:CreateButton(f, "", 118, 24, function()
    self:RemoveSelectedRuleFromPanel()
  end)
  f.btnRemove:SetPoint("LEFT", f.btnSave, "RIGHT", 8, 0)

  self.rulesFrame = f
  self:RegisterTabControls("rules", { f })
  self:ApplySkin()
  self:RefreshRulesPanelTexts()
  self:RelayoutRulesPanel()
  self:SetRulesSubTab("trigger", false)
  self:ApplyRuleFormModel(nil)
  self:RefreshRulesList()
end

function UI:OpenRulesPanel()
  self:BuildRulesPanel()
  self:SetWorkspaceMode("editor", true)
  self:RefreshRulesPanelTexts()
  self:RefreshRulesList()
  self:SetRulesSubTab("trigger", false)
  self:SelectTab("rules")
end






