local _, ns = ...
local U = ns.Utils
local D = ns.SettingsData
local S = ns.SoundManager
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

local function parseSoundToken(token)
  token = S:NormalizeToken(token)
  if type(token) == "string" and token:find("^file:") then
    return "file", token:sub(6)
  end
  return token, ""
end

local function hasOption(options, value)
  for i = 1, #options do
    if options[i].value == value then
      return true
    end
  end
  return false
end

local function safeLower(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower()
end

function UI:RefreshGroupDropdown()
  local options = D:GetGroupOptions()
  self.ddGroup:SetOptions(options)
  if #options == 0 then
    self.ddGroup:SetValue(nil)
  elseif not hasOption(options, self.ddGroup:GetValue()) then
    self.ddGroup:SetValue(options[1].value)
  end
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

function UI:RefreshLoadSpecDropdown(selectedSpecID, resetSelection)
  if not self.ddLoadSpec then
    return
  end
  local classToken = (self.ddLoadClass and self.ddLoadClass:GetValue()) or ""
  self.ddLoadSpec:SetOptions(D:GetLoadSpecMenuOptions(classToken))
  if resetSelection then
    self.ddLoadSpec:SetValue("")
    return
  end
  local sid = tonumber(selectedSpecID)
  if sid and sid > 0 then
    self.ddLoadSpec:SetValue(sid)
  else
    self.ddLoadSpec:SetValue("")
  end
end
function UI:RefreshIconCustomVisibility(mode)
  mode = mode or self.ddIconMode:GetValue() or "spell"
  local guided = ns.db and ns.db.options and ns.db.options.uiGuidedMode == true
  local show = (self.activeTab == "display") and (mode == "custom") and (not guided)
  if show then
    self.lblTexture:Show()
    self.editTexture:Show()
    self.textureHelp:Show()
  else
    self.lblTexture:Hide()
    self.editTexture:Hide()
    self.textureHelp:Hide()
  end
end

function UI:BuildAuraRowState(row)
  local item = row and row.item or nil
  local spellID = tonumber(item and item.spellID) or 0
  local issues = {}
  local status = "ok"

  local spellName = ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID) or ""
  if spellName == "" then
    spellName = "Spell " .. tostring(spellID)
  end
  local auraName = U.Trim(tostring(item and item.displayName or ""))
  if auraName == "" then
    auraName = spellName
  end

  local ruleCount = 0
  if ns.ProcRules and ns.ProcRules.GetUserRulesForAura and spellID > 0 then
    local rules = ns.ProcRules:GetUserRulesForAura(spellID) or {}
    ruleCount = #rules
  end

  if ns.db and ns.db.options and ns.db.options.rulesOnlyMode == true and ruleCount <= 0 then
    status = "warn"
    issues[#issues + 1] = tr("row_warn_missing_rule")
  end
  if item and item.iconMode == "custom" and U.Trim(tostring(item.customTexture or "")) == "" then
    status = "warn"
    issues[#issues + 1] = tr("row_warn_missing_texture")
  end
  if item and (not item.groupID or not (ns.db and ns.db.groups and ns.db.groups[item.groupID])) then
    status = "warn"
    issues[#issues + 1] = tr("row_warn_missing_group")
  end

  local texture = nil
  if ns.AuraAPI and ns.AuraAPI.GetDisplayTextureForItem then
    texture = ns.AuraAPI:GetDisplayTextureForItem(item, nil)
  end
  if not texture and ns.AuraAPI and ns.AuraAPI.GetSpellTexture then
    texture = ns.AuraAPI:GetSpellTexture(spellID)
  end
  if not texture then
    texture = 136243
  end

  local unitLabel = tostring(row and row.unit or "player")
  unitLabel = unitLabel:gsub("^%l", string.upper)
  local groupID = tostring(item and item.groupID or "group")
  local groupName = (ns.db and ns.db.groups and ns.db.groups[groupID] and ns.db.groups[groupID].name) or groupID
  local statusText = status == "ok" and tr("row_status_ok") or tr("row_status_warn")
  local statusColor = status == "ok" and "|cff6be39d" or "|cffffaa44"
  local meta = string.format("%s | %s | rules:%d", unitLabel, groupName, ruleCount)

  return {
    spellID = spellID,
    name = auraName,
    meta = meta,
    icon = texture,
    status = status,
    statusText = statusColor .. statusText .. "|r",
    issues = issues,
  }
end

function UI:RebuildAuraList()
  local rows = D:ListEntries(self.editFilter:GetText())
  self.listRows = rows
  local rowWidth = self:GetListRowWidth()
  local rowHeight = 24

  for i = 1, #rows do
    local row = rows[i]
    local view = self:BuildAuraRowState(row)
    local btn = self.listButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, self.listContent, "BackdropTemplate")
      btn:SetSize(rowWidth, rowHeight)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      self:ApplyListButtonState(btn, "normal")
      btn.icon = btn:CreateTexture(nil, "ARTWORK")
      btn.icon:SetSize(18, 18)
      btn.icon:SetPoint("LEFT", 6, 0)
      btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.text:SetPoint("LEFT", btn.icon, "RIGHT", 6, 0)
      btn.text:SetPoint("RIGHT", -92, 0)
      btn.text:SetJustifyH("LEFT")
      btn.text:SetWordWrap(false)
      btn.meta = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      btn.meta:SetPoint("BOTTOMLEFT", btn.icon, "BOTTOMRIGHT", 6, 1)
      btn.meta:SetPoint("BOTTOMRIGHT", -92, 1)
      btn.meta:SetJustifyH("LEFT")
      btn.meta:SetWordWrap(false)
      btn.meta:Hide()
      btn.status = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.status:SetPoint("RIGHT", -10, 0)
      btn.status:SetWidth(80)
      btn.status:SetJustifyH("RIGHT")
      btn:SetScript("OnEnter", function(selfBtn)
        if selfBtn.key ~= self.selectedKey then
          self:ApplyListButtonState(selfBtn, "hover")
        end
        if selfBtn.rowState and selfBtn.rowState.status == "warn" then
          GameTooltip:SetOwner(selfBtn, "ANCHOR_RIGHT")
          GameTooltip:AddLine(selfBtn.rowState.name or "Aura", 1.0, 0.9, 0.2)
          for ii = 1, #(selfBtn.rowState.issues or {}) do
            GameTooltip:AddLine("- " .. tostring(selfBtn.rowState.issues[ii]), 1.0, 0.4, 0.4)
          end
          GameTooltip:Show()
        end
      end)
      btn:SetScript("OnLeave", function(selfBtn)
        if selfBtn.key ~= self.selectedKey then
          self:ApplyListButtonState(selfBtn, "normal")
        end
        GameTooltip:Hide()
      end)
      btn:SetScript("OnMouseDown", function(selfBtn)
        self:SelectAura(selfBtn.key)
      end)
      self.listButtons[i] = btn
    else
      btn:SetSize(rowWidth, rowHeight)
    end

    btn.key = row.key
    btn.rowState = view
    btn:SetPoint("TOPLEFT", 0, -((i - 1) * (rowHeight + 2)))
    local label = view.name .. " (" .. tostring(view.spellID) .. ")"
    local maxChars = math.max(12, math.floor((rowWidth - 116) / 6.7))
    if #label > maxChars then
      label = label:sub(1, maxChars - 3) .. "..."
    end
    btn.text:SetText(label)
    btn.meta:SetText("")
    btn.status:SetText(view.statusText)
    btn.icon:SetTexture(view.icon)

    if row.key == self.selectedKey and self.editorMode == "edit" then
      self:ApplyListButtonState(btn, "selected")
    else
      self:ApplyListButtonState(btn, "normal")
    end

    btn:Show()
  end

  for i = #rows + 1, #self.listButtons do
    self.listButtons[i]:Hide()
  end

  self.listContent:SetSize(rowWidth, math.max(32, #rows * (rowHeight + 2)))
end

function UI:HideAutocomplete()
  if self.autoFrame then
    self.autoFrame:Hide()
  end
  self.autoRows = {}
end

function UI:ApplyAutocompleteRow(row)
  if not row then
    return
  end
  -- Store spellID to avoid locale/name mismatches when resolving.
  self.editSpell:SetText(tostring(row.id))
  self.editSpell:HighlightText()
  self:HideAutocomplete()
end

function UI:RefreshAutocomplete()
  if self.suppressAutocomplete then
    return
  end
  local query = U.Trim(self.editSpell:GetText() or "")
  local numeric = tonumber(query) ~= nil
  if query == "" or ((not numeric) and #query < 2) then
    self:HideAutocomplete()
    return
  end

  local rows = ns.SpellCatalog:Search(query, 8)
  if #rows == 0 then
    self:HideAutocomplete()
    return
  end

  self.autoRows = rows
  local width = 224
  local rowHeight = 18
  self.autoFrame:SetSize(width, (#rows * rowHeight) + 6)

  for i = 1, #rows do
    local row = rows[i]
    local btn = self.autoButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, self.autoFrame)
      btn:SetSize(width - 8, rowHeight)
      btn:SetPoint("TOPLEFT", 4, -((i - 1) * rowHeight) - 3)
      btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.text:SetPoint("LEFT", 2, 0)
      btn.text:SetPoint("RIGHT", -2, 0)
      btn.text:SetJustifyH("LEFT")
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      if ns.UISkin then
        local r, g, b, a = ns.UISkin:GetListRowColor("normal")
        btn.bg:SetColorTexture(r, g, b, a)
      else
        btn.bg:SetColorTexture(0.08, 0.08, 0.08, 0.65)
      end
      btn:SetScript("OnEnter", function(selfBtn)
        if ns.UISkin then
          local r, g, b, a = ns.UISkin:GetListRowColor("hover")
          selfBtn.bg:SetColorTexture(r, g, b, a)
        else
          selfBtn.bg:SetColorTexture(0.2, 0.28, 0.45, 0.8)
        end
      end)
      btn:SetScript("OnLeave", function(selfBtn)
        if ns.UISkin then
          local r, g, b, a = ns.UISkin:GetListRowColor("normal")
          selfBtn.bg:SetColorTexture(r, g, b, a)
        else
          selfBtn.bg:SetColorTexture(0.08, 0.08, 0.08, 0.65)
        end
      end)
      btn:SetScript("OnMouseDown", function(selfBtn)
        self:ApplyAutocompleteRow(selfBtn.row)
      end)
      self.autoButtons[i] = btn
    end

    btn.row = row
    btn.text:SetText(("%s (%d)"):format(row.name or ("Spell " .. tostring(row.id)), row.id or 0))
    btn:Show()
  end

  for i = #rows + 1, #self.autoButtons do
    self.autoButtons[i]:Hide()
  end

  self.autoFrame:Show()
end

function UI:ReadSoundRow(state, model)
  local row = self.soundControls[state]
  local token = row.dropdown:GetValue()
  local path = U.Trim(row.pathEdit:GetText() or "")
  local field = "soundOn" .. state:gsub("^%l", string.upper)

  if token == "file" then
    if path == "" then
      return nil, string.format(tr("msg_audio_path_missing"), state)
    end
    model[field] = "file:" .. path
    return true
  end

  model[field] = token or "default"
  return true
end

function UI:CollectFormModel()
  local barTextureValue = U.Trim((self.editBarTexture and self.editBarTexture:GetText()) or "")
  if self.ddBarTexturePreset then
    local presetValue = self.ddBarTexturePreset:GetValue()
    if type(presetValue) == "string" and presetValue ~= "" and presetValue ~= "custom" then
      barTextureValue = presetValue
    end
  end
  local loadSpecValue = self.ddLoadSpec and self.ddLoadSpec:GetValue() or nil
  if loadSpecValue == nil and self.modelSnapshot then
    loadSpecValue = firstSpecID(self.modelSnapshot.loadSpecIDs) or ""
  end

  local model = {
    spellInput = U.Trim(self.editSpell:GetText() or ""),
    displayName = U.Trim(self.editAuraName:GetText() or ""),
    unit = self.ddUnit:GetValue() or "player",
    groupID = self.ddGroup:GetValue() or "",
    loadClassToken = (self.ddLoadClass and self.ddLoadClass:GetValue()) or "",
    loadSpecIDs = loadSpecValue,
    instanceUID = (self.modelSnapshot and self.modelSnapshot.instanceUID) or "",
    onlyMine = self.cbOnlyMine:GetChecked() == true,
    alert = self.cbAlert:GetChecked() == true,
    iconMode = self.ddIconMode:GetValue() or "spell",
    customTexture = U.Trim(self.editTexture:GetText() or ""),
    barTexture = barTextureValue,
    timerVisual = self.ddTimerVisual:GetValue() or "icon",
    customText = U.Trim(self.editCustomText:GetText() or ""),
    resourceConditionEnabled = self.cbResourceCondition:GetChecked() == true,
    resourceMinPct = tonumber(U.Trim(self.editResourceMin:GetText() or "")) or 0,
    resourceMaxPct = tonumber(U.Trim(self.editResourceMax:GetText() or "")) or 100,
    lowTimeThreshold = tonumber(U.Trim(self.editLowTimeAura:GetText() or "")) or 0,
    timerAnchor = self.ddTimerAnchor:GetValue() or "BOTTOM",
    timerOffsetX = tonumber(U.Trim(self.editTimerOffsetX:GetText() or "")) or 0,
    timerOffsetY = tonumber(U.Trim(self.editTimerOffsetY:GetText() or "")) or -1,
    customTextAnchor = self.ddCustomAnchor:GetValue() or "TOP",
    customTextOffsetX = tonumber(U.Trim(self.editCustomOffsetX:GetText() or "")) or 0,
    customTextOffsetY = tonumber(U.Trim(self.editCustomOffsetY:GetText() or "")) or 2,
  }

  local customGroupID = safeLower(U.Trim(self.editGroupCustom:GetText() or ""))
  if customGroupID ~= "" then
    model.groupID = customGroupID
  end

  local okGain, errGain = self:ReadSoundRow("gain", model)
  if not okGain then
    return nil, errGain
  end

  local okLow, errLow = self:ReadSoundRow("low", model)
  if not okLow then
    return nil, errLow
  end

  local okExpire, errExpire = self:ReadSoundRow("expire", model)
  if not okExpire then
    return nil, errExpire
  end

  if model.spellInput == "" then
    return nil, tr("msg_spell_missing")
  end

  return model
end

function UI:ApplyModelToForm(model)
  model = model or D:BuildDefaultCreateModel()

  self.suppressAutocomplete = true
  self.editSpell:SetText(tostring(model.spellInput or model.spellID or ""))
  self.editAuraName:SetText(tostring(model.displayName or ""))
  self.ddUnit:SetValue(D:NormalizeUnit(model.unit))

  self:RefreshGroupDropdown()
  local options = D:GetGroupOptions()
  local groupID = model.groupID or ""
  if hasOption(options, groupID) then
    self.ddGroup:SetValue(groupID)
    self.editGroupCustom:SetText("")
  else
    if #options > 0 then
      self.ddGroup:SetValue(options[1].value)
    end
    self.editGroupCustom:SetText(groupID)
  end

  self.cbOnlyMine:SetChecked(model.onlyMine == true)
  self.cbAlert:SetChecked(model.alert ~= false)
  self.ddIconMode:SetValue(model.iconMode == "custom" and "custom" or "spell")
  self.editTexture:SetText(model.customTexture or "")
  self.ddTimerVisual:SetValue(tostring(model.timerVisual or "icon"))
  if self.editBarTexture then
    self.editBarTexture:SetText(tostring(model.barTexture or ""))
  end
  self:SyncBarTexturePresetFromPath(model.barTexture or "")
  self:RefreshIconCustomVisibility(model.iconMode)
  self:RefreshBarTextureVisibility(model.timerVisual)
  self.editCustomText:SetText(tostring(model.customText or ""))
  self.cbResourceCondition:SetChecked(model.resourceConditionEnabled == true)
  self.editResourceMin:SetText(tostring(model.resourceMinPct or 0))
  self.editResourceMax:SetText(tostring(model.resourceMaxPct or 100))
  local lowTimeValue = tonumber(model.lowTimeThreshold) or 0
  self.editLowTimeAura:SetText(lowTimeValue > 0 and tostring(lowTimeValue) or "")
  if self.ddLoadClass then
    self.ddLoadClass:SetValue(tostring(model.loadClassToken or ""))
  end
  self:RefreshLoadSpecDropdown(firstSpecID(model.loadSpecIDs), false)
  self.ddTimerAnchor:SetValue(tostring(model.timerAnchor or "BOTTOM"))
  self.editTimerOffsetX:SetText(tostring(model.timerOffsetX or 0))
  self.editTimerOffsetY:SetText(tostring(model.timerOffsetY or -1))
  self.ddCustomAnchor:SetValue(tostring(model.customTextAnchor or "TOP"))
  self.editCustomOffsetX:SetText(tostring(model.customTextOffsetX or 0))
  self.editCustomOffsetY:SetText(tostring(model.customTextOffsetY or 2))

  for _, state in ipairs({ "gain", "low", "expire" }) do
    local token = model["soundOn" .. state:gsub("^%l", string.upper)] or "default"
    local mode, path = parseSoundToken(token)
    local row = self.soundControls[state]
    row.dropdown:SetValue(mode)
    row.pathEdit:SetText(path or "")
  end
  self.suppressAutocomplete = false
  self:HideAutocomplete()
  self:SyncRuleAuraBinding()
  self:RefreshEditorHealth()
end

function UI:SetEditorTitle(text)
  self.editorTitle:SetText(text or "Aura")
end

function UI:RefreshEditorHealth()
  if not self.editorHealth or not self.editorGuide then
    return
  end

  local spellInput = U.Trim((self.editSpell and self.editSpell:GetText()) or "")
  local spellID = tonumber(spellInput) or nil
  local inEdit = self.editorMode == "edit" and self.selectedKey ~= nil
  local hasSpell = spellInput ~= ""
  local rulesOnly = ns.db and ns.db.options and ns.db.options.rulesOnlyMode == true
  local ruleCount = 0

  if spellID and spellID > 0 and ns.ProcRules and ns.ProcRules.GetUserRulesForAura then
    local rules = ns.ProcRules:GetUserRulesForAura(spellID) or {}
    ruleCount = #rules
  end

  local ready = true
  local guide = tr("editor_health_ready")
  if not hasSpell then
    ready = false
    guide = tr("editor_health_spell_missing")
  elseif rulesOnly and ruleCount <= 0 then
    ready = false
    guide = tr("editor_health_rule_missing")
  end

  local modeLabel = inEdit and tr("editor_health_mode_edit") or tr("editor_health_mode_create")
  local healthLabel = ready and ("|cff6be39d" .. tr("row_status_ok") .. "|r") or ("|cffffaa44" .. tr("row_status_warn") .. "|r")
  self.editorHealth:SetText(string.format("%s  |  %s", modeLabel, healthLabel))
  self.editorGuide:SetText(guide)
end

function UI:EnterCreateMode()
  self.editorMode = "create"
  self.selectedKey = nil
  if ns.state then
    ns.state.selectedAura = nil
  end
  self.modelSnapshot = D:BuildDefaultCreateModel()
  self:SetEditorTitle(tr("editor_new"))
  self:ApplyModelToForm(self.modelSnapshot)
  self:RebuildAuraList()
  self:RefreshRulesList()
  self:HideAutocomplete()
  self:RefreshEditorHealth()
end

function UI:SelectAura(key)
  local entry = D:ResolveEntry(key)
  if not entry then
    self:EnterCreateMode()
    return
  end

  self.editorMode = "edit"
  self.selectedKey = key
  self.modelSnapshot = D:BuildEditableModel(entry)
  if ns.state and self.modelSnapshot then
    ns.state.selectedAura = {
      key = key,
      unit = entry.unit,
      spellID = tonumber(self.modelSnapshot.spellID) or 0,
      instanceUID = tostring(self.modelSnapshot.instanceUID or ""),
    }
  end
  local titleName = U.Trim(self.modelSnapshot.displayName or "")
  if titleName == "" then
    titleName = (self.modelSnapshot.spellName ~= "" and self.modelSnapshot.spellName or tostring(self.modelSnapshot.spellID))
  end
  self:SetEditorTitle(string.format(tr("editor_edit"), titleName))
  self:ApplyModelToForm(self.modelSnapshot)
  if ns.db and ns.db.options and ns.db.options.uiWorkspace == "auras" then
    self:SetWorkspaceMode("editor", true)
  end
  self:RebuildAuraList()
  self:RefreshRulesList()
  self:HideAutocomplete()
  self:RefreshEditorHealth()
end

function UI:SaveCurrentAura()
  local model, err = self:CollectFormModel()
  if not model then
    info(err)
    return
  end

  -- One form handles both create and edit flows to keep behavior consistent.
  if self.editorMode == "create" then
    local key, addErr = D:AddEntry(model)
    if not key then
      info(addErr or tr("msg_add_fail"))
      return
    end
    info(tr("msg_add_ok"))
    self:SelectAura(key)
    return
  end

  if not self.selectedKey then
    info(tr("msg_select_missing"))
    return
  end

  local newKey, saveErr = D:UpdateEntry(self.selectedKey, model)
  if not newKey then
    info(saveErr or tr("msg_update_fail"))
    return
  end
  info(tr("msg_update_ok"))
  self:SelectAura(newKey)
  self:RefreshEditorHealth()
end

function UI:ResetCurrentForm()
  if self.editorMode == "edit" and self.selectedKey then
    self:SelectAura(self.selectedKey)
    return
  end
  self:EnterCreateMode()
  self:RefreshEditorHealth()
end

function UI:DeleteSelected()
  if not self.selectedKey then
    info(tr("msg_remove_pick"))
    return
  end
  local removed = D:DeleteEntry(self.selectedKey)
  if removed > 0 then
    info(tr("msg_remove_ok"))
  end
  self:EnterCreateMode()
  self:RefreshEditorHealth()
end

function UI:DuplicateSelected()
  if not self.selectedKey then
    info(tr("msg_duplicate_pick"))
    return
  end

  local entry = D:ResolveEntry(self.selectedKey)
  if not entry then
    info(tr("msg_duplicate_missing"))
    return
  end

  local model = D:BuildEditableModel(entry)
  model.spellInput = model.spellID
  local key, err = D:AddEntry(model)
  if not key then
    info(err or tr("msg_duplicate_fail"))
    return
  end
  info(tr("msg_duplicate_ok"))
  self:SelectAura(key)
  self:RefreshEditorHealth()
end

function UI:Refresh()
  if not self.frame or not self.frame:IsShown() then
    return
  end
  self:EnsureUXOptionsDefaults()
  self:ApplySkin()
  self:RefreshQuickState()
  self:ApplyWorkspaceLayout()
  self:RefreshGroupDropdown()
  self:RebuildAuraList()

  if self.editorMode == "edit" and self.selectedKey then
    local entry = D:ResolveEntry(self.selectedKey)
    if entry then
      self:SelectAura(self.selectedKey)
      return
    end
  end

  if self.editorMode ~= "edit" then
    self:ApplyModelToForm(self.modelSnapshot)
  else
    self:EnterCreateMode()
  end
  self:ApplyGuidedMode()
end

function UI:Open()
  self:BuildFrame()

  if ns.Localization then
    ns.Localization:EnsureOptionsDefaults(ns.db.options)
  end
  if ns.UISkin then
    ns.UISkin:EnsureOptionsDefaults(ns.db.options)
  end
  self:EnsureUXOptionsDefaults()
  -- Keep default editing experience stable and predictable.
  ns.db.options.uiWorkspace = "split"
  -- Le opzioni audio sono tenute coerenti qui prima di leggere/scrivere campi UI.
  S:EnsureOptionsDefaults(ns.db.options)
  self:ApplyLocalization()
  self:ApplySkin()

  self.frame:Show()
  self:RefreshQuickState()
  self:ApplyWorkspaceLayout()
  self:RefreshGroupDropdown()
  self:RebuildAuraList()

  if self.selectedKey and D:ResolveEntry(self.selectedKey) then
    self:SelectAura(self.selectedKey)
    return
  end

  if #self.listRows > 0 then
    self:SelectAura(self.listRows[1].key)
  else
    self:EnterCreateMode()
  end
  self:ApplyGuidedMode()
end

function UI:Close()
  if self.frame then
    self:HideAutocomplete()
    self.frame:Hide()
  end
  if ns.state then
    ns.state.selectedAura = nil
  end
end


