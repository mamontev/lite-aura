local _, ns = ...
local U = ns.Utils
local C = ns.UIComponents
local D = ns.SettingsData
local S = ns.SoundManager
local L = ns.Localization

ns.SettingsUI = ns.SettingsUI or {}
local UI = ns.SettingsUI

local channelOptions = {
  { value = "Master", label = "Master" },
  { value = "SFX", label = "SFX" },
  { value = "Music", label = "Music" },
  { value = "Ambience", label = "Ambience" },
  { value = "Dialog", label = "Dialog" },
}

local textAnchorOptions = {
  { value = "TOP", label = "TOP" },
  { value = "BOTTOM", label = "BOTTOM" },
  { value = "LEFT", label = "LEFT" },
  { value = "RIGHT", label = "RIGHT" },
  { value = "CENTER", label = "CENTER" },
  { value = "TOPLEFT", label = "TOPLEFT" },
  { value = "TOPRIGHT", label = "TOPRIGHT" },
  { value = "BOTTOMLEFT", label = "BOTTOMLEFT" },
  { value = "BOTTOMRIGHT", label = "BOTTOMRIGHT" },
}

local timerVisualOptions = {
  { value = "icon", label = "Icon" },
  { value = "bar", label = "Icon + Bar" },
}

local function safeLower(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower()
end

local function hasOption(options, value)
  for i = 1, #options do
    if options[i].value == value then
      return true
    end
  end
  return false
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

local function buildSoundOptions()
  local opts = S:GetDropdownOptions(true)
  opts[#opts + 1] = {
    value = "file",
    label = "File Path (aura)",
  }
  return opts
end

local function buildBarTextureOptions()
  local defaultLabel = (L and L.T and L:T("opt_default_texture")) or "Default"
  local customLabel = (L and L.T and L:T("opt_custom_path")) or "Custom Path"
  local opts = {
    { value = "", label = defaultLabel },
  }
  if ns.Media and ns.Media.GetStatusbarOptions then
    local lsmOptions = ns.Media:GetStatusbarOptions()
    for i = 1, #lsmOptions do
      opts[#opts + 1] = lsmOptions[i]
    end
  end
  opts[#opts + 1] = {
    value = "custom",
    label = customLabel,
  }
  return opts
end

function UI:GetBarTextureOptions()
  return buildBarTextureOptions()
end

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

local validWorkspaceModes = {
  auras = true,
  editor = true,
  split = true,
}

local function parseSoundToken(token)
  token = S:NormalizeToken(token)
  if type(token) == "string" and token:find("^file:") then
    return "file", token:sub(6)
  end
  return token, ""
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
    castSpellIDs = {},
    conditionMode = (tostring(rule.conditionMode or "all"):lower() == "any") and "any" or "all",
    talentSpellIDs = {},
    requiredAuraSpellIDs = {},
    requireInCombat = false,
    auraSpellID = nil,
    duration = 0,
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

  return model
end

function UI:GetActiveRuleAuraSpellID()
  if self.editorMode == "edit" and self.modelSnapshot then
    local sid = tonumber(self.modelSnapshot.spellID or self.modelSnapshot.spellInput)
    if sid and sid > 0 then
      return sid
    end
  end

  if self.editSpell then
    local text = U.Trim(self.editSpell:GetText() or "")
    local sid = tonumber(text)
    if sid and sid > 0 then
      return sid
    end
  end
  return nil
end

function UI:SyncRuleAuraBinding()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local auraSpellID = self:GetActiveRuleAuraSpellID()
  if f.editAuraSpell then
    f.editAuraSpell:SetText(auraSpellID and tostring(auraSpellID) or "")
    f.editAuraSpell:SetEnabled(false)
    if f.editAuraSpell.EnableMouse then
      f.editAuraSpell:EnableMouse(false)
    end
  end
end

function UI:EnsureUXOptionsDefaults()
  if not ns.db or not ns.db.options then
    return
  end
  local options = ns.db.options
  if options.uiGuidedMode == nil then
    options.uiGuidedMode = true
  else
    options.uiGuidedMode = options.uiGuidedMode == true
  end
  if options.rulesOnlyMode == nil then
    options.rulesOnlyMode = true
  else
    options.rulesOnlyMode = options.rulesOnlyMode == true
  end
  local workspace = tostring(options.uiWorkspace or "split")
  if not validWorkspaceModes[workspace] then
    workspace = "split"
  end
  options.uiWorkspace = workspace
end

function UI:GetListRowWidth()
  local baseWidth = (self.left and self.left:GetWidth()) or 348
  return math.max(240, math.floor(baseWidth - 60))
end

function UI:UpdateHintText()
  if not self.hintText then
    return
  end
  local mode = (ns.db and ns.db.options and ns.db.options.uiWorkspace) or "split"
  local guided = ns.db and ns.db.options and ns.db.options.uiGuidedMode == true

  local workflowText = tr("hint_split")
  if mode == "auras" then
    workflowText = tr("hint_library")
  elseif mode == "editor" then
    workflowText = tr("hint_editor")
  end

  local policyText = guided and tr("hint_guided") or tr("hint_advanced")
  self.hintText:SetText(workflowText .. "  " .. policyText)
end

function UI:GetQuickHeight()
  if self.quick then
    return self.quick:GetHeight()
  end
  return 122
end

function UI:ApplyWorkspaceLayout()
  if not self.frame or not self.left or not self.right then
    return
  end

  local contentTopY = -50 - self:GetQuickHeight() - 12
  local contentHeight = math.max(360, math.floor(self.frame:GetHeight() + contentTopY - 16))
  local mode = (ns.db and ns.db.options and ns.db.options.uiWorkspace) or "split"
  if not validWorkspaceModes[mode] then
    mode = "split"
  end
  local fullWidth = math.floor(self.frame:GetWidth() - 32)

  self.left:ClearAllPoints()
  self.right:ClearAllPoints()
  if mode == "auras" then
    self.left:SetPoint("TOPLEFT", 16, contentTopY)
    self.left:SetSize(fullWidth, contentHeight)
    self.left:Show()
    self.right:Hide()
  elseif mode == "editor" then
    self.right:SetPoint("TOPLEFT", 16, contentTopY)
    self.right:SetSize(fullWidth, contentHeight)
    self.right:Show()
    self.left:Hide()
  else
    self.left:SetPoint("TOPLEFT", 16, contentTopY)
    self.left:SetSize(348, contentHeight)
    self.left:Show()
    self.right:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, contentTopY)
    self.right:SetSize(686, contentHeight)
    self.right:Show()
  end

  local listRowWidth = self:GetListRowWidth()
  self.editFilter:SetWidth(math.max(190, listRowWidth - 68))
  self.btnClearFilter:ClearAllPoints()
  self.btnClearFilter:SetPoint("LEFT", self.editFilter, "RIGHT", 8, 0)
  self.listContent:SetWidth(listRowWidth)
  for i = 1, #(self.listButtons or {}) do
    local btn = self.listButtons[i]
    if btn then
      btn:SetWidth(listRowWidth)
    end
  end

  local rightBodyWidth = math.floor(self.right:GetWidth() - 36)
  self.editTexture:SetWidth(math.max(300, rightBodyWidth))
  if self.editBarTexture then
    self.editBarTexture:SetWidth(math.max(180, math.floor(self.right:GetWidth() - 452)))
  end
  self.editCustomText:SetWidth(math.max(300, rightBodyWidth))

  for _, state in ipairs({ "gain", "low", "expire" }) do
    local row = self.soundControls and self.soundControls[state]
    if row and row.pathEdit and row.test then
      local pathWidth = math.max(180, math.floor(self.right:GetWidth() - 300))
      row.pathEdit:SetWidth(pathWidth)
      row.test:ClearAllPoints()
      row.test:SetPoint("LEFT", row.pathEdit, "RIGHT", 8, 0)
    end
  end

  if self.rulesFrame then
    local f = self.rulesFrame
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", self.right, "TOPLEFT", 12, -112)
    f:SetSize(math.max(620, math.floor(self.right:GetWidth() - 24)), math.max(300, math.floor(self.right:GetHeight() - 144)))
    if f.listScroll then
      f.listScroll:SetPoint("TOPLEFT", 10, -46)
      f.listScroll:SetSize(f.listBaseWidth or 228, math.max(160, f:GetHeight() - 92))
    end
    if f.listContent then
      f.listContent:SetSize(math.max(128, (f.listBaseWidth or 228) - 28), math.max(24, #(f.ruleRows or {}) * 24))
    end
    self:RefreshRulesList()
  end

  self:UpdateHintText()
end

function UI:SetWorkspaceMode(mode, skipRefresh)
  if not validWorkspaceModes[mode] then
    mode = "split"
  end
  if ns.db and ns.db.options then
    ns.db.options.uiWorkspace = mode
  end
  if self.workspaceSegment then
    self.workspaceSegment:SetValue(mode, false)
  end
  self:ApplyWorkspaceLayout()
  if not skipRefresh then
    self:RebuildAuraList()
  end
end

function UI:ApplyGuidedMode()
  if not self.frame then
    return
  end
  local guided = ns.db and ns.db.options and ns.db.options.uiGuidedMode == true

  local map = self.advancedControlsByTab or {}
  for _, controls in pairs(map) do
    for i = 1, #controls do
      if controls[i] then
        controls[i]:Hide()
      end
    end
  end

  if not guided then
    local activeControls = map[self.activeTab or "general"] or {}
    for i = 1, #activeControls do
      if activeControls[i] then
        activeControls[i]:Show()
      end
    end
  end

  if self.soundControls then
    for _, state in ipairs({ "gain", "low", "expire" }) do
      local row = self.soundControls[state]
      if row and row.pathEdit then
        local showPath = (not guided) and (self.activeTab == "sounds")
        if showPath then
          row.pathEdit:Show()
        else
          row.pathEdit:Hide()
        end
      end
    end
  end

  self:RefreshBarTextureVisibility(self.ddTimerVisual and self.ddTimerVisual:GetValue() or "icon")
  self:UpdateHintText()
end

function UI:ApplyListButtonState(btn, state)
  if not btn or not btn.bg then
    return
  end
  if ns.UISkin then
    local r, g, b, a = ns.UISkin:GetListRowColor(state)
    btn.bg:SetColorTexture(r, g, b, a)
    return
  end

  if state == "selected" then
    btn.bg:SetColorTexture(0.2, 0.35, 0.65, 0.65)
  elseif state == "hover" then
    btn.bg:SetColorTexture(0.15, 0.15, 0.15, 0.5)
  else
    btn.bg:SetColorTexture(0, 0, 0, 0.35)
  end
end

function UI:ApplySkin()
  if ns.UISkin and ns.db and ns.db.options then
    ns.UISkin:EnsureOptionsDefaults(ns.db.options)
  end
  if not ns.UISkin then
    return
  end

  if self.frame then
    ns.UISkin:ApplyWindow(self.frame)
  end
  if self.quick then
    ns.UISkin:ApplySection(self.quick)
  end
  if self.left then
    ns.UISkin:ApplySection(self.left)
  end
  if self.right then
    ns.UISkin:ApplySection(self.right)
  end

  if self.autoFrame then
    ns.UISkin:ApplySection(self.autoFrame)
  end
  if self.localizationFrame then
    ns.UISkin:ApplyWindow(self.localizationFrame)
  end
  if self.globalOptionsFrame then
    ns.UISkin:ApplyWindow(self.globalOptionsFrame)
  end

  if self.divA and self.divB then
    local p = ns.UISkin:GetPalette()
    local r = p.sectionAccent[1]
    local g = p.sectionAccent[2]
    local b = p.sectionAccent[3]
    self.divA:SetColorTexture(r, g, b, 0.35)
    self.divB:SetColorTexture(r, g, b, 0.35)
  end

  local buttons = {
    self.btnLock, self.btnEdit, self.btnRefresh, self.btnLocalization, self.btnRules,
    self.btnGlobalOptions,
    self.btnTabGeneral, self.btnTabDisplay, self.btnTabSounds, self.btnTabRules,
    self.btnClearFilter, self.btnNewAura, self.btnDuplicate, self.btnDelete,
    self.btnSave, self.btnReset, self.btnOpenOptions,
    self.btnGlobalClose,
  }
  if self.workspaceSegment and self.workspaceSegment.buttons then
    for i = 1, #self.workspaceSegment.buttons do
      buttons[#buttons + 1] = self.workspaceSegment.buttons[i]
    end
  end
  for i = 1, #buttons do
    if buttons[i] then
      ns.UISkin:ApplyButton(buttons[i])
    end
  end

  local edits = {
    self.editThreshold, self.editFilter, self.editSpell, self.editAuraName,
    self.editGroupCustom, self.editLowTimeAura, self.editTexture, self.editBarTexture, self.editCustomText, self.editResourceMin,
    self.editResourceMax, self.editTimerOffsetX, self.editTimerOffsetY,
    self.editCustomOffsetX, self.editCustomOffsetY,
  }
  for i = 1, #edits do
    if edits[i] then
      ns.UISkin:ApplyEditBox(edits[i])
    end
  end

  local drops = {
    self.ddChannel, self.ddUnit, self.ddGroup, self.ddIconMode, self.ddTimerVisual,
    self.ddBarTexturePreset, self.ddTimerAnchor, self.ddCustomAnchor,
  }
  for i = 1, #drops do
    if drops[i] then
      ns.UISkin:ApplyDropdown(drops[i])
    end
  end

  if self.soundControls then
    for _, state in ipairs({ "gain", "low", "expire" }) do
      local row = self.soundControls[state]
      if row then
        if row.dropdown then
          ns.UISkin:ApplyDropdown(row.dropdown)
        end
        if row.pathEdit then
          ns.UISkin:ApplyEditBox(row.pathEdit)
        end
        if row.test then
          ns.UISkin:ApplyButton(row.test)
        end
      end
    end
  end

  if self.localizationFrame then
    local f = self.localizationFrame
    if f.ddLanguage then
      ns.UISkin:ApplyDropdown(f.ddLanguage)
    end
    if f.ddTheme then
      ns.UISkin:ApplyDropdown(f.ddTheme)
    end
    if f.editTexture then
      ns.UISkin:ApplyEditBox(f.editTexture)
    end
    if f.btnApply then
      ns.UISkin:ApplyButton(f.btnApply)
    end
    if f.btnClose then
      ns.UISkin:ApplyButton(f.btnClose)
    end
    if f.rulesSegment and f.rulesSegment.buttons then
      for i = 1, #f.rulesSegment.buttons do
        ns.UISkin:ApplyButton(f.rulesSegment.buttons[i])
      end
    end
  end

  if self.rulesFrame then
    local f = self.rulesFrame
    ns.UISkin:ApplySection(f)
    if f.ddType then
      ns.UISkin:ApplyDropdown(f.ddType)
    end
    if f.ddConditionMode then
      ns.UISkin:ApplyDropdown(f.ddConditionMode)
    end
    if f.editRuleID then
      ns.UISkin:ApplyEditBox(f.editRuleID)
    end
    if f.editCastSpell then
      ns.UISkin:ApplyEditBox(f.editCastSpell)
    end
    if f.editTalentSpell then
      ns.UISkin:ApplyEditBox(f.editTalentSpell)
    end
    if f.editConditionAura then
      ns.UISkin:ApplyEditBox(f.editConditionAura)
    end
    if f.editAuraSpell then
      ns.UISkin:ApplyEditBox(f.editAuraSpell)
    end
    if f.editDuration then
      ns.UISkin:ApplyEditBox(f.editDuration)
    end
    if f.btnSave then
      ns.UISkin:ApplyButton(f.btnSave)
    end
    if f.btnRemove then
      ns.UISkin:ApplyButton(f.btnRemove)
    end
    if f.btnClear then
      ns.UISkin:ApplyButton(f.btnClear)
    end
    if f.btnNew then
      ns.UISkin:ApplyButton(f.btnNew)
    end
    if f.btnClose then
      ns.UISkin:ApplyButton(f.btnClose)
    end
  end

  if self.listButtons then
    for i = 1, #self.listButtons do
      local btn = self.listButtons[i]
      if btn and btn.key then
        local selected = btn.key == self.selectedKey and self.editorMode == "edit"
        self:ApplyListButtonState(btn, selected and "selected" or "normal")
      end
    end
  end
end

function UI:RegisterTabControl(tabKey, control)
  if not control then
    return
  end
  self.tabControls = self.tabControls or {
    general = {},
    display = {},
    sounds = {},
  }
  self.tabControls[tabKey] = self.tabControls[tabKey] or {}
  self.tabControls[tabKey][#self.tabControls[tabKey] + 1] = control
end

function UI:RegisterTabControls(tabKey, controls)
  for i = 1, #(controls or {}) do
    self:RegisterTabControl(tabKey, controls[i])
  end
end

local function setControlVisible(control, visible)
  if not control then
    return
  end
  if visible then
    control:Show()
  else
    control:Hide()
  end
end

function UI:RefreshTabButtons()
  if not self.tabButtons then
    return
  end
  for key, button in pairs(self.tabButtons) do
    if button and button.Disable and button.Enable then
      if key == self.activeTab then
        button:Disable()
      else
        button:Enable()
      end
    end
  end
end

function UI:SelectTab(tabKey)
  if tabKey ~= "general" and tabKey ~= "display" and tabKey ~= "sounds" and tabKey ~= "rules" then
    tabKey = "general"
  end
  self.activeTab = tabKey

  if self.tabControls then
    for key, controls in pairs(self.tabControls) do
      local show = key == tabKey
      for i = 1, #controls do
        setControlVisible(controls[i], show)
      end
    end
  end

  self:RefreshIconCustomVisibility(self.ddIconMode and self.ddIconMode:GetValue() or "spell")
  self:RefreshBarTextureVisibility(self.ddTimerVisual and self.ddTimerVisual:GetValue() or "icon")

  if tabKey ~= "general" then
    self:HideAutocomplete()
  end
  local showAuraEditorButtons = tabKey ~= "rules"
  setControlVisible(self.btnSave, showAuraEditorButtons)
  setControlVisible(self.btnReset, showAuraEditorButtons)
  setControlVisible(self.btnOpenOptions, showAuraEditorButtons)
  self:RefreshTabButtons()
  self:ApplyGuidedMode()
  self:UpdateHintText()
end

function UI:BuildGlobalOptionsPanel()
  if self.globalOptionsFrame or not self.frame then
    return
  end

  local f = CreateFrame("Frame", "AuraLiteGlobalOptionsFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(500, 330)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if ns.UISkin then
    ns.UISkin:ApplyWindow(f)
  end
  if f.TitleText then
    f.TitleText:SetText(tr("global_title"))
  end

  self.cbCompact = C:CreateCheckBox(f, tr("lbl_compact"), function(checked)
    ns.db.options.compactMode = checked == true
    ns.EventRouter:RefreshAll()
  end)
  self.cbCompact:SetPoint("TOPLEFT", 16, -40)

  self.cbSource = C:CreateCheckBox(f, tr("lbl_show_source"), function(checked)
    ns.db.options.showSource = checked == true
    ns.EventRouter:RefreshAll()
  end)
  self.cbSource:SetPoint("TOPLEFT", 16, -68)

  self.cbSounds = C:CreateCheckBox(f, tr("lbl_enable_sounds"), function(checked)
    ns.db.options.soundEnabled = checked == true
  end)
  self.cbSounds:SetPoint("TOPLEFT", 16, -96)

  self.cbDebug = C:CreateCheckBox(f, tr("lbl_debug_chat"), function(checked)
    ns.Debug:SetEnabled(checked == true)
  end)
  self.cbDebug:SetPoint("TOPLEFT", 16, -124)

  self.cbRulesOnly = C:CreateCheckBox(f, tr("lbl_rules_only"), function(checked)
    ns.db.options.rulesOnlyMode = checked == true
    if ns.ProcRules and ns.ProcRules.RefreshContext then
      ns.ProcRules:RefreshContext()
    end
    ns.EventRouter:RefreshAll()
  end)
  self.cbRulesOnly:SetPoint("TOPLEFT", 16, -152)

  self.lblChannel = C:CreateLabel(f, tr("lbl_channel"), "GameFontHighlightSmall")
  self.lblChannel:SetPoint("TOPLEFT", 282, -40)
  self.ddChannel = C:CreateDropdown(f, 130)
  self.ddChannel:SetPoint("TOPLEFT", 266, -54)
  self.ddChannel:SetOptions(channelOptions)
  self.ddChannel:SetOnValueChanged(function(value)
    if hasOption(channelOptions, value) then
      ns.db.options.soundChannel = value
    end
  end)

  self.lblThreshold = C:CreateLabel(f, tr("lbl_low_time"), "GameFontHighlightSmall")
  self.lblThreshold:SetPoint("TOPLEFT", 282, -98)
  self.editThreshold = C:CreateEditBox(f, 64, 22, false)
  self.editThreshold:SetPoint("TOPLEFT", 282, -114)
  self.editThreshold:SetNumeric(false)
  self.editThreshold:SetScript("OnEditFocusLost", function(box)
    local raw = U.Trim(box:GetText())
    local v = tonumber(raw)
    if not v or v < 1 then
      v = 3
    end
    ns.db.options.lowTimeThreshold = math.min(30, math.floor(v + 0.5))
    box:SetText(tostring(ns.db.options.lowTimeThreshold))
  end)

  self.globalHint = C:CreateLabel(f, tr("global_hint"), "GameFontDisableSmall")
  self.globalHint:SetPoint("TOPLEFT", 16, -196)
  self.globalHint:SetWidth(460)
  self.globalHint:SetJustifyH("LEFT")

  self.btnGlobalClose = C:CreateButton(f, tr("loc_close"), 110, 24, function()
    f:Hide()
  end)
  self.btnGlobalClose:SetPoint("BOTTOMRIGHT", -16, 12)

  self.globalOptionsFrame = f
end

function UI:OpenGlobalOptionsPanel()
  self:BuildGlobalOptionsPanel()
  if not self.globalOptionsFrame then
    return
  end
  self:RefreshQuickState()
  self.globalOptionsFrame:Raise()
  self.globalOptionsFrame:Show()
end

function UI:BuildFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteSettingsFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(1080, 660)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()
  if ns.UISkin then
    ns.UISkin:ApplyWindow(frame)
  end

  if frame.TitleText then
    frame.TitleText:SetText(tr("ui_title"))
  end

  local quick = C:CreateSection(frame, tr("quick_actions"), 1048, 122)
  quick:SetPoint("TOPLEFT", 16, -50)
  self.quick = quick

  self.btnLock = C:CreateButton(quick, tr("btn_unlock"), 124, 22, function()
    ns.Dragger:SetLocked(not ns.db.locked)
    ns.EventRouter:RefreshAll()
    self:RefreshQuickState()
  end)
  self.btnLock:SetPoint("TOPLEFT", 12, -28)

  self.btnEdit = C:CreateButton(quick, tr("btn_edit_off"), 110, 22, function()
    ns.TestMode:SetEnabled(not ns.TestMode:IsEnabled())
    ns.EventRouter:RefreshAll()
    self:RefreshQuickState()
  end)
  self.btnEdit:SetPoint("LEFT", self.btnLock, "RIGHT", 10, 0)

  self.btnRefresh = C:CreateButton(quick, tr("btn_refresh"), 92, 22, function()
    ns:RebuildWatchIndex()
    ns.EventRouter:RefreshAll()
    self:Refresh()
  end)
  self.btnRefresh:SetPoint("LEFT", self.btnEdit, "RIGHT", 10, 0)

  self.btnLocalization = C:CreateButton(quick, tr("btn_localization"), 138, 22, function()
    self:OpenLocalizationPanel()
  end)
  self.btnLocalization:SetPoint("LEFT", self.btnRefresh, "RIGHT", 10, 0)

  self.btnRules = C:CreateButton(quick, tr("btn_rules"), 84, 22, function()
    self:SetWorkspaceMode("editor", true)
    self:OpenRulesPanel()
  end)
  self.btnRules:SetPoint("LEFT", self.btnLocalization, "RIGHT", 10, 0)

  self.btnGlobalOptions = C:CreateButton(quick, tr("btn_global_options"), 170, 22, function()
    self:OpenGlobalOptionsPanel()
  end)
  self.btnGlobalOptions:SetPoint("LEFT", self.btnRules, "RIGHT", 10, 0)

  self.lblWorkspace = C:CreateLabel(quick, tr("lbl_workspace"), "GameFontHighlightSmall")
  self.lblWorkspace:SetPoint("TOPLEFT", 786, -22)
  self.workspaceSegment = C:CreateSegmentedControl(quick, 190, 22, {
    { value = "auras", label = tr("ws_auras") },
    { value = "editor", label = tr("ws_editor") },
    { value = "split", label = tr("ws_split") },
  }, function(value)
    self:SetWorkspaceMode(value, false)
  end)
  self.workspaceSegment:SetPoint("TOPLEFT", 836, -30)

  self.cbGuided = C:CreateCheckBox(quick, tr("lbl_guided_mode"), function(checked)
    ns.db.options.uiGuidedMode = checked == true
    self:ApplyGuidedMode()
  end)
  self.cbGuided:SetPoint("TOPLEFT", 14, -62)

  self.hintText = C:CreateLabel(quick, "", "GameFontDisableSmall")
  self.hintText:SetPoint("TOPLEFT", 14, -92)
  self.hintText:SetWidth(1018)
  self.hintText:SetJustifyH("LEFT")

  local left = C:CreateSection(frame, tr("aura_list"), 348, 460)
  left:SetPoint("TOPLEFT", 16, -184)
  self.left = left

  self.lblFilter = C:CreateLabel(left, tr("lbl_filter"), "GameFontHighlightSmall")
  self.lblFilter:SetPoint("TOPLEFT", 12, -28)
  self.editFilter = C:CreateEditBox(left, 220, 20, false)
  self.editFilter:SetPoint("TOPLEFT", 12, -44)
  self.editFilter:SetScript("OnTextChanged", function()
    self:RebuildAuraList()
  end)

  self.btnClearFilter = C:CreateButton(left, tr("btn_clear"), 64, 20, function()
    self.editFilter:SetText("")
    self:RebuildAuraList()
  end)
  self.btnClearFilter:SetPoint("LEFT", self.editFilter, "RIGHT", 8, 0)

  self.listScroll = CreateFrame("ScrollFrame", nil, left, "UIPanelScrollFrameTemplate")
  self.listScroll:SetPoint("TOPLEFT", 12, -72)
  self.listScroll:SetPoint("BOTTOMRIGHT", -32, 46)
  self.listContent = CreateFrame("Frame", nil, self.listScroll)
  self.listContent:SetSize(self:GetListRowWidth(), 10)
  self.listScroll:SetScrollChild(self.listContent)
  self.listButtons = {}
  self.listRows = {}

  self.btnNewAura = C:CreateButton(left, tr("btn_new_aura"), 104, 22, function()
    self:EnterCreateMode()
  end)
  self.btnNewAura:SetPoint("BOTTOMLEFT", 12, 14)

  self.btnDuplicate = C:CreateButton(left, tr("btn_duplicate"), 88, 22, function()
    self:DuplicateSelected()
  end)
  self.btnDuplicate:SetPoint("LEFT", self.btnNewAura, "RIGHT", 8, 0)

  self.btnDelete = C:CreateButton(left, tr("btn_remove"), 88, 22, function()
    self:DeleteSelected()
  end)
  self.btnDelete:SetPoint("LEFT", self.btnDuplicate, "RIGHT", 8, 0)

  local right = C:CreateSection(frame, tr("aura_details"), 686, 460)
  right:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -16, -184)
  self.right = right

  self.divA = right:CreateTexture(nil, "ARTWORK")
  self.divA:SetColorTexture(1, 1, 1, 0.08)
  self.divA:SetPoint("TOPLEFT", 12, -136)
  self.divA:SetPoint("TOPRIGHT", -12, -136)
  self.divA:SetHeight(1)

  self.divB = right:CreateTexture(nil, "ARTWORK")
  self.divB:SetColorTexture(1, 1, 1, 0.08)
  self.divB:SetPoint("TOPLEFT", 12, -206)
  self.divB:SetPoint("TOPRIGHT", -12, -206)
  self.divB:SetHeight(1)

  self.editorTitle = C:CreateLabel(right, tr("editor_none"), "GameFontNormal")
  self.editorTitle:SetPoint("TOPLEFT", 12, -28)
  self.editorHealth = C:CreateLabel(right, "", "GameFontHighlightSmall")
  self.editorHealth:SetPoint("TOPRIGHT", -12, -30)
  self.editorHealth:SetJustifyH("RIGHT")
  self.editorGuide = C:CreateLabel(right, "", "GameFontDisableSmall")
  self.editorGuide:SetPoint("TOPLEFT", 12, -56)
  self.editorGuide:SetWidth(640)
  self.editorGuide:SetJustifyH("LEFT")

  self.tabButtons = {}
  self.btnTabGeneral = C:CreateButton(right, tr("tab_general"), 92, 20, function()
    self:SelectTab("general")
  end)
  self.btnTabGeneral:SetPoint("TOPLEFT", 12, -82)
  self.tabButtons.general = self.btnTabGeneral

  self.btnTabDisplay = C:CreateButton(right, tr("tab_display"), 92, 20, function()
    self:SelectTab("display")
  end)
  self.btnTabDisplay:SetPoint("LEFT", self.btnTabGeneral, "RIGHT", 8, 0)
  self.tabButtons.display = self.btnTabDisplay

  self.btnTabSounds = C:CreateButton(right, tr("tab_sounds"), 92, 20, function()
    self:SelectTab("sounds")
  end)
  self.btnTabSounds:SetPoint("LEFT", self.btnTabDisplay, "RIGHT", 8, 0)
  self.tabButtons.sounds = self.btnTabSounds

  self.btnTabRules = C:CreateButton(right, tr("tab_rules"), 92, 20, function()
    self:SelectTab("rules")
  end)
  self.btnTabRules:SetPoint("LEFT", self.btnTabSounds, "RIGHT", 8, 0)
  self.tabButtons.rules = self.btnTabRules

  self.lblSpell = C:CreateLabel(right, tr("lbl_spell"), "GameFontHighlightSmall")
  self.lblSpell:SetPoint("TOPLEFT", 12, -120)
  self.editSpell = C:CreateEditBox(right, 224, 20, false)
  self.editSpell:SetPoint("TOPLEFT", 12, -136)
  self.editSpell:SetScript("OnTextChanged", function(_, userInput)
    if userInput then
      self:RefreshAutocomplete()
    end
  end)
  self.editSpell:SetScript("OnTabPressed", function()
    if self.autoRows and #self.autoRows > 0 then
      self:ApplyAutocompleteRow(self.autoRows[1])
      return
    end
  end)
  self.editSpell:SetScript("OnEscapePressed", function(box)
    self:HideAutocomplete()
    box:ClearFocus()
  end)
  self.editSpell:SetScript("OnEnterPressed", function(box)
    self:HideAutocomplete()
    box:ClearFocus()
  end)
  self.editSpell:SetScript("OnEditFocusLost", function()
    C_Timer.After(0.05, function()
      self:HideAutocomplete()
    end)
  end)

  self.autoFrame = CreateFrame("Frame", nil, right, "BackdropTemplate")
  self.autoFrame:SetPoint("TOPLEFT", self.editSpell, "BOTTOMLEFT", 0, -2)
  self.autoFrame:SetSize(224, 18)
  self.autoFrame:SetFrameStrata("DIALOG")
  self.autoFrame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  self.autoFrame:SetBackdropColor(0.02, 0.02, 0.02, 0.96)
  self.autoFrame:SetBackdropBorderColor(0.35, 0.35, 0.35, 0.95)
  self.autoFrame:Hide()
  self.autoButtons = {}
  self.autoRows = {}

  self.lblAuraName = C:CreateLabel(right, tr("lbl_aura_name"), "GameFontHighlightSmall")
  self.lblAuraName:SetPoint("TOPLEFT", 252, -120)
  self.editAuraName = C:CreateEditBox(right, 314, 20, false)
  self.editAuraName:SetPoint("TOPLEFT", 252, -136)

  self.lblUnit = C:CreateLabel(right, tr("lbl_unit"), "GameFontHighlightSmall")
  self.lblUnit:SetPoint("TOPLEFT", 12, -170)
  self.ddUnit = C:CreateDropdown(right, 120)
  self.ddUnit:SetPoint("TOPLEFT", -2, -182)
  self.ddUnit:SetOptions(D:GetUnitOptions())

  self.lblGroup = C:CreateLabel(right, tr("lbl_group"), "GameFontHighlightSmall")
  self.lblGroup:SetPoint("TOPLEFT", 194, -170)
  self.ddGroup = C:CreateDropdown(right, 180)
  self.ddGroup:SetPoint("TOPLEFT", 178, -182)

  self.lblGroupCustom = C:CreateLabel(right, tr("lbl_group_custom"), "GameFontHighlightSmall")
  self.lblGroupCustom:SetPoint("TOPLEFT", 12, -220)
  self.editGroupCustom = C:CreateEditBox(right, 224, 20, false)
  self.editGroupCustom:SetPoint("TOPLEFT", 12, -236)

  self.cbOnlyMine = C:CreateCheckBox(right, tr("lbl_only_mine"), nil)
  self.cbOnlyMine:SetPoint("TOPLEFT", 394, -182)
  self.cbAlert = C:CreateCheckBox(right, tr("lbl_low_alert"), nil)
  self.cbAlert:SetPoint("LEFT", self.cbOnlyMine, "RIGHT", 126, 0)
  self.lblLowTimeAura = C:CreateLabel(right, tr("lbl_low_time_aura"), "GameFontHighlightSmall")
  self.lblLowTimeAura:SetPoint("TOPLEFT", 394, -218)
  self.editLowTimeAura = C:CreateEditBox(right, 56, 20, false)
  self.editLowTimeAura:SetPoint("TOPLEFT", 394, -234)
  self.editLowTimeAura:SetNumeric(false)

  self.lblIconMode = C:CreateLabel(right, tr("lbl_icon"), "GameFontHighlightSmall")
  self.lblIconMode:SetPoint("TOPLEFT", 12, -120)
  self.ddIconMode = C:CreateDropdown(right, 130)
  self.ddIconMode:SetPoint("TOPLEFT", -2, -132)
  self.ddIconMode:SetOptions({
    { value = "spell", label = tr("opt_spell_icon") },
    { value = "custom", label = tr("opt_custom_path") },
  })
  self.ddIconMode:SetOnValueChanged(function(value)
    self:RefreshIconCustomVisibility(value)
  end)

  self.lblTexture = C:CreateLabel(right, tr("lbl_custom_texture"), "GameFontHighlightSmall")
  self.lblTexture:SetPoint("TOPLEFT", 12, -166)
  self.editTexture = C:CreateEditBox(right, 650, 20, false)
  self.editTexture:SetPoint("TOPLEFT", 12, -182)

  self.lblTimerVisual = C:CreateLabel(right, tr("lbl_cd_visual"), "GameFontHighlightSmall")
  self.lblTimerVisual:SetPoint("TOPLEFT", 214, -120)
  self.ddTimerVisual = C:CreateDropdown(right, 92)
  self.ddTimerVisual:SetPoint("TOPLEFT", 196, -132)
  self.ddTimerVisual:SetOptions(timerVisualOptions)
  self.ddTimerVisual:SetOnValueChanged(function(value)
    self:RefreshBarTextureVisibility(value)
  end)

  self.lblBarTexture = C:CreateLabel(right, tr("lbl_bar_texture"), "GameFontHighlightSmall")
  self.lblBarTexture:SetPoint("TOPLEFT", 332, -120)
  self.ddBarTexturePreset = C:CreateDropdown(right, 190)
  self.ddBarTexturePreset:SetPoint("TOPLEFT", 316, -132)
  self.ddBarTexturePreset:SetOptions(self:GetBarTextureOptions())
  self.ddBarTexturePreset:SetOnValueChanged(function(value)
    if not self.editBarTexture then
      return
    end
    if value == "" then
      self.editBarTexture:SetText("")
      return
    end
    if value == "custom" then
      self.editBarTexture:SetFocus()
      return
    end
    self.editBarTexture:SetText(tostring(value))
  end)
  self.editBarTexture = C:CreateEditBox(right, 234, 20, false)
  self.editBarTexture:SetPoint("TOPLEFT", 332, -182)

  self.textureHelp = C:CreateLabel(right, tr("help_custom_texture"), "GameFontDisableSmall")
  self.textureHelp:SetPoint("TOPLEFT", 12, -204)
  self.barTextureHelp = C:CreateLabel(right, tr("help_bar_texture"), "GameFontDisableSmall")
  self.barTextureHelp:SetPoint("TOPLEFT", 332, -204)

  self.lblCustomText = C:CreateLabel(right, tr("lbl_custom_text"), "GameFontHighlightSmall")
  self.lblCustomText:SetPoint("TOPLEFT", 12, -228)
  self.editCustomText = C:CreateEditBox(right, 650, 20, false)
  self.editCustomText:SetPoint("TOPLEFT", 12, -244)
  self.customTextHelp = C:CreateLabel(
    right,
    tr("help_custom_text"),
    "GameFontDisableSmall"
  )
  self.customTextHelp:SetPoint("TOPLEFT", 12, -266)

  self.cbResourceCondition = C:CreateCheckBox(right, tr("lbl_resource_condition"), nil)
  self.cbResourceCondition:SetPoint("TOPLEFT", 12, -276)
  self.lblResourceRange = C:CreateLabel(right, tr("lbl_resource_range"), "GameFontHighlightSmall")
  self.lblResourceRange:SetPoint("TOPLEFT", 252, -272)
  self.editResourceMin = C:CreateEditBox(right, 50, 20, false)
  self.editResourceMin:SetPoint("TOPLEFT", 252, -288)
  self.editResourceMax = C:CreateEditBox(right, 50, 20, false)
  self.editResourceMax:SetPoint("TOPLEFT", 310, -288)
  self.lblResourceCurrent = C:CreateLabel(right, "", "GameFontDisableSmall")
  self.lblResourceCurrent:SetPoint("TOPLEFT", 374, -290)

  self.lblTimerAnchor = C:CreateLabel(right, tr("lbl_timer_anchor"), "GameFontHighlightSmall")
  self.lblTimerAnchor:SetPoint("TOPLEFT", 12, -296)
  self.ddTimerAnchor = C:CreateDropdown(right, 120)
  self.ddTimerAnchor:SetPoint("TOPLEFT", -2, -308)
  self.ddTimerAnchor:SetOptions(textAnchorOptions)

  self.lblTimerOffset = C:CreateLabel(right, tr("lbl_timer_offset"), "GameFontHighlightSmall")
  self.lblTimerOffset:SetPoint("TOPLEFT", 190, -296)
  self.editTimerOffsetX = C:CreateEditBox(right, 50, 20, false)
  self.editTimerOffsetX:SetPoint("TOPLEFT", 190, -312)
  self.editTimerOffsetY = C:CreateEditBox(right, 50, 20, false)
  self.editTimerOffsetY:SetPoint("TOPLEFT", 248, -312)

  self.lblCustomAnchor = C:CreateLabel(right, tr("lbl_text_anchor"), "GameFontHighlightSmall")
  self.lblCustomAnchor:SetPoint("TOPLEFT", 350, -296)
  self.ddCustomAnchor = C:CreateDropdown(right, 120)
  self.ddCustomAnchor:SetPoint("TOPLEFT", 336, -308)
  self.ddCustomAnchor:SetOptions(textAnchorOptions)

  self.lblCustomOffset = C:CreateLabel(right, tr("lbl_text_offset"), "GameFontHighlightSmall")
  self.lblCustomOffset:SetPoint("TOPLEFT", 516, -296)
  self.editCustomOffsetX = C:CreateEditBox(right, 50, 20, false)
  self.editCustomOffsetX:SetPoint("TOPLEFT", 516, -312)
  self.editCustomOffsetY = C:CreateEditBox(right, 50, 20, false)
  self.editCustomOffsetY:SetPoint("TOPLEFT", 574, -312)

  self.soundTitle = C:CreateLabel(right, tr("lbl_sound_title"), "GameFontNormal")
  self.soundTitle:SetPoint("TOPLEFT", 12, -116)

  self.soundControls = {}
  self:BuildSoundRow("gain", tr("lbl_sound_gain"), -156)
  self:BuildSoundRow("low", tr("lbl_sound_low"), -244)
  self:BuildSoundRow("expire", tr("lbl_sound_expire"), -332)

  self.tabControls = {
    general = {},
    display = {},
    sounds = {},
    rules = {},
  }

  self:RegisterTabControls("general", {
    self.lblSpell, self.editSpell, self.autoFrame,
    self.lblAuraName, self.editAuraName,
    self.lblUnit, self.ddUnit,
    self.lblGroup, self.ddGroup,
    self.lblGroupCustom, self.editGroupCustom,
    self.cbOnlyMine, self.cbAlert,
    self.lblLowTimeAura, self.editLowTimeAura,
    self.cbResourceCondition, self.lblResourceRange,
    self.editResourceMin, self.editResourceMax, self.lblResourceCurrent,
  })

  self:RegisterTabControls("display", {
    self.divA, self.divB,
    self.lblIconMode, self.ddIconMode,
    self.lblTexture, self.editTexture, self.textureHelp,
    self.lblTimerVisual, self.ddTimerVisual, self.ddBarTexturePreset,
    self.lblBarTexture, self.editBarTexture, self.barTextureHelp,
    self.lblCustomText, self.editCustomText, self.customTextHelp,
    self.lblTimerAnchor, self.ddTimerAnchor,
    self.lblTimerOffset, self.editTimerOffsetX, self.editTimerOffsetY,
    self.lblCustomAnchor, self.ddCustomAnchor,
    self.lblCustomOffset, self.editCustomOffsetX, self.editCustomOffsetY,
  })

  self:RegisterTabControls("sounds", {
    self.soundTitle,
  })
  for _, state in ipairs({ "gain", "low", "expire" }) do
    local row = self.soundControls[state]
    if row then
      self:RegisterTabControls("sounds", {
        row.label, row.dropdown, row.pathEdit, row.test,
      })
    end
  end

  self.advancedControlsByTab = {
    general = {
      self.lblGroupCustom, self.editGroupCustom,
      self.lblLowTimeAura, self.editLowTimeAura,
      self.cbResourceCondition, self.lblResourceRange, self.editResourceMin, self.editResourceMax, self.lblResourceCurrent,
    },
    display = {
      self.lblTexture, self.editTexture, self.textureHelp,
      self.lblBarTexture, self.editBarTexture, self.barTextureHelp,
      self.lblTimerAnchor, self.ddTimerAnchor,
      self.lblTimerOffset, self.editTimerOffsetX, self.editTimerOffsetY,
      self.lblCustomAnchor, self.ddCustomAnchor,
      self.lblCustomOffset, self.editCustomOffsetX, self.editCustomOffsetY,
    },
    sounds = {},
    rules = {},
  }

  self:BuildRulesPanel()

  self.btnSave = C:CreateButton(right, tr("btn_save"), 116, 24, function()
    self:SaveCurrentAura()
  end)
  self.btnSave:SetPoint("BOTTOMLEFT", 12, 14)

  self.btnReset = C:CreateButton(right, tr("btn_reset"), 116, 24, function()
    self:ResetCurrentForm()
  end)
  self.btnReset:SetPoint("LEFT", self.btnSave, "RIGHT", 8, 0)

  self.btnOpenOptions = C:CreateButton(right, tr("btn_open_options"), 186, 24, function()
    if not ns.OptionsIntegration:OpenBlizzardCategory() then
      info(tr("msg_category_unavailable"))
    end
  end)
  self.btnOpenOptions:SetPoint("LEFT", self.btnReset, "RIGHT", 8, 0)

  self.frame = frame
  self.editorMode = "create"
  self.selectedKey = nil
  self.modelSnapshot = nil

  self:BuildGlobalOptionsPanel()
  self:ApplySkin()
  self:ApplyLocalization()
  self:SelectTab("general")
  self:ApplyWorkspaceLayout()
  self:ApplyGuidedMode()
end

function UI:BuildSoundRow(state, label, yOffset)
  local row = {}
  local right = self.right
  local options = buildSoundOptions()
  row.state = state

  row.label = C:CreateLabel(right, label, "GameFontHighlightSmall")
  row.label:SetPoint("TOPLEFT", 12, yOffset)

  row.dropdown = C:CreateDropdown(right, 170)
  row.dropdown:SetPoint("TOPLEFT", 0, yOffset - 24)
  row.dropdown:SetOptions(options)

  row.pathEdit = C:CreateEditBox(right, 360, 20, false)
  row.pathEdit:SetPoint("TOPLEFT", 206, yOffset - 26)

  row.test = C:CreateButton(right, tr("btn_test"), 56, 20, function()
    local token = row.dropdown:GetValue()
    local path = U.Trim(row.pathEdit:GetText() or "")
    if token == "file" then
      if path == "" then
        info(tr("msg_no_audio_path"))
        return
      end
      token = "file:" .. path
    end
    S:Play(token, state)
  end)
  row.test:SetPoint("LEFT", row.pathEdit, "RIGHT", 8, 0)

  self.soundControls[state] = row
end

function UI:ApplyLocalization()
  if not self.frame then
    return
  end

  if self.frame.TitleText then
    self.frame.TitleText:SetText(tr("ui_title"))
  end

  self.quick.title:SetText(tr("quick_actions"))
  self.left.title:SetText(tr("aura_list"))
  self.right.title:SetText(tr("aura_details"))

  self.btnRefresh:SetText(tr("btn_refresh"))
  self.btnLocalization:SetText(tr("btn_localization"))
  if self.btnGlobalOptions then
    self.btnGlobalOptions:SetText(tr("btn_global_options"))
  end
  if self.btnRules then
    self.btnRules:SetText(tr("btn_rules"))
  end
  if self.btnTabGeneral then
    self.btnTabGeneral:SetText(tr("tab_general"))
  end
  if self.btnTabDisplay then
    self.btnTabDisplay:SetText(tr("tab_display"))
  end
  if self.btnTabSounds then
    self.btnTabSounds:SetText(tr("tab_sounds"))
  end
  if self.btnTabRules then
    self.btnTabRules:SetText(tr("tab_rules"))
  end
  if self.cbCompact and self.cbCompact.text then
    self.cbCompact.text:SetText(tr("lbl_compact"))
  end
  if self.cbSource and self.cbSource.text then
    self.cbSource.text:SetText(tr("lbl_show_source"))
  end
  if self.cbSounds and self.cbSounds.text then
    self.cbSounds.text:SetText(tr("lbl_enable_sounds"))
  end
  if self.cbDebug and self.cbDebug.text then
    self.cbDebug.text:SetText(tr("lbl_debug_chat"))
  end
  self.cbGuided.text:SetText(tr("lbl_guided_mode"))
  if self.cbRulesOnly and self.cbRulesOnly.text then
    self.cbRulesOnly.text:SetText(tr("lbl_rules_only"))
  end
  if self.lblChannel then
    self.lblChannel:SetText(tr("lbl_channel"))
  end
  if self.lblThreshold then
    self.lblThreshold:SetText(tr("lbl_low_time"))
  end
  self.lblWorkspace:SetText(tr("lbl_workspace"))
  self.lblFilter:SetText(tr("lbl_filter"))
  self.btnClearFilter:SetText(tr("btn_clear"))
  self.btnNewAura:SetText(tr("btn_new_aura"))
  self.btnDuplicate:SetText(tr("btn_duplicate"))
  self.btnDelete:SetText(tr("btn_remove"))
  self.lblSpell:SetText(tr("lbl_spell"))
  self.lblAuraName:SetText(tr("lbl_aura_name"))
  self.lblUnit:SetText(tr("lbl_unit"))
  self.lblGroup:SetText(tr("lbl_group"))
  self.lblGroupCustom:SetText(tr("lbl_group_custom"))
  self.cbOnlyMine.text:SetText(tr("lbl_only_mine"))
  self.cbAlert.text:SetText(tr("lbl_low_alert"))
  self.lblLowTimeAura:SetText(tr("lbl_low_time_aura"))
  self.lblIconMode:SetText(tr("lbl_icon"))
  self.lblTexture:SetText(tr("lbl_custom_texture"))
  self.textureHelp:SetText(tr("help_custom_texture"))
  self.lblTimerVisual:SetText(tr("lbl_cd_visual"))
  if self.lblBarTexture then
    self.lblBarTexture:SetText(tr("lbl_bar_texture"))
  end
  if self.barTextureHelp then
    self.barTextureHelp:SetText(tr("help_bar_texture"))
  end
  self.lblCustomText:SetText(tr("lbl_custom_text"))
  self.customTextHelp:SetText(tr("help_custom_text"))
  self.cbResourceCondition.text:SetText(tr("lbl_resource_condition"))
  self.lblResourceRange:SetText(tr("lbl_resource_range"))
  self.lblTimerAnchor:SetText(tr("lbl_timer_anchor"))
  self.lblTimerOffset:SetText(tr("lbl_timer_offset"))
  self.lblCustomAnchor:SetText(tr("lbl_text_anchor"))
  self.lblCustomOffset:SetText(tr("lbl_text_offset"))
  self.soundTitle:SetText(tr("lbl_sound_title"))
  self.btnSave:SetText(tr("btn_save"))
  self.btnReset:SetText(tr("btn_reset"))
  self.btnOpenOptions:SetText(tr("btn_open_options"))
  if self.btnLocalization then
    self.btnLocalization:SetText(tr("btn_localization"))
  end

  self.ddIconMode:SetOptions({
    { value = "spell", label = tr("opt_spell_icon") },
    { value = "custom", label = tr("opt_custom_path") },
  })
  self.ddTimerVisual:SetOptions({
    { value = "icon", label = tr("opt_cd_icon") },
    { value = "bar", label = tr("opt_cd_icon_bar") },
  })
  if self.ddBarTexturePreset then
    local currentBarPreset = self.ddBarTexturePreset:GetValue()
    self:RefreshBarTextureOptions()
    if currentBarPreset then
      self.ddBarTexturePreset:SetValue(currentBarPreset)
    end
  end

  self.ddTimerAnchor:SetOptions(textAnchorOptions)
  self.ddCustomAnchor:SetOptions(textAnchorOptions)
  if self.workspaceSegment then
    self.workspaceSegment:SetOptions({
      { value = "auras", label = tr("ws_auras") },
      { value = "editor", label = tr("ws_editor") },
      { value = "split", label = tr("ws_split") },
    })
  end
  if self.globalOptionsFrame and self.globalOptionsFrame.TitleText then
    self.globalOptionsFrame.TitleText:SetText(tr("global_title"))
  end
  if self.globalHint then
    self.globalHint:SetText(tr("global_hint"))
  end
  if self.btnGlobalClose then
    self.btnGlobalClose:SetText(tr("loc_close"))
  end

  if self.soundControls.gain then
    self.soundControls.gain.label:SetText(tr("lbl_sound_gain"))
    self.soundControls.gain.test:SetText(tr("btn_test"))
  end
  if self.soundControls.low then
    self.soundControls.low.label:SetText(tr("lbl_sound_low"))
    self.soundControls.low.test:SetText(tr("btn_test"))
  end
  if self.soundControls.expire then
    self.soundControls.expire.label:SetText(tr("lbl_sound_expire"))
    self.soundControls.expire.test:SetText(tr("btn_test"))
  end

  self:SelectTab(self.activeTab or "general")
  self:UpdateHintText()
  self:ApplySkin()
  self:RefreshQuickState()
  self:RefreshResourcePreview()
  self:RefreshLocalizationPanelTexts()
  self:RefreshRulesPanelTexts()
end

function UI:RefreshResourcePreview()
  if not self.lblResourceCurrent or not ns.PlayerResource then
    return
  end
  local data = ns.PlayerResource:GetPrimaryResource()
  local label = ns.PlayerResource:GetPrimaryLabel()
  if data.available == true then
    self.lblResourceCurrent:SetText(string.format(tr("lbl_resource_current_fmt"), label, math.floor((data.pct or 0) + 0.5)))
  else
    self.lblResourceCurrent:SetText(string.format(tr("lbl_resource_current_na"), label))
  end
end

function UI:RefreshLocalizationPanelTexts()
  if not self.localizationFrame then
    return
  end
  local f = self.localizationFrame
  if f.title then
    f.title:SetText(tr("loc_title"))
  end
  if f.lblLanguage then
    f.lblLanguage:SetText(tr("loc_language"))
  end
  if f.lblTheme then
    f.lblTheme:SetText(tr("loc_theme"))
  end
  if f.lblTexture then
    f.lblTexture:SetText(tr("loc_texture"))
  end
  if f.lblTextureHelp then
    f.lblTextureHelp:SetText(tr("loc_texture_help"))
  end
  if f.btnApply then
    f.btnApply:SetText(tr("loc_apply"))
  end
  if f.btnClose then
    f.btnClose:SetText(tr("loc_close"))
  end
  if f.ddLanguage then
    local current = f.ddLanguage:GetValue() or (L and L:GetLanguage()) or "enUS"
    f.ddLanguage:SetOptions(L:GetLanguageOptions())
    f.ddLanguage:SetValue(current)
  end
  if f.ddTheme and ns.UISkin then
    local currentTheme = f.ddTheme:GetValue() or (ns.db and ns.db.options and ns.db.options.uiTheme) or "modern"
    f.ddTheme:SetOptions(ns.UISkin:GetThemeOptions())
    f.ddTheme:SetValue(currentTheme)
  end
  self:ApplySkin()
end

function UI:RefreshRulesTypeVisibility()
  if not self.rulesFrame then
    return
  end
  local f = self.rulesFrame
  local ruleType = (f.ddType and f.ddType:GetValue()) or "if"
  local subTab = tostring(f.activeSubTab or "trigger")
  local onTrigger = subTab == "trigger"
  local onConditions = subTab == "conditions"
  local onActions = subTab == "actions"

  local function setShown(ctrl, shown)
    if ctrl then
      ctrl:SetShown(shown == true)
    end
  end

  setShown(f.lblType, onTrigger)
  setShown(f.ddType, onTrigger)
  setShown(f.lblRuleID, onTrigger)
  setShown(f.editRuleID, onTrigger)
  setShown(f.lblCastSpell, onTrigger)
  setShown(f.editCastSpell, onTrigger)

  setShown(f.lblConditionMode, onConditions)
  setShown(f.ddConditionMode, onConditions)
  setShown(f.lblTalentSpell, onConditions)
  setShown(f.editTalentSpell, onConditions)
  setShown(f.lblConditionAura, onConditions)
  setShown(f.editConditionAura, onConditions)
  setShown(f.cbConditionCombat, onConditions)
  setShown(f.csvHint, onConditions)

  setShown(f.lblAuraSpell, onActions)
  setShown(f.editAuraSpell, onActions)
  setShown(f.lblDuration, onActions and ruleType == "if")
  setShown(f.editDuration, onActions and ruleType == "if")
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
    castSpellIDs = {},
    conditionMode = "all",
    talentSpellIDs = {},
    requiredAuraSpellIDs = {},
    requireInCombat = false,
    auraSpellID = boundAuraSpellID or "",
    duration = 8,
  }
  if f.ddType then
    f.ddType:SetValue(model.type or "if")
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
    castSpellIDs = castSpellIDs,
    conditionMode = (f.ddConditionMode and f.ddConditionMode:GetValue()) or "all",
    talentSpellIDs = talentSpellIDs,
    requiredAuraSpellIDs = requiredAuraSpellIDs,
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
  f.ruleRows = rules
  f.ruleButtons = f.ruleButtons or {}

  local rowWidth = math.max(140, math.floor((f.listBaseWidth or 228) - 34))
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
    if #label > 34 then
      label = label:sub(1, 31) .. "..."
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

  f.listContent:SetSize(rowWidth, math.max(24, #rules * 24))
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

  local panelW = f:GetWidth()
  local panelH = f:GetHeight()
  local listW = 228
  local formX = listW + 44
  local formW = math.max(280, panelW - formX - 12)
  local colGap = 14
  local colW = math.max(132, math.floor((formW - colGap) / 2))
  local colA = formX
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
  f.listScroll:SetPoint("TOPLEFT", 10, -46)
  f.listScroll:SetSize(listW, math.max(180, panelH - 92))
  f.listContent = CreateFrame("Frame", nil, f.listScroll)
  f.listContent:SetSize(math.max(128, listW - 28), 10)
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

  f.lblType = C:CreateLabel(f, "", "GameFontHighlightSmall")
  f.lblType:SetPoint("TOPLEFT", colA, -84)
  fitRuleLabel(f.lblType, formW)
  f.ddType = C:CreateDropdown(f, formW)
  f.ddType:SetPoint("TOPLEFT", colA - 16, -100)
  f.ddType:SetOnValueChanged(function()
    self:RefreshRulesTypeVisibility()
  end)

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

  f.cbConditionCombat = C:CreateCheckBox(f, "", function() end)
  f.cbConditionCombat:SetPoint("TOPLEFT", colA, -236)

  f.csvHint = C:CreateLabel(f, "CSV example: 6343,23922", "GameFontDisableSmall")
  f.csvHint:SetPoint("TOPLEFT", colA, -266)
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

function UI:BuildLocalizationPanel()
  if self.localizationFrame then
    return
  end

  local f = CreateFrame("Frame", "AuraLiteLocalizationFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(420, 270)
  f:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetToplevel(true)
  f:SetClampedToScreen(true)
  f:SetMovable(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  f:Hide()
  if ns.UISkin then
    ns.UISkin:ApplyWindow(f)
  end

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 16, -14)

  f.lblLanguage = C:CreateLabel(f, "", "GameFontHighlight")
  f.lblLanguage:SetPoint("TOPLEFT", 18, -50)

  f.ddLanguage = C:CreateDropdown(f, 180)
  f.ddLanguage:SetPoint("TOPLEFT", 8, -70)
  f.ddLanguage:SetOptions(L:GetLanguageOptions())
  f.ddLanguage:SetValue(L:GetLanguage())

  f.lblTheme = C:CreateLabel(f, "", "GameFontHighlight")
  f.lblTheme:SetPoint("TOPLEFT", 18, -102)
  f.ddTheme = C:CreateDropdown(f, 180)
  f.ddTheme:SetPoint("TOPLEFT", 8, -122)
  if ns.UISkin then
    f.ddTheme:SetOptions(ns.UISkin:GetThemeOptions())
  end
  f.ddTheme:SetValue((ns.db and ns.db.options and ns.db.options.uiTheme) or "modern")

  f.lblTexture = C:CreateLabel(f, "", "GameFontHighlight")
  f.lblTexture:SetPoint("TOPLEFT", 18, -154)
  f.editTexture = C:CreateEditBox(f, 360, 20, false)
  f.editTexture:SetPoint("TOPLEFT", 18, -172)
  f.editTexture:SetText((ns.db and ns.db.options and ns.db.options.uiTexturePath) or "")
  f.lblTextureHelp = C:CreateLabel(f, "", "GameFontDisableSmall")
  f.lblTextureHelp:SetPoint("TOPLEFT", 18, -194)

  f.btnApply = C:CreateButton(f, "", 100, 22, function()
    local code = f.ddLanguage:GetValue() or "enUS"
    local applied = L:SetLanguage(code)

    if ns.UISkin then
      ns.UISkin:EnsureOptionsDefaults(ns.db.options)
      local theme = f.ddTheme and f.ddTheme:GetValue() or "modern"
      if theme == "modern" or theme == "classic" then
        ns.db.options.uiTheme = theme
      end
      ns.db.options.uiTexturePath = U.Trim((f.editTexture and f.editTexture:GetText()) or "")
    end

    self:ApplyLocalization()
    self:ApplySkin()
    info(string.format(tr("msg_language_applied"), applied))
    info(string.format(tr("msg_style_applied"), tostring(ns.db.options.uiTheme or "modern")))
  end)
  f.btnApply:SetPoint("BOTTOMLEFT", 16, 14)

  f.btnClose = C:CreateButton(f, "", 100, 22, function()
    f:Hide()
  end)
  f.btnClose:SetPoint("LEFT", f.btnApply, "RIGHT", 8, 0)

  self.localizationFrame = f
  self:ApplySkin()
  self:RefreshLocalizationPanelTexts()
end

function UI:OpenLocalizationPanel()
  self:BuildLocalizationPanel()
  self.localizationFrame.ddLanguage:SetValue(L:GetLanguage())
  if self.localizationFrame.ddTheme then
    self.localizationFrame.ddTheme:SetValue((ns.db and ns.db.options and ns.db.options.uiTheme) or "modern")
  end
  if self.localizationFrame.editTexture then
    self.localizationFrame.editTexture:SetText((ns.db and ns.db.options and ns.db.options.uiTexturePath) or "")
  end
  self.localizationFrame:Raise()
  self.localizationFrame:Show()
end

function UI:RefreshQuickState()
  self:EnsureUXOptionsDefaults()
  if self.cbCompact then
    self.cbCompact:SetChecked(ns.db.options.compactMode == true)
  end
  if self.cbSource then
    self.cbSource:SetChecked(ns.db.options.showSource == true)
  end
  if self.cbSounds then
    self.cbSounds:SetChecked(ns.db.options.soundEnabled == true)
  end
  if self.cbDebug then
    self.cbDebug:SetChecked(ns.db.options.debugEnabled == true)
  end
  self.cbGuided:SetChecked(ns.db.options.uiGuidedMode == true)
  if self.cbRulesOnly then
    self.cbRulesOnly:SetChecked(ns.db.options.rulesOnlyMode == true)
  end
  if self.ddChannel then
    self.ddChannel:SetValue(ns.db.options.soundChannel or "Master")
  end
  if self.editThreshold then
    self.editThreshold:SetText(tostring(ns.db.options.lowTimeThreshold or 3))
  end
  if self.workspaceSegment then
    self.workspaceSegment:SetValue(ns.db.options.uiWorkspace or "split", false)
  end

  self.btnLock:SetText(ns.db.locked and tr("btn_unlock") or tr("btn_lock"))
  self.btnEdit:SetText(ns.TestMode:IsEnabled() and tr("btn_edit_on") or tr("btn_edit_off"))
  self:UpdateHintText()
  self:RefreshResourcePreview()
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
      btn.text:SetPoint("RIGHT", -72, 0)
      btn.text:SetJustifyH("LEFT")
      btn.text:SetWordWrap(false)
      btn.meta = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      btn.meta:SetPoint("BOTTOMLEFT", btn.icon, "BOTTOMRIGHT", 6, 1)
      btn.meta:SetPoint("BOTTOMRIGHT", -64, 1)
      btn.meta:SetJustifyH("LEFT")
      btn.meta:SetWordWrap(false)
      btn.meta:Hide()
      btn.status = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.status:SetPoint("RIGHT", -6, 0)
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
    if #label > 32 then
      label = label:sub(1, 29) .. "..."
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
  local model = {
    spellInput = U.Trim(self.editSpell:GetText() or ""),
    displayName = U.Trim(self.editAuraName:GetText() or ""),
    unit = self.ddUnit:GetValue() or "player",
    groupID = self.ddGroup:GetValue() or "important_procs",
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
  local groupID = model.groupID or "important_procs"
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
end
