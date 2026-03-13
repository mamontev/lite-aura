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

local function createCardBackdrop(frame)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(frame)
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(0.04, 0.08, 0.16, 0.72)
  frame:SetBackdropBorderColor(0.22, 0.34, 0.48, 0.74)
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
  if showAdvanced ~= true and tabKey == "Advanced" then
    return false
  end
  return true
end

local function addInfoBox(parent, y, title, body, height)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createCardBackdrop(frame)
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

local function createCard(parent, y, title, body, height)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createCardBackdrop(frame)
  frame:SetHeight(height or 96)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -14, 0)

  frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.heading:SetPoint("TOPLEFT", 12, -10)
  frame.heading:SetText(title or "")

  frame.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.desc:SetPoint("TOPLEFT", 12, -28)
  frame.desc:SetPoint("RIGHT", -12, 0)
  frame.desc:SetJustifyH("LEFT")
  frame.desc:SetText(body or "")

  frame.content = CreateFrame("Frame", nil, frame)
  frame.content:SetPoint("TOPLEFT", 10, -46)
  frame.content:SetPoint("TOPRIGHT", -10, -46)
  frame.content:SetHeight(math.max(24, (height or 96) - 56))

  return frame
end

local function setTabVisual(btn, active)
  if not btn then
    return
  end

  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btn, active)
    Skin:SetButtonVariant(btn, "tab")
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
    self.titleText:SetText("")
    self.subtitle:SetText("Select an aura from the list or create a new one.")
    if self.previewBannerText then
      self.previewBannerText:SetText("No aura selected")
    end
    if self.previewBannerHint then
      self.previewBannerHint:SetText("Pick an aura from the list to see a live draft preview here.")
    end
    return
  end
  self.titleText:SetText("")
  self.subtitle:SetText(string.format("Unit: %s | Tracking: %s", tostring(self.draft.unit or "player"), getTrackingSummary(self.draft)))
  if self.previewBannerText then
    local dirty = S and S.Get and S:Get().dirty == true
    local auraName = tostring(self.draft.name or self.draft.displayName or "Selected Aura")
    self.previewBannerText:SetText(string.format("%s | %s", auraName, dirty and "Unsaved changes" or "Saved"))
  end
  if self.previewBannerHint then
    self.previewBannerHint:SetText("The selected aura is rendered as a preview placeholder while you edit. Display changes update live before you save.")
  end
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
  local tab = (S and S.Get and S:Get().activeTab) or "Tracking"
  if not isTabAvailable(self.draft, tab, self.showAdvanced) then
    tab = "Tracking"
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
  if key == "group" then
    self.draft.groupID = value
  elseif key == "groupID" then
    self.draft.group = value
  end

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
    self:RenderTab(self.currentTab or "Tracking")
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
    self:RenderTab(self.currentTab or "Tracking")
    self:RefreshLivePreview(true)
    return
  end

  if key == "loadClassToken" and self.currentTab == "Advanced" then
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

function AuraEditorPanel:RenderGenericFields(tab, yStart, parent, leftInset, rightInset)
  local fields = tab.fields or tab or {}
  local y = yStart
  parent = parent or self.content
  leftInset = tonumber(leftInset) or 16
  rightInset = tonumber(rightInset) or -24
  for i = 1, #fields do
    local field = fields[i]
    local widget = FieldFactory:CreateField(parent, field, self.draft, function(fKey, fValue)
      self:OnFieldChanged(fKey, fValue)
    end)
    widget:SetPoint("TOPLEFT", leftInset, y)
    widget:SetPoint("RIGHT", rightInset, 0)
    widget:Show()
    y = y - widget:GetHeight() - 8
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
  end
  return y
end

function AuraEditorPanel:RenderAppearanceCard(y, title, body, fields)
  local cardHeight = 72
  for i = 1, #(fields or {}) do
    local field = fields[i]
    cardHeight = cardHeight + ((field.widget == "multiline") and 100 or 60)
  end
  local card = createCard(self.content, y, title, body, cardHeight)
  self.fieldWidgets[#self.fieldWidgets + 1] = card
  local nextY = self:RenderGenericFields(fields or {}, -2, card.content, 2, -2)
  card.content:SetHeight(math.max(24, -nextY + 8))
  return y - cardHeight - 10
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

  if tabKey == "Tracking" then
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
      btnConfirmed:SetText("Read Live Aura")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnConfirmed, "segment")
      end

      local btnEstimated = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnEstimated:SetSize(200, 24)
      btnEstimated:SetPoint("LEFT", btnConfirmed, "RIGHT", 8, 0)
      btnEstimated:SetText("Estimate From My Cast")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnEstimated, "segment")
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
    elseif isDirectAuraTracking(self.draft) then
      local infoFrame = addInfoBox(
        self.content,
        y,
        "Live aura read",
        "AuraLite reads the selected target directly when Blizzard allows it. This is the most literal mode, but target aura data can still be restricted in combat.",
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
      modeLabel:SetText("Rule behavior:")

      local btnShow = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnShow:SetSize(128, 22)
      btnShow:SetPoint("LEFT", modeLabel, "RIGHT", 8, 0)
      btnShow:SetText("Show / Produce")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnShow, "segment")
      end

      local btnConsume = CreateFrame("Button", nil, modeFrame, "UIPanelButtonTemplate")
      btnConsume:SetSize(128, 22)
      btnConsume:SetPoint("LEFT", btnShow, "RIGHT", 6, 0)
      btnConsume:SetText("Consume / Hide")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(btnConsume, "segment")
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
        self:RenderTab("Tracking")
      end)
      btnConsume:SetScript("OnClick", function()
        self:ApplyRuleMode("consume")
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:RenderTab("Tracking")
      end)
      refreshModeButtons()

      self.fieldWidgets[#self.fieldWidgets + 1] = modeFrame
      y = y - 40

      self.ruleBuilder = Widgets.RuleBuilderWidget:Create(self.content, function()
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:ValidateDraft()
        self:RenderTab("Tracking")
      end)
      self.ruleBuilder.frame:SetPoint("TOPLEFT", 12, y)
      self.ruleBuilder.frame:SetPoint("RIGHT", -14, 0)
      self.ruleBuilder.frame:Show()
      self.ruleBuilder:SetDraft(self.draft)
      y = y - self.ruleBuilder.frame:GetHeight() - 10
    end

    local fields = tab.fields or {}
    local filtered = {}
    for i = 1, #fields do
      local key = fields[i].key
      if isDirectAuraTracking(self.draft) then
        if key == "unit" or key == "spellID" then
          filtered[#filtered + 1] = fields[i]
        end
      elseif isEstimatedTargetTracking(self.draft) then
        if key == "unit" or key == "spellID" or key == "castSpellIDs" or key == "estimatedDuration" then
          filtered[#filtered + 1] = fields[i]
        end
      elseif not self.showAdvanced then
        if key == "unit" or key == "spellID" or key == "castSpellIDs" then
          filtered[#filtered + 1] = fields[i]
        end
      else
        filtered[#filtered + 1] = fields[i]
      end
    end
    y = self:RenderGenericFields(filtered, y)
  elseif tabKey == "Appearance" then
    local allFields = tab.fields or {}
    local byKey = {}
    for i = 1, #allFields do
      if allFields[i] then
        byKey[allFields[i].key] = allFields[i]
      end
    end
    local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")

    y = self:RenderAppearanceCard(y, "Layout", "Define the overall shape and placement of this aura.", {
      byKey.name,
      byKey.group,
      byKey.displayMode,
      (mode ~= "icon") and byKey.barSide or nil,
    })

    if mode == "icon" or mode == "iconbar" then
      y = self:RenderAppearanceCard(y, "Icon", "Adjust icon size for quick recognition.", {
        byKey.iconWidth,
        byKey.iconHeight,
      })
    end

    if mode == "bar" or mode == "iconbar" then
      y = self:RenderAppearanceCard(y, "Bar", "Tune bar size, readability and timing feedback. Changes update live.", {
        byKey.barWidth,
        byKey.barHeight,
        byKey.showTimerText,
        byKey.barColor,
        byKey.barTexture,
        byKey.lowTime,
      })
    end

    y = self:RenderAppearanceCard(y, "Text", "Optional helper text layered onto the aura.", {
      byKey.customText,
    })
  elseif tabKey == "Advanced" then
    local intro = addInfoBox(
      self.content,
      y,
      "Advanced settings",
      "Use this section for technical tuning, conditions, load restrictions and notes. Most auras do not need anything here.",
      84
    )
    self.fieldWidgets[#self.fieldWidgets + 1] = intro
    y = y - 94

    if not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) and Widgets.ConditionTreeWidget and Widgets.ConditionTreeWidget.Create then
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

    local fields = tab.fields or {}
    local filtered = {}
    for i = 1, #fields do
      local key = fields[i].key
      local include = true
      if isDirectAuraTracking(self.draft) or isEstimatedTargetTracking(self.draft) then
        if key == "conditionLogic" or key == "talentSpellIDs" or key == "requiredAuraSpellIDs" or key == "duration" or key == "ruleName" or key == "ruleID" then
          include = false
        end
      end
      if include then
        filtered[#filtered + 1] = fields[i]
      end
    end
    y = self:RenderGenericFields(filtered, y)
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
  o.currentTab = "Tracking"
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

  o.previewBanner = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  createBackdrop(o.previewBanner)
  o.previewBanner:SetPoint("TOPLEFT", 10, -48)
  o.previewBanner:SetPoint("TOPRIGHT", -12, -48)
  o.previewBanner:SetHeight(46)

  o.previewBannerText = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.previewBannerText:SetPoint("TOPLEFT", 10, -8)
  o.previewBannerText:SetText("No aura selected")

  o.previewBannerHint = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.previewBannerHint:SetPoint("TOPLEFT", 10, -24)
  o.previewBannerHint:SetPoint("RIGHT", -10, 0)
  o.previewBannerHint:SetJustifyH("LEFT")
  o.previewBannerHint:SetText("Pick an aura from the list to see a live draft preview here.")

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 10, -98)
  o.tabStrip:SetPoint("TOPRIGHT", -138, -98)
  o.tabStrip:SetHeight(26)

  o.btnMode = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnMode:SetSize(118, 22)
  o.btnMode:SetPoint("TOPRIGHT", -12, -98)
  o.btnMode:SetText("More Options")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnMode, "ghost")
  end
  o.btnMode:SetScript("OnClick", function()
    o.showAdvanced = not o.showAdvanced
    o.btnMode:SetText(o.showAdvanced and "Simple View" or "More Options")
    o:RefreshTabButtons()
    local activeTab = o.currentTab or "Tracking"
    if not isTabAvailable(o.draft, activeTab, o.showAdvanced) then
      activeTab = "Tracking"
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
      Skin:SetButtonVariant(btn, "tab")
    end
    btn:SetScript("OnClick", function()
      o:SelectTab(tab.key)
    end)
    o.tabs[tab.key] = btn
    x = x + 100
  end

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame, "UIPanelScrollFrameTemplate")
  o.scroll:SetPoint("TOPLEFT", 8, -126)
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
      o:UpdateHeader()
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


