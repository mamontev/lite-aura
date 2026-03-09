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
  if options.aggregateByGroup == nil then
    options.aggregateByGroup = false
  else
    options.aggregateByGroup = options.aggregateByGroup == true
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
  local layoutSig = table.concat({
    tostring(mode),
    tostring(contentTopY),
    tostring(contentHeight),
    tostring(fullWidth),
    tostring(self.activeTab or "general"),
    tostring(#(self.listButtons or {})),
    tostring(self.frame:IsShown() and 1 or 0),
  }, "|")
  if self._layoutSig == layoutSig then
    self:UpdateHintText()
    return
  end
  self._layoutSig = layoutSig

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
    self.left:SetSize(364, contentHeight)
    self.left:Show()
    self.right:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -16, contentTopY)
    self.right:SetSize(724, contentHeight)
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
    if self.RelayoutRulesPanel then
      self:RelayoutRulesPanel()
    elseif self.activeTab == "rules" and f:IsShown() then
      self:RefreshRulesList()
    end
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
  local guidedSig = tostring(guided) .. "|" .. tostring(self.activeTab or "general")
  if self._guidedSig == guidedSig then
    self:RefreshBarTextureVisibility(self.ddTimerVisual and self.ddTimerVisual:GetValue() or "icon")
    self:UpdateHintText()
    return
  end
  self._guidedSig = guidedSig

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
    self.btnTabGeneral, self.btnTabDisplay, self.btnTabSounds, self.btnTabLoad, self.btnTabRules,
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
    self.ddBarTexturePreset, self.ddLoadClass, self.ddLoadSpec, self.ddTimerAnchor, self.ddCustomAnchor,
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
    f:ClearAllPoints()
    f:SetPoint("TOPLEFT", self.right, "TOPLEFT", 12, -112)
    f:SetSize(math.max(620, math.floor(self.right:GetWidth() - 24)), math.max(300, math.floor(self.right:GetHeight() - 144)))
    if self.RelayoutRulesPanel then
      self:RelayoutRulesPanel()
    elseif self.activeTab == "rules" and f:IsShown() then
      self:RefreshRulesList()
    end
  end

  self:UpdateHintText()
end

function UI:RegisterTabControls(tabKey, controls)
  if type(tabKey) ~= "string" or type(controls) ~= "table" then
    return
  end
  self.tabControls = self.tabControls or {}
  self.tabControls[tabKey] = self.tabControls[tabKey] or {}
  local bucket = self.tabControls[tabKey]
  for i = 1, #controls do
    local ctrl = controls[i]
    if ctrl then
      bucket[#bucket + 1] = ctrl
    end
  end
end

local validTabs = {
  general = true,
  display = true,
  sounds = true,
  load = true,
  rules = true,
}

function UI:SelectTab(tabKey)
  if not validTabs[tabKey] then
    tabKey = "general"
  end
  self.activeTab = tabKey

  for key, btn in pairs(self.tabButtons or {}) do
    if btn and btn.Disable and btn.Enable then
      if key == tabKey then
        btn:Disable()
      else
        btn:Enable()
      end
    end
  end

  local map = self.tabControls or {}
  for key, controls in pairs(map) do
    local show = key == tabKey
    for i = 1, #controls do
      local ctrl = controls[i]
      if ctrl and ctrl.SetShown then
        ctrl:SetShown(show)
      elseif ctrl and ctrl.Show and ctrl.Hide then
        if show then
          ctrl:Show()
        else
          ctrl:Hide()
        end
      end
    end
  end

  if tabKey == "rules" then
    if self.BuildRulesPanel then
      self:BuildRulesPanel()
    end
    if self.rulesFrame then
      self:SyncRuleAuraBinding()
      if self.RelayoutRulesPanel then
        self:RelayoutRulesPanel()
      end
      self:RefreshRulesList()
      self:RefreshRulesTypeVisibility()
      self:SetRulesSubTab((self.rulesFrame and self.rulesFrame.activeSubTab) or "trigger", false)
    end
  end

  self:RefreshIconCustomVisibility(self.ddIconMode and self.ddIconMode:GetValue() or "spell")
  if self.RefreshBarTextureVisibility then
    self:RefreshBarTextureVisibility(self.ddTimerVisual and self.ddTimerVisual:GetValue() or "icon")
  end
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

  self.cbAggregateGroup = C:CreateCheckBox(f, tr("lbl_aggregate_group"), function(checked)
    ns.db.options.aggregateByGroup = checked == true
    ns.EventRouter:RefreshAll()
  end)
  self.cbAggregateGroup:SetPoint("TOPLEFT", 16, -180)

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
  self.globalHint:SetPoint("TOPLEFT", 16, -224)
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
  frame:SetSize(1120, 700)
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

  local quick = C:CreateSection(frame, tr("quick_actions"), 1088, 132)
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
  self.lblWorkspace:SetPoint("TOPRIGHT", quick, "TOPRIGHT", -222, -22)
  self.workspaceSegment = C:CreateSegmentedControl(quick, 190, 22, {
    { value = "auras", label = tr("ws_auras") },
    { value = "editor", label = tr("ws_editor") },
    { value = "split", label = tr("ws_split") },
  }, function(value)
    self:SetWorkspaceMode(value, false)
  end)
  self.workspaceSegment:SetPoint("TOPRIGHT", quick, "TOPRIGHT", -14, -30)

  self.cbGuided = C:CreateCheckBox(quick, tr("lbl_guided_mode"), function(checked)
    ns.db.options.uiGuidedMode = checked == true
    self:ApplyGuidedMode()
  end)
  self.cbGuided:SetPoint("TOPLEFT", 14, -62)

  self.hintText = C:CreateLabel(quick, "", "GameFontDisableSmall")
  self.hintText:SetPoint("TOPLEFT", 14, -92)
  self.hintText:SetWidth(1060)
  self.hintText:SetJustifyH("LEFT")

  local left = C:CreateSection(frame, tr("aura_list"), 364, 492)
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

  local right = C:CreateSection(frame, tr("aura_details"), 724, 492)
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

  self.btnTabLoad = C:CreateButton(right, tr("tab_load"), 92, 20, function()
    self:SelectTab("load")
  end)
  self.btnTabLoad:SetPoint("LEFT", self.btnTabSounds, "RIGHT", 8, 0)
  self.tabButtons.load = self.btnTabLoad

  self.btnTabRules = C:CreateButton(right, tr("tab_rules"), 92, 20, function()
    self:SelectTab("rules")
  end)
  self.btnTabRules:SetPoint("LEFT", self.btnTabLoad, "RIGHT", 8, 0)
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
  if self.cbOnlyMine.text then self.cbOnlyMine.text:SetWidth(120) end
  self.cbAlert = C:CreateCheckBox(right, tr("lbl_low_alert"), nil)
  self.cbAlert:SetPoint("TOPLEFT", 394, -208)
  if self.cbAlert.text then self.cbAlert.text:SetWidth(180) end
  self.cbMoveWithGroup = C:CreateCheckBox(right, tr("lbl_move_with_group"), nil)
  self.cbMoveWithGroup:SetPoint("TOPLEFT", 394, -234)
  if self.cbMoveWithGroup.text then self.cbMoveWithGroup.text:SetWidth(220) end
  self.lblLowTimeAura = C:CreateLabel(right, tr("lbl_low_time_aura"), "GameFontHighlightSmall")
  self.lblLowTimeAura:SetPoint("TOPLEFT", 394, -262)
  self.editLowTimeAura = C:CreateEditBox(right, 56, 20, false)
  self.editLowTimeAura:SetPoint("TOPLEFT", 394, -278)
  self.editLowTimeAura:SetNumeric(false)

  self.lblLoadClass = C:CreateLabel(right, tr("lbl_load_class"), "GameFontHighlightSmall")
  self.lblLoadClass:SetPoint("TOPLEFT", 12, -262)
  self.ddLoadClass = C:CreateDropdown(right, 180)
  self.ddLoadClass:SetPoint("TOPLEFT", -2, -274)
  self.ddLoadClass:SetOptions(D:GetLoadClassOptions())

  self.lblLoadSpec = C:CreateLabel(right, tr("lbl_load_spec"), "GameFontHighlightSmall")
  self.lblLoadSpec:SetPoint("TOPLEFT", 206, -262)
  self.ddLoadSpec = C:CreateDropdown(right, 168)
  self.ddLoadSpec:SetPoint("TOPLEFT", 190, -274)
  self.ddLoadSpec:SetOptions(D:GetLoadSpecMenuOptions(""))
  self.ddLoadSpec:SetValue("")
  self.ddLoadClass:SetOnValueChanged(function()
    self:RefreshLoadSpecDropdown(nil, true)
  end)

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
    load = {},
    rules = {},
  }

  self:RegisterTabControls("general", {
    self.lblSpell, self.editSpell, self.autoFrame,
    self.lblAuraName, self.editAuraName,
    self.lblUnit, self.ddUnit,
    self.lblGroup, self.ddGroup,
    self.lblGroupCustom, self.editGroupCustom,
    self.cbOnlyMine, self.cbAlert, self.cbMoveWithGroup,
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

  self:RegisterTabControls("load", {
    self.lblLoadClass, self.ddLoadClass, self.lblLoadSpec, self.ddLoadSpec,
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
    load = {},
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
  if self.btnTabLoad then
    self.btnTabLoad:SetText(tr("tab_load"))
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
  if self.cbAggregateGroup and self.cbAggregateGroup.text then
    self.cbAggregateGroup.text:SetText(tr("lbl_aggregate_group"))
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
  if self.cbMoveWithGroup and self.cbMoveWithGroup.text then
    self.cbMoveWithGroup.text:SetText(tr("lbl_move_with_group"))
  end
  self.lblLowTimeAura:SetText(tr("lbl_low_time_aura"))
  if self.lblLoadClass then self.lblLoadClass:SetText(tr("lbl_load_class")) end
  if self.lblLoadSpec then self.lblLoadSpec:SetText(tr("lbl_load_spec")) end
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

function UI:BuildLocalizationPanel()
  if self.localizationFrame then
    return
  end

  local f = CreateFrame("Frame", "AuraLiteLocalizationFrame", UIParent, "BasicFrameTemplateWithInset")
  f:SetSize(460, 318)
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
  f.lblLanguage:SetPoint("TOPLEFT", 18, -52)

  f.ddLanguage = C:CreateDropdown(f, 220)
  f.ddLanguage:SetPoint("TOPLEFT", 8, -74)
  f.ddLanguage:SetOptions(L:GetLanguageOptions())
  f.ddLanguage:SetValue(L:GetLanguage())

  f.lblTheme = C:CreateLabel(f, "", "GameFontHighlight")
  f.lblTheme:SetPoint("TOPLEFT", 18, -114)
  f.ddTheme = C:CreateDropdown(f, 220)
  f.ddTheme:SetPoint("TOPLEFT", 8, -136)
  if ns.UISkin then
    f.ddTheme:SetOptions(ns.UISkin:GetThemeOptions())
  end
  f.ddTheme:SetValue((ns.db and ns.db.options and ns.db.options.uiTheme) or "modern")

  f.lblTexture = C:CreateLabel(f, "", "GameFontHighlight")
  f.lblTexture:SetPoint("TOPLEFT", 18, -178)
  f.editTexture = C:CreateEditBox(f, 410, 20, false)
  f.editTexture:SetPoint("TOPLEFT", 18, -196)
  f.editTexture:SetText((ns.db and ns.db.options and ns.db.options.uiTexturePath) or "")
  f.lblTextureHelp = C:CreateLabel(f, "", "GameFontDisableSmall")
  f.lblTextureHelp:SetPoint("TOPLEFT", 18, -220)

  f.btnApply = C:CreateButton(f, "", 100, 22, function()
    local code = f.ddLanguage:GetValue() or "enUS"
    local applied = L:SetLanguage(code)

    if ns.UISkin then
      ns.UISkin:EnsureOptionsDefaults(ns.db.options)
      local theme = f.ddTheme and f.ddTheme:GetValue() or "modern"
      if theme == "modern" or theme == "sky" or theme == "classic" then
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
  if self.cbAggregateGroup then
    self.cbAggregateGroup:SetChecked(ns.db.options.aggregateByGroup == true)
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

