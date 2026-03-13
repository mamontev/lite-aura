local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local V = UI.ValidationBus
local Schemas = UI.Schemas
local Repo = UI.AuraRepository
local RuleRepo = UI.RuleRepository
local FieldFactory = UI.FieldFactory
local Widgets = UI.Widgets or {}
local Skin = ns.UISkin

local AuraEditorPanel = {}
AuraEditorPanel.__index = AuraEditorPanel

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.03, 0.08, 0.18, 0.72)
  frame:SetBackdropBorderColor(0.12, 0.50, 0.82, 0.90)
end

local function isDirectAuraTracking(draft)
  if UI and UI.Bindings and UI.Bindings.IsDirectAuraTracking then
    return UI.Bindings:IsDirectAuraTracking(draft)
  end
  return tostring(draft and draft.unit or "player") == "target"
end

local function isEstimatedTargetTracking(draft)
  if UI and UI.Bindings and UI.Bindings.IsEstimatedTargetDebuffTracking then
    return UI.Bindings:IsEstimatedTargetDebuffTracking(draft)
  end
  return false
end

local function getTrackingSummary(draft)
  draft = draft or {}
  local unit = tostring(draft.unit or "player")
  if unit == "target" then
    if isEstimatedTargetTracking(draft) then
      return "Estimated from your cast"
    end
    return "Confirmed read"
  end
  return "Rule-based cast trigger"
end

local function isTabAvailable(draft, tabKey, showAdvanced)
  if not draft then
    return false
  end
  if showAdvanced ~= true and (tabKey == "Advanced" or tabKey == "Conditions") then
    return false
  end
  if isEstimatedTargetTracking(draft) then
    return tabKey ~= "Conditions" and tabKey ~= "Actions" and tabKey ~= "Advanced"
  end
  if isDirectAuraTracking(draft) then
    return tabKey ~= "Conditions" and tabKey ~= "Actions"
  end
  return true
end

local function addInfoBox(parent, y, title, body, height)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createBackdrop(frame)
  frame:SetHeight(height or 86)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -14, 0)

  local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  heading:SetPoint("TOPLEFT", 10, -8)
  heading:SetText(title or "")

  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  text:SetPoint("TOPLEFT", 10, -26)
  text:SetPoint("RIGHT", -10, 0)
  text:SetJustifyH("LEFT")
  text:SetText(body or "")

  return frame
end

local function setTabVisual(btn, active)
  if not btn then
    return
  end

  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btn, active)
    Skin:SetButtonVariant(btn, active and "primary" or "ghost")
    return
  end

  local fs = btn.GetFontString and btn:GetFontString() or btn.Text
  if active then
    btn:SetNormalFontObject("GameFontNormal")
    if fs and fs.SetTextColor then
      fs:SetTextColor(1.0, 0.85, 0.2)
    end
  else
    btn:SetNormalFontObject("GameFontHighlight")
    if fs and fs.SetTextColor then
      fs:SetTextColor(0.8, 0.88, 1.0)
    end
  end
end

local LIVE_PREVIEW_FIELDS = {
  name = true,
  displayName = true,
  spellID = true,
  unit = true,
  trackingMode = true,
  iconMode = true,
  customTexture = true,
  barTexture = true,
  customText = true,
  timerVisual = true,
  iconWidth = true,
  iconHeight = true,
  barWidth = true,
  barHeight = true,
  showTimerText = true,
  barColor = true,
  barSide = true,
  timerAnchor = true,
  timerOffsetX = true,
  timerOffsetY = true,
  customTextAnchor = true,
  customTextOffsetX = true,
  customTextOffsetY = true,
  lowTime = true,
  estimatedDuration = true,
}

function AuraEditorPanel:RefreshLivePreview(forceRefresh)
  if not ns.state then
    return
  end

  if not self.draft then
    ns.state.selectedAura = nil
    ns.state.selectedAuraPreviewItem = nil
    if forceRefresh and ns.EventRouter and ns.EventRouter.RefreshAll then
      ns.EventRouter:RefreshAll()
    end
    return
  end

  ns.state.selectedAura = {
    key = tostring(self.currentAuraId or self.draft._sourceKey or self.draft.id or ""),
    unit = tostring(self.draft.unit or "player"),
    spellID = tonumber(self.draft.spellID) or 0,
    instanceUID = tostring(self.draft.instanceUID or ""),
  }

  local previewItem = nil
  if UI and UI.Bindings and UI.Bindings.ToSettingsDataModel and ns.SettingsData and ns.SettingsData.BuildWatchItemFromModel then
    local settingsModel = UI.Bindings:ToSettingsDataModel(self.draft)
    previewItem = ns.SettingsData:BuildWatchItemFromModel(settingsModel)
  end
  ns.state.selectedAuraPreviewItem = previewItem

  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
end

function AuraEditorPanel:ValidateDraft()
  local issues = {}
  if not self.draft then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  if tostring(self.draft.name or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "name", message = "Add a short aura name so it is easier to find later." }
  end

  local sid = tonumber(self.draft.spellID)
  if not sid or sid <= 0 then
    issues[#issues + 1] = { severity = "error", path = "spellID", message = "Aura SpellID is required." }
  end

  if isEstimatedTargetTracking(self.draft) then
    if tostring(self.draft.castSpellIDs or "") == "" then
      issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "Add at least one spell you cast to start this debuff timer." }
    end
    if tonumber(self.draft.estimatedDuration) == nil or tonumber(self.draft.estimatedDuration) <= 0 then
      issues[#issues + 1] = { severity = "error", path = "estimatedDuration", message = "Set the expected debuff duration in seconds." }
    end
  elseif not isDirectAuraTracking(self.draft) and tostring(self.draft.triggerType or "cast") == "cast" and tostring(self.draft.castSpellIDs or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "Add at least one trigger spell to drive this aura." }
  end

  if #issues == 0 then
    V:SetStatus("ok", "Setup looks ready to save.")
  else
    V:SetEntries(issues)
  end
end

function AuraEditorPanel:UpdateHeader()
  if not self.draft then
    self.titleText:SetText("Aura Editor")
    self.subtitle:SetText("Select an aura from the list or create a new one.")
    return
  end
  self.titleText:SetText(string.format("Aura Editor - %s", tostring(self.draft.name or "New Aura")))
  self.subtitle:SetText(string.format("SpellID: %s | Unit: %s | Tracking: %s | Group: %s", tostring(self.draft.spellID or "?"), tostring(self.draft.unit or "player"), getTrackingSummary(self.draft), tostring(self.draft.group or "-")))
end

function AuraEditorPanel:RefreshTabButtons()
  local x = 0
  for i = 1, #(Schemas and Schemas.EditorTabs or {}) do
    local tab = Schemas.EditorTabs[i]
    local btn = self.tabs and self.tabs[tab.key]
    if btn then
      if isTabAvailable(self.draft, tab.key, self.showAdvanced) then
        btn:Show()
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", x, 0)
        x = x + 100
      else
        btn:Hide()
      end
    end
  end
end

function AuraEditorPanel:ApplyRuleMode(mode)
  if not self.draft or isDirectAuraTracking(self.draft) then
    return
  end
  mode = (tostring(mode or "produce") == "consume") and "consume" or "produce"
  self.triggerEditMode = mode
  self.draft.actionMode = mode

  local auraSpellID = tonumber(self.draft.spellID)
  local rule = nil
  if RuleRepo and RuleRepo.GetRuleForAuraByMode and auraSpellID and auraSpellID > 0 then
    rule = RuleRepo:GetRuleForAuraByMode(auraSpellID, mode)
  end

  if rule and UI and UI.Bindings and UI.Bindings.ApplyRuleToDraft then
    UI.Bindings:ApplyRuleToDraft(self.draft, rule)
  else
    local base = auraSpellID and ("aura" .. tostring(auraSpellID)) or "aura"
    self.draft.ruleID = base
    self.draft.ruleName = (mode == "consume") and "Consume Aura" or "Show Aura"
    self.draft.castSpellIDs = tostring(self.draft.castSpellIDs or "")
    self.draft.conditionLogic = self.draft.conditionLogic or "all"
    self.draft.talentSpellIDs = tostring(self.draft.talentSpellIDs or "")
    self.draft.requiredAuraSpellIDs = (mode == "consume" and auraSpellID) and tostring(auraSpellID) or tostring(self.draft.requiredAuraSpellIDs or "")
    self.draft.duration = tonumber(self.draft.duration) or 8
  end

  if self.ruleBuilder and self.ruleBuilder.SetDraft then
    self.ruleBuilder:SetDraft(self.draft)
  end
end
function AuraEditorPanel:LoadAura(auraId)
  self.draft = Repo:GetAuraDraft(auraId)
  self.triggerEditMode = self.triggerEditMode or "produce"
  self.currentAuraId = self.draft and self.draft.id or auraId

  self:UpdateHeader()
  self:RefreshTabButtons()
  local tab = (S and S.Get and S:Get().activeTab) or "Trigger"
  if not isTabAvailable(self.draft, tab, self.showAdvanced) then
    tab = "Trigger"
    if S and S.SetActiveTab then
      S:SetActiveTab(tab)
    end
  end
  self:RenderTab(tab)
  self:ValidateDraft()
  self:RefreshLivePreview(true)
end

function AuraEditorPanel:OnFieldChanged(key, value)
  if not self.draft then
    return
  end

  self.draft[key] = value

  if key == "unit" then
    self.draft.triggerType = (tostring(value or "player") == "target") and "aura" or "cast"
    if tostring(value or "player") ~= "target" then
      self.draft.trackingMode = "confirmed"
    else
      self.draft.trackingMode = tostring(self.draft.trackingMode or "confirmed")
    end
    if self.draft.triggerType == "aura" then
      self.draft.actionMode = "produce"
    end
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RefreshTabButtons()
    self:RenderTab(self.currentTab or "Trigger")
    self:RefreshLivePreview(true)
    return
  end

  if key == "trackingMode" then
    if tostring(self.draft.unit or "player") == "target" and tostring(value or "confirmed") == "estimated" then
      self.draft.triggerType = "cast"
      self.draft.actionMode = "produce"
      self.draft.onlyMine = true
      if not tonumber(self.draft.estimatedDuration) or tonumber(self.draft.estimatedDuration) <= 0 then
        self.draft.estimatedDuration = tonumber(self.draft.duration) or 8
      end
    else
      self.draft.triggerType = "aura"
    end
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RefreshTabButtons()
    self:RenderTab(self.currentTab or "Trigger")
    self:RefreshLivePreview(true)
    return
  end

  if key == "loadClassToken" and (self.currentTab == "Advanced" or self.currentTab == "Conditions") then
    self:RenderTab(self.currentTab)
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end

  self:UpdateHeader()
  self:ValidateDraft()

  if self.ruleBuilder then
    self.ruleBuilder:SetDraft(self.draft)
  end
  if self.conditionTree then
    self.conditionTree:SetDraft(self.draft)
  end

  if E then
    E:Emit(E.Names.STATE_CHANGED, S and S:Get() or nil)
  end

  if LIVE_PREVIEW_FIELDS[key] then
    self:RefreshLivePreview(false)
  end
end

function AuraEditorPanel:ClearTabContent()
  for i = 1, #(self.fieldWidgets or {}) do
    local w = self.fieldWidgets[i]
    if w then
      w:Hide()
      w:SetParent(nil)
    end
  end
  self.fieldWidgets = {}

  if self.ruleBuilder and self.ruleBuilder.frame then
    self.ruleBuilder.frame:Hide()
    self.ruleBuilder.frame:SetParent(nil)
  end
  self.ruleBuilder = nil

  if self.conditionTree and self.conditionTree.frame then
    self.conditionTree.frame:Hide()
    self.conditionTree.frame:SetParent(nil)
  end
  self.conditionTree = nil
end

function AuraEditorPanel:RenderGenericFields(tab, yStart)
  local fields = tab.fields or tab or {}
  local y = yStart
  for i = 1, #fields do
    local field = fields[i]
    local widget = FieldFactory:CreateField(self.content, field, self.draft, function(fKey, fValue)
      self:OnFieldChanged(fKey, fValue)
    end)
    widget:SetPoint("TOPLEFT", 16, y)
    widget:SetPoint("RIGHT", -24, 0)
    widget:Show()
    y = y - widget:GetHeight() - 8
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
  end
  return y
end

function AuraEditorPanel:RenderTab(tabKey)
  self.currentTab = tabKey
  self:ClearTabContent()

  if not self.content or not self.draft then
    return
  end

  local tab = Schemas and Schemas:GetTab(tabKey) or nil
  if not tab then
    return
  end

  for key, btn in pairs(self.tabs or {}) do
    setTabVisual(btn, key == tabKey)
  end
  self:RefreshTabButtons()

  local y = -12

  if tabKey == "Trigger" then
    if tostring(self.draft.unit or "player") == "target" then
      local modeFrame = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
      createBackdrop(modeFrame)
      modeFrame:SetHeight(60)
      modeFrame:SetPoint("TOPLEFT", 12, y)
      modeFrame:SetPoint("RIGHT", -14, 0)

      local modeLabel = modeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      modeLabel:SetPoint("TOPLEFT", 10, -8)
      modeLabel:SetText("How should AuraLite track this target aura?")

      local btnConfirmed = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnConfirmed:SetSize(172, 24)
      btnConfirmed:SetPoint("BOTTOMLEFT", 10, 8)
      btnConfirmed:SetText("Confirmed Aura Read")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnConfirmed, "ghost")
      end

      local btnEstimated = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnEstimated:SetSize(200, 24)
      btnEstimated:SetPoint("LEFT", btnConfirmed, "RIGHT", 8, 0)
      btnEstimated:SetText("Estimated Debuff From My Cast")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnEstimated, "ghost")
      end

      local function refreshTrackingButtons()
        local estimated = isEstimatedTargetTracking(self.draft)
        setTabVisual(btnConfirmed, not estimated)
        setTabVisual(btnEstimated, estimated)
      end

      btnConfirmed:SetScript("OnClick", function()
        self:OnFieldChanged("trackingMode", "confirmed")
      end)
      btnEstimated:SetScript("OnClick", function()
        self:OnFieldChanged("trackingMode", "estimated")
      end)
      refreshTrackingButtons()

      self.fieldWidgets[#self.fieldWidgets + 1] = modeFrame
      y = y - 68
    end

    if isEstimatedTargetTracking(self.draft) then
      local infoFrame = addInfoBox(
        self.content,
        y,
        "Best for your own debuffs",
        "AuraLite watches the SpellIDs you cast, then starts a local timer on your current target using the duration you enter below.",
        92
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 102

      local stepsFrame = addInfoBox(
        self.content,
        y,
        "Setup checklist",
        "1. Choose the aura SpellID to show.\n2. Add the spell(s) you cast to apply or refresh it.\n3. Enter the expected duration.\n4. Save and test on a dummy or boss target.\n5. This is a local estimate, not a confirmed aura read.",
        118
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = stepsFrame
      y = y - 128

      local fieldsFrame = addInfoBox(
        self.content,
        y,
        "Quick setup fields",
        "Aura SpellID To Show = the icon and timer you want on screen.\nSpellIDs I Cast = the casts AuraLite listens for.\nExpected Duration = how long the timer should run after your cast succeeds.",
        112
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = fieldsFrame
      y = y - 122
    elseif isDirectAuraTracking(self.draft) then
      local infoFrame = addInfoBox(
        self.content,
        y,
        "Confirmed aura read",
        "AuraLite tries to read the aura directly from the selected target. Blizzard can restrict target aura data in combat, so this mode is literal but not always complete.",
        92
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 102
    elseif Widgets.RuleBuilderWidget and Widgets.RuleBuilderWidget.Create then
      local modeFrame = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
      createBackdrop(modeFrame)
      modeFrame:SetHeight(34)
      modeFrame:SetPoint("TOPLEFT", 12, y)
      modeFrame:SetPoint("RIGHT", -14, 0)

      local modeLabel = modeFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      modeLabel:SetPoint("LEFT", 10, 0)
      modeLabel:SetText("Editing Rule:")

      local btnShow = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnShow:SetSize(128, 22)
      btnShow:SetPoint("LEFT", modeLabel, "RIGHT", 8, 0)
      btnShow:SetText("Show / Produce")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnShow, "ghost")
      end

      local btnConsume = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnConsume:SetSize(128, 22)
      btnConsume:SetPoint("LEFT", btnShow, "RIGHT", 6, 0)
      btnConsume:SetText("Consume / Hide")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnConsume, "ghost")
      end

      local activeMode = (tostring(self.triggerEditMode or self.draft.actionMode or "produce") == "consume") and "consume" or "produce"
      if not self.ruleBuilder or not self.ruleBuilder.frame then
        self:ApplyRuleMode(activeMode)
      end

      local function refreshModeButtons()
        local isConsume = tostring(self.triggerEditMode or "produce") == "consume"
        setTabVisual(btnShow, not isConsume)
        setTabVisual(btnConsume, isConsume)
      end

      btnShow:SetScript("OnClick", function()
        self:ApplyRuleMode("produce")
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:RenderTab("Trigger")
      end)
      btnConsume:SetScript("OnClick", function()
        self:ApplyRuleMode("consume")
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:RenderTab("Trigger")
      end)
      refreshModeButtons()

      self.fieldWidgets[#self.fieldWidgets + 1] = modeFrame
      y = y - 40

      self.ruleBuilder = Widgets.RuleBuilderWidget:Create(self.content, function()
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:ValidateDraft()
        self:RenderTab("Trigger")
      end)
      self.ruleBuilder.frame:SetPoint("TOPLEFT", 12, y)
      self.ruleBuilder.frame:SetPoint("RIGHT", -14, 0)
      self.ruleBuilder.frame:Show()
      self.ruleBuilder:SetDraft(self.draft)
      y = y - self.ruleBuilder.frame:GetHeight() - 10

      local descFrame = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
      createBackdrop(descFrame)
      descFrame:SetHeight(98)
      descFrame:SetPoint("TOPLEFT", 12, y)
      descFrame:SetPoint("RIGHT", -14, 0)

      local lbl = descFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      lbl:SetPoint("TOPLEFT", 10, -8)
      lbl:SetText("Persisted rules for this aura")

      local text = descFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      text:SetPoint("TOPLEFT", 10, -24)
      text:SetPoint("RIGHT", -10, 0)
      text:SetJustifyH("LEFT")

      local desc = ""
      local sid = tonumber(self.draft.spellID)
      if sid and sid > 0 and RuleRepo and RuleRepo.DescribeRuleForAura then
        desc = RuleRepo:DescribeRuleForAura(sid)
      end
      if desc == "" then
        desc = "No persisted rules yet. Create one Show rule and one Consume rule from the selector above, then Save Aura."
      end
      text:SetText(desc)

      self.fieldWidgets[#self.fieldWidgets + 1] = descFrame
      y = y - 106
    end
  elseif tabKey == "Conditions" and Widgets.ConditionTreeWidget and Widgets.ConditionTreeWidget.Create then
    self.conditionTree = Widgets.ConditionTreeWidget:Create(self.content, function()
      if S and S.SetDirty then
        S:SetDirty(true)
      end
      self:ValidateDraft()
      self:UpdateHeader()
    end)
    self.conditionTree.frame:SetPoint("TOPLEFT", 12, y)
    self.conditionTree.frame:SetPoint("RIGHT", -14, 0)
    self.conditionTree.frame:Show()
    self.conditionTree:SetDraft(self.draft)
    y = y - self.conditionTree.frame:GetHeight() - 10
  end

  if tabKey ~= "Conditions" then
    local fields = tab.fields or {}
    if isDirectAuraTracking(self.draft) and tabKey == "Trigger" then
      local filtered = {}
      for i = 1, #fields do
        local key = fields[i].key
        if key == "unit" or key == "spellID" then
          filtered[#filtered + 1] = fields[i]
        end
      end
      fields = filtered
    elseif isEstimatedTargetTracking(self.draft) and tabKey == "Trigger" then
      local filtered = {}
      for i = 1, #fields do
        local key = fields[i].key
        if key == "unit" or key == "spellID" or key == "castSpellIDs" or key == "estimatedDuration" then
          filtered[#filtered + 1] = fields[i]
        end
      end
      fields = filtered
    elseif not self.showAdvanced and not isDirectAuraTracking(self.draft) and tabKey == "Trigger" then
      local filtered = {}
      for i = 1, #fields do
        local key = fields[i].key
        if key == "unit" or key == "spellID" or key == "castSpellIDs" then
          filtered[#filtered + 1] = fields[i]
        end
      end
      fields = filtered
    elseif isDirectAuraTracking(self.draft) and tabKey == "Actions" then
      local filtered = {}
      for i = 1, #fields do
        if fields[i].key ~= "actionMode" then
          filtered[#filtered + 1] = fields[i]
        end
      end
      fields = filtered
    elseif isEstimatedTargetTracking(self.draft) and tabKey == "Actions" then
      fields = {}
      local infoFrame = addInfoBox(
        self.content,
        y,
        "Automatic timer ending",
        "Estimated debuffs do not use Produce or Consume actions. AuraLite starts the timer from your cast list and removes it automatically when the estimated duration expires or the target dies.",
        86
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 96
    elseif tabKey == "Display" then
      local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")
      local filtered = {}
      for i = 1, #fields do
        local key = fields[i].key
        local include = true
        if mode == "icon" and (key == "barWidth" or key == "barHeight" or key == "barColor" or key == "barSide") then
          include = false
        elseif mode == "bar" and (key == "iconWidth" or key == "iconHeight" or key == "barSide") then
          include = false
        end
        if include then
          filtered[#filtered + 1] = fields[i]
        end
      end
      fields = filtered
    end
    y = self:RenderGenericFields(fields, y)
  end

  self.content:SetHeight(math.max(360, -y + 20))
  self:ValidateDraft()
end

function AuraEditorPanel:SelectTab(tabKey)
  if not isTabAvailable(self.draft, tabKey, self.showAdvanced) then
    return
  end
  if S and S.SetActiveTab then
    S:SetActiveTab(tabKey)
  end
  self:RenderTab(tabKey)
end

function AuraEditorPanel:DeleteCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local deleted, err = Repo and Repo.DeleteAura and Repo:DeleteAura(self.draft.id)
  if not deleted then
    V:SetStatus("error", tostring(err or "Delete failed"))
    return
  end

  self.currentAuraId = nil
  self.draft = nil
  self:UpdateHeader()
  self:ClearTabContent()
  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if ns.state then
    ns.state.selectedAura = nil
    ns.state.selectedAuraPreviewItem = nil
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  if S and S.SetSelectedAura then
    S:SetSelectedAura(nil, "delete")
  end
  V:SetStatus("ok", "Aura deleted.")
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "delete", value = true })
  end
end
function AuraEditorPanel:SaveCurrent()
  if not self.draft then
    return
  end

  if (not self.draft.id or tostring(self.draft.id) == "") and self.currentAuraId and tostring(self.currentAuraId) ~= "" then
    self.draft.id = tostring(self.currentAuraId)
    self.draft._sourceKey = tostring(self.currentAuraId)
  end

  local ok, savedId, err = Repo:SaveDraft(self.draft)
  if not ok then
    V:SetStatus("error", tostring(err or "Save failed"))
    return
  end

  self.draft.id = savedId or self.draft.id

  if RuleRepo and RuleRepo.SaveRuleFromDraft then
    local rok, rerr = RuleRepo:SaveRuleFromDraft(self.draft)
    if rok ~= true and rerr then
      V:Push("warn", "rule", tostring(rerr))
    end
  end

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if S and S.SetSelectedAura and savedId then
    S:SetSelectedAura(savedId, "save")
  end

  self:ValidateDraft()
  self:RefreshLivePreview(true)
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "save", value = savedId })
  end
end

function AuraEditorPanel:Create(parent)
  local o = setmetatable({}, self)
  o.fieldWidgets = {}
  o.currentTab = "Trigger"
  o.triggerEditMode = "produce"
  o.showAdvanced = false

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetAllPoints()
  createBackdrop(o.frame)

  o.titleText = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.titleText:SetPoint("TOPLEFT", 12, -10)
  o.titleText:SetText("Aura Editor")

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 12, -28)
  o.subtitle:SetPoint("RIGHT", -14, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("Select an aura from the list or create a new one.")

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 10, -48)
  o.tabStrip:SetPoint("TOPRIGHT", -138, -48)
  o.tabStrip:SetHeight(26)

  o.btnMode = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnMode:SetSize(118, 22)
  o.btnMode:SetPoint("TOPRIGHT", -12, -48)
  o.btnMode:SetText("More Options")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnMode, "ghost")
  end
  o.btnMode:SetScript("OnClick", function()
    o.showAdvanced = not o.showAdvanced
    o.btnMode:SetText(o.showAdvanced and "Simple View" or "More Options")
    o:RefreshTabButtons()
    local activeTab = o.currentTab or "Trigger"
    if not isTabAvailable(o.draft, activeTab, o.showAdvanced) then
      activeTab = "Trigger"
      if S and S.SetActiveTab then
        S:SetActiveTab(activeTab)
      end
    end
    o:RenderTab(activeTab)
  end)

  o.tabs = {}
  local x = 0
  for i = 1, #(Schemas and Schemas.EditorTabs or {}) do
    local tab = Schemas.EditorTabs[i]
    local btn = CreateFrame("Button", nil, o.tabStrip, "UIPanelButtonTemplate")
    btn:SetSize(96, 22)
    btn:SetPoint("TOPLEFT", x, 0)
    btn:SetText(tab.label or tab.key)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "ghost")
    end
    btn:SetScript("OnClick", function()
      o:SelectTab(tab.key)
    end)
    o.tabs[tab.key] = btn
    x = x + 100
  end

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame, "UIPanelScrollFrameTemplate")
  o.scroll:SetPoint("TOPLEFT", 8, -76)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 48)

  o.content = CreateFrame("Frame", nil, o.scroll)
  o.content:SetSize(1, 1)
  o.scroll:SetScrollChild(o.content)

  o.status = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.status:SetPoint("BOTTOMLEFT", 12, 38)
  o.status:SetPoint("RIGHT", -12, 0)
  o.status:SetJustifyH("LEFT")
  o.status:SetText("Ready")

  o.btnSave = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSave:SetSize(110, 24)
  o.btnSave:SetPoint("BOTTOMLEFT", 10, 10)
  o.btnSave:SetText("Save Aura")
  o.btnSave:SetScript("OnClick", function()
    o:SaveCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnSave, "primary")
  end

  o.btnReset = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnReset:SetSize(90, 24)
  o.btnReset:SetPoint("LEFT", o.btnSave, "RIGHT", 8, 0)
  o.btnReset:SetText("Reset")
  o.btnReset:SetScript("OnClick", function()
    o:LoadAura(o.currentAuraId)
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnReset, "ghost")
  end

  o.btnDelete = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnDelete:SetSize(90, 24)
  o.btnDelete:SetPoint("LEFT", o.btnReset, "RIGHT", 8, 0)
  o.btnDelete:SetText("Delete")
  o.btnDelete:SetScript("OnClick", function()
    o:DeleteCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnDelete, "danger")
  end

  if E then
    E:On(E.Names.AURA_SELECTED, function(payload)
      o:LoadAura(payload and payload.auraId or nil)
    end)

    E:On(E.Names.NEW_AURA, function()
      local draft = Repo:CreateDraft()
      if S and S.SetSelectedAura then
        S:SetSelectedAura(draft.id, "new")
      end
      o:LoadAura(draft.id)
    end)

    E:On(E.Names.STATE_CHANGED, function(state)
      if not state or not o.status then
        return
      end
      local dirtyTag = state.dirty and "Unsaved changes" or "All changes saved"
      local tracking = getTrackingSummary(o.draft)
      local mode = o.showAdvanced and "Full options" or "Simple setup"
      o.status:SetText(dirtyTag .. " | " .. tracking .. " | " .. mode)
    end)
  end

  if V then
    V:Subscribe(function(snapshot)
      if not o.status then
        return
      end
      local status = snapshot and snapshot.status or "ok"
      local entries = snapshot and snapshot.entries or {}
      local msg = (#entries > 0 and entries[1].message) or "Ready"
      if status == "error" then
        o.status:SetTextColor(1, 0.35, 0.35)
      elseif status == "warn" then
        o.status:SetTextColor(1, 0.82, 0.2)
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
      end
      o.status:SetText(msg)
    end)
  end

  o:LoadAura(nil)
  return o
end

Panels.AuraEditorPanel = AuraEditorPanel


