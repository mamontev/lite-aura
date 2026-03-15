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

local function applyGroupConfigToDraft(draft, groupID)
  if type(draft) ~= "table" then
    return
  end
  groupID = tostring(groupID or "")
  draft.group = groupID
  draft.groupID = groupID
  if groupID == "" then
    draft.groupName = ""
    draft.groupDirection = "RIGHT"
    draft.groupSpacing = 4
    draft.groupSort = "list"
    draft.groupWrapAfter = 0
    draft.groupOffsetX = 0
    draft.groupOffsetY = 0
    return
  end

  if ns.SettingsData and ns.SettingsData.GetGroupConfig then
    local groupConfig = ns.SettingsData:GetGroupConfig(groupID)
    local layout = (groupConfig and groupConfig.layout) or {}
    draft.groupName = tostring(groupConfig and groupConfig.name or draft.groupName or "")
    draft.groupDirection = tostring(layout.direction or "RIGHT")
    draft.groupSpacing = tonumber(layout.spacing) or 4
    draft.groupSort = tostring(layout.sort or "list")
    draft.groupWrapAfter = tonumber(layout.wrapAfter) or 0
    draft.groupOffsetX = tonumber(layout.nudgeX) or 0
    draft.groupOffsetY = tonumber(layout.nudgeY) or 0
  end
end

local function inferTrackingPreset(draft)
  draft = draft or {}
  local unit = tostring(draft.unit or "player")
  if unit == "target" and isEstimatedTargetTracking(draft) then
    return "debuff_target"
  end
  if unit == "target" then
    return "target_aura"
  end
  return "buff_player"
end

local function shouldShowConsumeBehavior(draft)
  draft = draft or {}
  local maxStacks = tonumber(draft.maxStacks) or 1
  local stackBehavior = tostring(draft.stackBehavior or "replace")
  return maxStacks > 1 or stackBehavior == "add"
end

local function isStackingSyntheticAura(draft)
  draft = draft or {}
  local maxStacks = tonumber(draft.maxStacks) or 1
  local stackBehavior = tostring(draft.stackBehavior or "replace")
  return maxStacks > 1 or stackBehavior == "add"
end

local function shouldExpandStackOptions(draft, panel)
  if panel and panel.stackOptionsExpanded ~= nil then
    return panel.stackOptionsExpanded == true
  end
  return isStackingSyntheticAura(draft)
end

local function normalizeProduceTriggers(draft)
  if UI and UI.Bindings and UI.Bindings.GetProduceTriggers then
    return UI.Bindings:GetProduceTriggers(draft)
  end
  return {}
end

local function spellIDResolves(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return false
  end
  if ns.AuraAPI and ns.AuraAPI.GetSpellName then
    local name = ns.AuraAPI:GetSpellName(spellID)
    if type(name) == "string" and name ~= "" then
      return true
    end
  end
  return false
end

local function getSpellRowPreview(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return 134400, "Choose a spell"
  end

  local icon = (ns.AuraAPI and ns.AuraAPI.GetSpellTexture and ns.AuraAPI:GetSpellTexture(spellID)) or 134400
  local name = (ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID)) or ("Spell " .. tostring(spellID))
  return icon, name
end

local function syncProduceTriggersToDraft(draft)
  if not draft then
    return
  end
  normalizeProduceTriggers(draft)
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

local function getCurrentClassAndSpec()
  local _, classToken = UnitClass and UnitClass("player") or nil
  classToken = tostring(classToken or ""):upper()
  local specID, specName = nil, ""
  if GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local a, b, c, d = GetSpecializationInfo(specIndex)
      if type(a) == "number" then
        specID = tonumber(a)
        specName = tostring(b or "")
      else
        specID = tonumber(d)
        specName = tostring(a or "")
      end
    end
  end
  return classToken, specID, specName
end

local function lookupOptionLabel(options, wanted)
  wanted = tostring(wanted or "")
  for i = 1, #(options or {}) do
    local row = options[i]
    if tostring(row.value or "") == wanted then
      return tostring(row.label or wanted)
    end
    if type(row.menuList) == "table" then
      for j = 1, #row.menuList do
        local child = row.menuList[j]
        if tostring(child.value or "") == wanted then
          return tostring(child.label or wanted)
        end
      end
    end
  end
  return wanted
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
  displayMode = true,
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
  self:CommitProduceTriggerWidgets()

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
    local existingEntry = nil
    if ns.SettingsData.ResolveEntry then
      local sourceKey = tostring(self.currentAuraId or self.draft._sourceKey or self.draft.id or "")
      existingEntry = ns.SettingsData:ResolveEntry(sourceKey)
      local existingUID = existingEntry and existingEntry.item and tostring(existingEntry.item.instanceUID or "") or ""
      if existingUID ~= "" then
        settingsModel.instanceUID = existingUID
        self.draft.instanceUID = existingUID
        ns.state.selectedAura.instanceUID = existingUID
      end
    end
    previewItem = ns.SettingsData:BuildWatchItemFromModel(settingsModel, { existingItem = existingEntry and existingEntry.item or nil })
  end
  ns.state.selectedAuraPreviewItem = previewItem

  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
end

function AuraEditorPanel:CommitProduceTriggerWidgets()
  if not self.draft then
    return
  end

  if self.triggerListWidget and self.triggerListWidget.Commit then
    self.triggerListWidget:Commit()
    return
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

  if not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) then
    local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
    if actionMode == "produce" then
      local triggers = normalizeProduceTriggers(self.draft)
      local validCount = 0
      for i = 1, #triggers do
        local trigger = triggers[i]
        if spellIDResolves(trigger and trigger.spellID) then
          validCount = validCount + 1
        elseif tonumber(trigger and trigger.spellID) and tonumber(trigger.spellID) > 0 then
          issues[#issues + 1] = {
            severity = "warn",
            path = "produceTriggers",
            message = string.format("Trigger %d uses a SpellID that could not be resolved.", i),
          }
        end
      end
      if validCount == 0 then
        issues[#issues + 1] = {
          severity = "error",
          path = "produceTriggers",
          message = "Add at least one valid spell that can grant or refresh this aura.",
        }
      end
    elseif actionMode == "consume" then
      local consumeCSV = tostring(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs or "")
      if consumeCSV == "" then
        issues[#issues + 1] = {
          severity = "error",
          path = "consumeCastSpellIDs",
          message = "Add the spell that should spend or remove this aura.",
        }
      end
    end
  end

  if not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) then
    if tostring(self.draft.actionMode or "produce") == "produce" then
      if tostring(self.draft.timerBehavior or "reset") == "extend" then
        if (tonumber(self.draft.maxDuration) or 0) <= 0 then
          issues[#issues + 1] = { severity = "warn", path = "maxDuration", message = "Set a maximum extended length so the timer has a cap." }
        elseif tonumber(self.draft.maxDuration) < (tonumber(self.draft.duration) or 0) then
          issues[#issues + 1] = { severity = "warn", path = "maxDuration", message = "The cap should be greater than or equal to the base timer length." }
        end
      end
      if tostring(self.draft.stackBehavior or "replace") == "add" and (tonumber(self.draft.maxStacks) or 0) < 2 then
        issues[#issues + 1] = { severity = "warn", path = "maxStacks", message = "Add-stack auras should usually allow at least 2 maximum stacks." }
      end
    end
  end

  local hasErrors = false
  for i = 1, #issues do
    if issues[i].severity == "error" then
      hasErrors = true
      break
    end
  end
  self.hasValidationErrors = hasErrors
  if self.btnSave then
    self.btnSave:SetEnabled(not hasErrors)
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
      self.previewBannerHint:SetText("")
    end
    return
  end
  self.titleText:SetText("")
  self.subtitle:SetText(string.format("Unit: %s | Tracking: %s", tostring(self.draft.unit or "player"), getTrackingSummary(self.draft)))
  if self.previewBannerText then
    local auraName = tostring(self.draft.name or self.draft.displayName or "Selected Aura")
    self.previewBannerText:SetText(auraName)
  end
  if self.previewBannerHint then
    self.previewBannerHint:SetText("")
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
  self:CommitProduceTriggerWidgets()

  if not self.draft or isDirectAuraTracking(self.draft) then
    return
  end
  mode = (tostring(mode or "produce") == "consume") and "consume" or "produce"
  self.triggerEditMode = mode
  self.draft.actionMode = mode

  local auraSpellID = tonumber(self.draft.spellID)
  local applied = false
  local preserveDraftProduce = (mode == "produce") and self.draft._produceTriggersDirty == true
  if (not preserveDraftProduce) and RuleRepo and RuleRepo.ApplyRulesForModeToDraft and auraSpellID and auraSpellID > 0 then
    RuleRepo:ApplyRulesForModeToDraft(self.draft, mode)
    applied = true
  elseif not preserveDraftProduce then
    local rule = nil
    if RuleRepo and RuleRepo.GetRuleForAuraByMode and auraSpellID and auraSpellID > 0 then
      rule = RuleRepo:GetRuleForAuraByMode(auraSpellID, mode)
    end
    if rule and UI and UI.Bindings and UI.Bindings.ApplyRuleToDraft then
      UI.Bindings:ApplyRuleToDraft(self.draft, rule)
      applied = true
    end
  end

  if applied then
    if mode == "produce" then
      syncProduceTriggersToDraft(self.draft)
    else
      self.draft.consumeCastSpellIDs = tostring(self.draft.castSpellIDs or "")
    end
  else
    local base = auraSpellID and ("aura" .. tostring(auraSpellID)) or "aura"
    self.draft.ruleID = base
    self.draft.ruleName = (mode == "consume") and "Consume Aura" or "Show Aura"
    self.draft.castSpellIDs = tostring(self.draft.castSpellIDs or "")
    self.draft.conditionLogic = self.draft.conditionLogic or "all"
    self.draft.talentSpellIDs = tostring(self.draft.talentSpellIDs or "")
    self.draft.requiredAuraSpellIDs = (mode == "consume" and auraSpellID) and tostring(auraSpellID) or tostring(self.draft.requiredAuraSpellIDs or "")
    self.draft.duration = tonumber(self.draft.duration) or 8
    self.draft.timerBehavior = tostring(self.draft.timerBehavior or "reset")
    self.draft.maxDuration = tonumber(self.draft.maxDuration) or 0
    self.draft.stackBehavior = tostring(self.draft.stackBehavior or "replace")
    self.draft.stackAmount = tonumber(self.draft.stackAmount) or 1
    self.draft.maxStacks = tonumber(self.draft.maxStacks) or 1
    local defaultConsume = (mode == "consume" and isStackingSyntheticAura(self.draft)) and "decrement" or "hide"
    self.draft.consumeBehavior = tostring(self.draft.consumeBehavior or defaultConsume)
    if mode == "produce" then
      syncProduceTriggersToDraft(self.draft)
    else
      self.draft.consumeCastSpellIDs = tostring(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs or "")
    end
  end

  if self.ruleBuilder and self.ruleBuilder.SetDraft then
    self.ruleBuilder:SetDraft(self.draft)
  end
end

function AuraEditorPanel:ApplyTrackingPreset(presetKey)
  if not self.draft then
    return
  end

  if presetKey == "debuff_target" then
    self.draft.unit = "target"
    self.draft.trackingMode = "estimated"
    self.draft.triggerType = "cast"
    self.draft.actionMode = "produce"
    self.draft.onlyMine = true
    if not tonumber(self.draft.estimatedDuration) or tonumber(self.draft.estimatedDuration) <= 0 then
      self.draft.estimatedDuration = tonumber(self.draft.duration) or 8
    end
  elseif presetKey == "target_aura" then
    self.draft.unit = "target"
    self.draft.trackingMode = "confirmed"
    self.draft.triggerType = "aura"
    self.draft.actionMode = "produce"
  else
    self.draft.unit = "player"
    self.draft.trackingMode = "confirmed"
    self.draft.triggerType = "cast"
    self.draft.actionMode = "produce"
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:UpdateHeader()
  self:ValidateDraft()
  self:RefreshTabButtons()
  self:RenderTab("Tracking")
  self:RefreshLivePreview(true)
end

function AuraEditorPanel:ApplyLayoutPreset(presetKey)
  if not self.draft then
    return
  end

  if presetKey == "icon" then
    self.draft.displayMode = "icon"
    self.draft.timerVisual = "icon"
    self.draft.iconWidth = 36
    self.draft.iconHeight = 36
    self.draft.showTimerText = true
    self.draft.timerAnchor = "BOTTOM"
    self.draft.customTextAnchor = "TOP"
  elseif presetKey == "compact" then
    self.draft.displayMode = "icon"
    self.draft.timerVisual = "icon"
    self.draft.iconWidth = 28
    self.draft.iconHeight = 28
    self.draft.showTimerText = false
    self.draft.customText = ""
  elseif presetKey == "iconbar" then
    self.draft.displayMode = "iconbar"
    self.draft.timerVisual = "iconbar"
    self.draft.iconWidth = 36
    self.draft.iconHeight = 36
    self.draft.barWidth = 94
    self.draft.barHeight = 16
    self.draft.barSide = "right"
    self.draft.showTimerText = true
  elseif presetKey == "targetbar" then
    self.draft.displayMode = "bar"
    self.draft.timerVisual = "bar"
    self.draft.barWidth = 180
    self.draft.barHeight = 18
    self.draft.showTimerText = true
    self.draft.timerAnchor = "BOTTOM"
    self.draft.customTextAnchor = "TOP"
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  self:RenderTab("Appearance")
end
function AuraEditorPanel:LoadAura(auraId)
  self.draft = Repo:GetAuraDraft(auraId)
  self.deleteArmedUntil = nil
  self.triggerEditMode = tostring(self.draft and self.draft.actionMode or "produce")
  if self.draft then
    self.draft._produceTriggersDirty = false
  end
  self.currentAuraId = self.draft and self.draft.id or auraId
  if S and S.SetDirty then
    S:SetDirty(false)
  end

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
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  if S and S.SetDirty then
    S:SetDirty(false)
  end
end

function AuraEditorPanel:OnFieldChanged(key, value)
  if not self.draft then
    return
  end

  self.draft[key] = value
  if key == "group" then
    applyGroupConfigToDraft(self.draft, value)
  elseif key == "groupID" then
    applyGroupConfigToDraft(self.draft, value)
  end
  if self.suspendFieldChanges == true then
    return
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
  self.produceTriggerWidgets = nil

  if self.triggerListWidget and self.triggerListWidget.frame then
    self.triggerListWidget.frame:Hide()
    self.triggerListWidget.frame:SetParent(nil)
  end
  self.triggerListWidget = nil

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

function AuraEditorPanel:RenderDisplayCanvas(y)
  local card = createCard(self.content, y, "Visual Layout", "Use quick layout presets here, then check the Live Preview panel on the right for the real draft preview.", 132)
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local presetLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  presetLabel:SetPoint("TOPLEFT", 2, -2)
  presetLabel:SetText("Quick Layout Presets")

  local function makePreset(text, x, presetKey)
    local btn = CreateFrame("Button", nil, card.content, "UIPanelButtonTemplate")
    btn:SetSize(82, 20)
    btn:SetPoint("TOPLEFT", 2 + x, -18)
    btn:SetText(text)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "segment")
    end
    btn:SetScript("OnClick", function()
      self:ApplyLayoutPreset(presetKey)
    end)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
  end

  makePreset("Icon", 0, "icon")
  makePreset("Compact", 88, "compact")
  makePreset("Icon + Bar", 176, "iconbar")
  makePreset("Target Bar", 264, "targetbar")

  local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")

  local function makeMiniButton(text, x, onClick)
    local btn = CreateFrame("Button", nil, card.content, "UIPanelButtonTemplate")
    btn:SetSize(82, 20)
    btn:SetPoint("TOPLEFT", 2 + x, -46)
    btn:SetText(text)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "segment")
    end
    btn:SetScript("OnClick", onClick)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
    return btn
  end

  if mode == "iconbar" then
    makeMiniButton("Icon Left", 0, function()
      self:OnFieldChanged("barSide", "right")
      self:RenderTab("Appearance")
    end)
    makeMiniButton("Icon Right", 88, function()
      self:OnFieldChanged("barSide", "left")
      self:RenderTab("Appearance")
    end)
  end
  makeMiniButton("Timer Above", 0, function()
    self:OnFieldChanged("timerAnchor", "TOP")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 2, -74)
  makeMiniButton("Timer Below", 88, function()
    self:OnFieldChanged("timerAnchor", "BOTTOM")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 90, -74)
  makeMiniButton("Text Above", 176, function()
    self:OnFieldChanged("customTextAnchor", "TOP")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 178, -74)
  makeMiniButton("Text Below", 266, function()
    self:OnFieldChanged("customTextAnchor", "BOTTOM")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 266, -74)

  card.content:SetHeight(98)
  return y - 142
end

function AuraEditorPanel:SetStackingEnabled(enabled)
  if not self.draft then
    return
  end
  enabled = enabled == true
  if enabled then
    self.draft.stackBehavior = "add"
    self.draft.stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1)
    self.draft.maxStacks = math.max(2, tonumber(self.draft.maxStacks) or 2)
    local triggers = normalizeProduceTriggers(self.draft)
    for i = 1, #triggers do
      triggers[i].stackAmount = math.max(1, tonumber(triggers[i].stackAmount) or 1)
    end
    self.stackOptionsExpanded = true
  else
    self.draft.stackBehavior = "replace"
    self.draft.stackAmount = 1
    self.draft.maxStacks = 1
    local triggers = normalizeProduceTriggers(self.draft)
    for i = 1, #triggers do
      triggers[i].stackAmount = 1
    end
    if tostring(self.draft.consumeBehavior or "hide") == "decrement" then
      self.draft.consumeBehavior = "hide"
    end
    self.stackOptionsExpanded = false
  end
  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(false)
end

function AuraEditorPanel:RenderTrackingStackCard(y, fieldsByKey)
  local enabled = isStackingSyntheticAura(self.draft)
  local expanded = enabled and shouldExpandStackOptions(self.draft, self)
  local extraHeight = expanded and 128 or 0
  local cardHeight = 88 + extraHeight

  local card = createCard(
    self.content,
    y,
    "Stacks",
    "Turn this on only for buffs that can build charges or stacks instead of simply refreshing.",
    cardHeight
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local toggle = CreateFrame("CheckButton", nil, card.content, "UICheckButtonTemplate")
  toggle:SetPoint("TOPLEFT", 2, -2)
  toggle:SetChecked(enabled)
  if Skin and Skin.ApplyCheckbox then
    Skin:ApplyCheckbox(toggle)
  end
  toggle:SetScript("OnClick", function(btn)
    if Skin and Skin.RefreshCheckbox then
      Skin:RefreshCheckbox(btn)
    end
    self:SetStackingEnabled(btn:GetChecked() == true)
    self:RenderTab("Tracking")
  end)
  self.fieldWidgets[#self.fieldWidgets + 1] = toggle

  local toggleLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  toggleLabel:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
  toggleLabel:SetText("Stackable")
  self.fieldWidgets[#self.fieldWidgets + 1] = toggleLabel

  local hint = card.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 2, -24)
  hint:SetPoint("RIGHT", -40, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(enabled and "This aura can gain more than one charge. Expand below to set how many it can hold." or "Leave this off for simple buffs that only refresh.")
  self.fieldWidgets[#self.fieldWidgets + 1] = hint

  if enabled then
    local collapseBtn = CreateFrame("Button", nil, card.content, "UIPanelButtonTemplate")
    collapseBtn:SetSize(26, 20)
    collapseBtn:SetPoint("TOPRIGHT", -2, 0)
    collapseBtn:SetText(expanded and "-" or "+")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(collapseBtn, "ghost")
    end
    collapseBtn:SetScript("OnClick", function()
      self.stackOptionsExpanded = not expanded
      self:RenderTab("Tracking")
    end)
    self.fieldWidgets[#self.fieldWidgets + 1] = collapseBtn

    if expanded then
      local stackFields = {
        fieldsByKey.stackAmount,
        fieldsByKey.maxStacks,
      }
      local nextY = self:RenderGenericFields(stackFields, -52, card.content, 2, -2)
      card.content:SetHeight(math.max(24, -nextY + 8))
    else
      card.content:SetHeight(44)
    end
  else
    card.content:SetHeight(44)
  end

  return y - cardHeight - 10
end

function AuraEditorPanel:RenderConsumeBehaviorCard(y)
  if not shouldShowConsumeBehavior(self.draft) then
    return y
  end

  local card = createCard(
    self.content,
    y,
    "Spending Charges",
    "Choose whether the spender clears the whole aura or uses one charge at a time.",
    94
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local toggle = CreateFrame("CheckButton", nil, card.content, "UICheckButtonTemplate")
  toggle:SetPoint("TOPLEFT", 2, -2)
  toggle:SetChecked(tostring(self.draft.consumeBehavior or "hide") == "decrement")
  if Skin and Skin.ApplyCheckbox then
    Skin:ApplyCheckbox(toggle)
  end
  toggle:SetScript("OnClick", function(btn)
    if Skin and Skin.RefreshCheckbox then
      Skin:RefreshCheckbox(btn)
    end
    self.draft.consumeBehavior = btn:GetChecked() and "decrement" or "hide"
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:ValidateDraft()
    self:RefreshLivePreview(false)
    self:RenderTab("Tracking")
  end)
  self.fieldWidgets[#self.fieldWidgets + 1] = toggle

  local toggleLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  toggleLabel:SetPoint("LEFT", toggle, "RIGHT", 4, 0)
  toggleLabel:SetText("Consume only 1 charge")
  self.fieldWidgets[#self.fieldWidgets + 1] = toggleLabel

  local hint = card.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 2, -24)
  hint:SetPoint("RIGHT", -2, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText(toggle:GetChecked() and "Best for buffs like Precise Shots, where each spender uses one charge." or "Use this for buffs that should disappear completely when consumed.")
  self.fieldWidgets[#self.fieldWidgets + 1] = hint

  card.content:SetHeight(46)
  return y - 104
end

function AuraEditorPanel:RenderLoadConditionsCard(y, fieldsByKey)
  local card = createCard(
    self.content,
    y,
    "Load Conditions",
    "Use this only when the aura should exist for one class or spec. Leave both blank to load it everywhere.",
    176
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local currentClassToken, currentSpecID, currentSpecName = getCurrentClassAndSpec()
  local loadClassToken = tostring(self.draft and self.draft.loadClassToken or ""):upper()
  local loadSpecID = tostring(self.draft and self.draft.loadSpecID or "")

  local classOptions = (ns.SettingsData and ns.SettingsData.GetLoadClassOptions and ns.SettingsData:GetLoadClassOptions()) or {}
  local specOptions = (ns.SettingsData and ns.SettingsData.GetLoadSpecMenuOptions and ns.SettingsData:GetLoadSpecMenuOptions(loadClassToken)) or {}
  local classLabel = (loadClassToken ~= "") and lookupOptionLabel(classOptions, loadClassToken) or "Any Class"
  local specLabel = (loadSpecID ~= "") and lookupOptionLabel(specOptions, loadSpecID) or "Any Spec"

  local status = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  status:SetPoint("TOPLEFT", 2, -2)
  status:SetPoint("RIGHT", -2, 0)
  status:SetJustifyH("LEFT")
  self.fieldWidgets[#self.fieldWidgets + 1] = status

  local detail = card.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail:SetPoint("TOPLEFT", 2, -20)
  detail:SetPoint("RIGHT", -2, 0)
  detail:SetJustifyH("LEFT")
  self.fieldWidgets[#self.fieldWidgets + 1] = detail

  local loaded = true
  local reason = ""
  if loadClassToken ~= "" and loadClassToken ~= currentClassToken then
    loaded = false
    reason = "Wrong Class"
  elseif loadSpecID ~= "" and tostring(currentSpecID or "") ~= loadSpecID then
    loaded = false
    reason = "Wrong Spec"
  end

  if loaded then
    status:SetText("|cff4dff88Loaded for your current character|r")
  else
    status:SetText("|cffff6b6bNot loaded for your current character|r")
  end

  local currentClassLabel = lookupOptionLabel(classOptions, currentClassToken)
  local currentLabel = string.format("Current: %s%s", currentClassLabel ~= "" and currentClassLabel or currentClassToken, currentSpecName ~= "" and (" / " .. currentSpecName) or "")
  local targetLabel = string.format("Aura setting: %s / %s", classLabel, specLabel)
  if loaded then
    detail:SetText(currentLabel .. "\n" .. targetLabel)
  else
    detail:SetText(currentLabel .. "\n" .. targetLabel .. "\nReason: " .. reason)
  end

  local quickLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  quickLabel:SetPoint("TOPLEFT", 2, -52)
  quickLabel:SetText("Quick setup")
  self.fieldWidgets[#self.fieldWidgets + 1] = quickLabel

  local function makeQuickButton(text, x, onClick)
    local btn = CreateFrame("Button", nil, card.content, "UIPanelButtonTemplate")
    btn:SetSize(124, 20)
    btn:SetPoint("TOPLEFT", x, -68)
    btn:SetText(text)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "segment")
    end
    btn:SetScript("OnClick", onClick)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
    return btn
  end

  makeQuickButton("Load Everywhere", 2, function()
    self:OnFieldChanged("loadClassToken", "")
    self:OnFieldChanged("loadSpecID", "")
    self:RenderTab("Advanced")
  end)
  makeQuickButton("Only My Class", 132, function()
    self:OnFieldChanged("loadClassToken", currentClassToken)
    self:OnFieldChanged("loadSpecID", "")
    self:RenderTab("Advanced")
  end)
  makeQuickButton("Only This Spec", 262, function()
    self:OnFieldChanged("loadClassToken", currentClassToken)
    self:OnFieldChanged("loadSpecID", tostring(currentSpecID or ""))
    self:RenderTab("Advanced")
  end)

  local nextY = self:RenderGenericFields({
    fieldsByKey.loadClassToken,
    fieldsByKey.loadSpecID,
  }, -96, card.content, 2, -2)

  card.content:SetHeight(math.max(132, -nextY + 8))
  return y - 224
end

function AuraEditorPanel:RenderProduceTriggersCard(y)
  if Widgets.TriggerListWidget and Widgets.TriggerListWidget.Create then
    self.triggerListWidget = Widgets.TriggerListWidget:Create(self.content, {
      isStackable = isStackingSyntheticAura,
      onChanged = function()
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:ValidateDraft()
      end,
      onRequestRender = function()
        self._skipProduceTriggerCommitOnce = true
        self:RenderTab("Tracking")
      end,
    })
    self.triggerListWidget.frame:SetPoint("TOPLEFT", 12, y)
    self.triggerListWidget.frame:SetPoint("RIGHT", -14, 0)
    self.triggerListWidget.frame:Show()
    self.triggerListWidget:SetDraft(self.draft)
    return y - self.triggerListWidget.frame:GetHeight() - 10
  end

  return y
end

function AuraEditorPanel:RenderTab(tabKey)
  if self._skipProduceTriggerCommitOnce == true then
    self._skipProduceTriggerCommitOnce = false
  else
    self:CommitProduceTriggerWidgets()
  end
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
  self.suspendFieldChanges = true

  local y = -12

  if tabKey == "Tracking" then
    local presetFrame = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
    createBackdrop(presetFrame)
    presetFrame:SetHeight(64)
    presetFrame:SetPoint("TOPLEFT", 12, y)
    presetFrame:SetPoint("RIGHT", -14, 0)

    local presetLabel = presetFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    presetLabel:SetPoint("TOPLEFT", 10, -8)
    presetLabel:SetText("Choose the kind of aura you want to build")

    local activePreset = inferTrackingPreset(self.draft)
    local btnPlayer = CreateFrame("Button", nil, presetFrame, "UIPanelButtonTemplate")
    btnPlayer:SetSize(150, 24)
    btnPlayer:SetPoint("BOTTOMLEFT", 10, 8)
    btnPlayer:SetText("Buff / Proc On Me")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btnPlayer, "segment")
    end
    setTabVisual(btnPlayer, activePreset == "buff_player")
    btnPlayer:SetScript("OnClick", function()
      self:ApplyTrackingPreset("buff_player")
    end)

    local btnDebuff = CreateFrame("Button", nil, presetFrame, "UIPanelButtonTemplate")
    btnDebuff:SetSize(150, 24)
    btnDebuff:SetPoint("LEFT", btnPlayer, "RIGHT", 8, 0)
    btnDebuff:SetText("Debuff I Apply")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btnDebuff, "segment")
    end
    setTabVisual(btnDebuff, activePreset == "debuff_target")
    btnDebuff:SetScript("OnClick", function()
      self:ApplyTrackingPreset("debuff_target")
    end)

    local btnTarget = CreateFrame("Button", nil, presetFrame, "UIPanelButtonTemplate")
    btnTarget:SetSize(150, 24)
    btnTarget:SetPoint("LEFT", btnDebuff, "RIGHT", 8, 0)
    btnTarget:SetText("Aura On Target")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btnTarget, "segment")
    end
    setTabVisual(btnTarget, activePreset == "target_aura")
    btnTarget:SetScript("OnClick", function()
      self:ApplyTrackingPreset("target_aura")
    end)

    self.fieldWidgets[#self.fieldWidgets + 1] = presetFrame
    self.fieldWidgets[#self.fieldWidgets + 1] = btnPlayer
    self.fieldWidgets[#self.fieldWidgets + 1] = btnDebuff
    self.fieldWidgets[#self.fieldWidgets + 1] = btnTarget
    y = y - 72

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
      self.triggerEditMode = activeMode

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

      local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
      if actionMode == "produce" then
        local infoFrame = addInfoBox(
          self.content,
          y,
          "Applied when the cast finishes",
          "For cast-time spells like Aimed Shot, AuraLite grants the aura only when the cast really completes, not on the first key press.",
          82
        )
        self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
        y = y - 92
      elseif actionMode == "consume" and shouldShowConsumeBehavior(self.draft) then
        local infoFrame = addInfoBox(
          self.content,
          y,
          "Spend one charge at a time",
          "For stackable buffs like Precise Shots, choose 'Remove 1 Stack' so each spender removes only one charge instead of clearing the whole aura.",
          82
        )
        self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
        y = y - 92
      end
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
        local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
        if key == "unit" or key == "spellID" or (key == "castSpellIDs" and actionMode == "consume") then
          filtered[#filtered + 1] = fields[i]
      elseif actionMode == "produce" and (
          key == "duration"
          or key == "timerBehavior"
          or (key == "maxDuration" and tostring(self.draft.timerBehavior or "reset") == "extend")
        ) then
          filtered[#filtered + 1] = fields[i]
        elseif actionMode == "consume" and key ~= "consumeBehavior" then
          filtered[#filtered + 1] = fields[i]
        end
      else
        filtered[#filtered + 1] = fields[i]
      end
    end
    y = self:RenderGenericFields(filtered, y)
    if not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) and not self.showAdvanced then
      local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
      if actionMode == "produce" then
        local byKey = {}
        for i = 1, #fields do
          if fields[i] then
            byKey[fields[i].key] = fields[i]
          end
        end
        y = self:RenderProduceTriggersCard(y)
        y = self:RenderTrackingStackCard(y, byKey)
      elseif actionMode == "consume" then
        y = self:RenderConsumeBehaviorCard(y)
      end
    end
  elseif tabKey == "Appearance" then
    local allFields = tab.fields or {}
    local byKey = {}
    for i = 1, #allFields do
      if allFields[i] then
        byKey[allFields[i].key] = allFields[i]
      end
    end
    local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")

    y = self:RenderDisplayCanvas(y)

    y = self:RenderAppearanceCard(y, "Layout", "Define the overall shape and placement of this aura.", {
      byKey.name,
      byKey.group,
      byKey.displayMode,
      (mode ~= "icon") and byKey.barSide or nil,
    })

    if tostring(self.draft.groupID or self.draft.group or "") ~= "" then
      y = self:RenderAppearanceCard(y, "Group Layout", "A grouped aura moves with its shared container. Use Movers to place the whole group.", {
        byKey.groupName,
        byKey.groupDirection,
        byKey.groupSpacing,
        byKey.groupSort,
        byKey.groupWrapAfter,
        byKey.groupOffsetX,
        byKey.groupOffsetY,
      })
    end

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
    local byKey = {}
    for i = 1, #fields do
      if fields[i] then
        byKey[fields[i].key] = fields[i]
      end
    end

    y = self:RenderLoadConditionsCard(y, byKey)

    local filtered = {}
    for i = 1, #fields do
      local key = fields[i].key
      local include = true
      if key == "loadClassToken" or key == "loadSpecID" then
        include = false
      end
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
  self.suspendFieldChanges = false
  self:ValidateDraft()
end

function AuraEditorPanel:SelectTab(tabKey)
  self:CommitProduceTriggerWidgets()
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

  local now = GetTime and GetTime() or 0
  if not self.deleteArmedUntil or self.deleteArmedUntil < now then
    self.deleteArmedUntil = now + 4
    if self.RefreshDeleteButton then
      self:RefreshDeleteButton()
    end
    V:SetStatus("warn", "Press Delete again to permanently remove this aura.")
    return
  end

  local deleted, err = Repo and Repo.DeleteAura and Repo:DeleteAura(self.draft.id)
  if not deleted then
    V:SetStatus("error", tostring(err or "Delete failed"))
    return
  end

  self.deleteArmedUntil = nil
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
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "delete", value = true })
  end
end

function AuraEditorPanel:DuplicateCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local ok, newId, err = Repo and Repo.DuplicateAura and Repo:DuplicateAura(self.draft.id)
  if not ok then
    V:SetStatus("error", tostring(err or "Duplicate failed"))
    return
  end

  if S and S.SetSelectedAura then
    S:SetSelectedAura(newId, "duplicate")
  end
  V:SetStatus("ok", "Aura duplicated.")
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "duplicate", value = newId })
  end
end

function AuraEditorPanel:ExportCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local text, err = Repo and Repo.ExportAura and Repo:ExportAura(self.draft.id)
  if not text then
    V:SetStatus("error", tostring(err or "Export failed"))
    return
  end

  if UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowExport then
    UI.ImportExportDialog:ShowExport(
      "Export Aura",
      text,
      "This exports only the selected aura. Linked rules are included; the imported copy gets fresh local IDs."
    )
  end
  V:SetStatus("ok", "Aura export generated.")
end

function AuraEditorPanel:DiscardCurrent()
  if not self.draft then
    return
  end

  local currentId = tostring(self.currentAuraId or self.draft.id or "")
  if currentId ~= "" then
    self:LoadAura(currentId)
  else
    self.draft = Repo:CreateDraft()
    self.currentAuraId = self.draft and self.draft.id or nil
    self:UpdateHeader()
    self:RefreshTabButtons()
    self:RenderTab((S and S.Get and S:Get().activeTab) or "Tracking")
    self:ValidateDraft()
    self:RefreshLivePreview(true)
  end

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  self.deleteArmedUntil = nil
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  V:SetStatus("ok", "Unsaved changes discarded.")
end

function AuraEditorPanel:SaveCurrent()
  if not self.draft then
    return
  end

  self:CommitProduceTriggerWidgets()

  if tostring(self.triggerEditMode or self.draft.actionMode or "produce") == "produce" then
    syncProduceTriggersToDraft(self.draft)
  elseif tostring(self.draft.castSpellIDs or "") ~= "" then
    self.draft.consumeCastSpellIDs = tostring(self.draft.castSpellIDs or "")
  end

  if (not self.draft.id or tostring(self.draft.id) == "") and self.currentAuraId and tostring(self.currentAuraId) ~= "" then
    self.draft.id = tostring(self.currentAuraId)
    self.draft._sourceKey = tostring(self.currentAuraId)
  end

  local ruleDraft = (ns.Utils and ns.Utils.DeepCopy and ns.Utils.DeepCopy(self.draft)) or nil
  if type(ruleDraft) ~= "table" then
    ruleDraft = {}
    for key, value in pairs(self.draft) do
      ruleDraft[key] = value
    end
  end

  local ok, savedId, err = Repo:SaveDraft(self.draft)
  if not ok then
    V:SetStatus("error", tostring(err or "Save failed"))
    return
  end

  if savedId and tostring(savedId) ~= "" then
    ruleDraft.id = tostring(savedId)
    ruleDraft._sourceKey = tostring(savedId)
    if ns.SettingsData and ns.SettingsData.ResolveEntry then
      local savedEntry = ns.SettingsData:ResolveEntry(savedId)
      local savedUID = savedEntry and savedEntry.item and tostring(savedEntry.item.instanceUID or "") or ""
      if savedUID ~= "" then
        ruleDraft.instanceUID = savedUID
      end
    end
  end

  ruleDraft._produceTriggersDirty = false

  if RuleRepo and RuleRepo.SaveRuleFromDraft then
    local rok, rerr = RuleRepo:SaveRuleFromDraft(ruleDraft)
    if rok ~= true and rerr then
      V:Push("warn", "rule", tostring(rerr))
    end
  end

  if savedId and tostring(savedId) ~= "" then
    self.currentAuraId = tostring(savedId)
    local refreshedDraft = Repo:GetAuraDraft(savedId)
    if type(refreshedDraft) == "table" then
      self.draft = refreshedDraft
    else
      self.draft.id = tostring(savedId)
      self.draft._sourceKey = tostring(savedId)
      if ns.SettingsData and ns.SettingsData.ResolveEntry then
        local savedEntry = ns.SettingsData:ResolveEntry(savedId)
        local savedUID = savedEntry and savedEntry.item and tostring(savedEntry.item.instanceUID or "") or ""
        if savedUID ~= "" then
          self.draft.instanceUID = savedUID
        end
      end
    end
  else
    self.draft.id = savedId or self.draft.id
  end
  self.draft._produceTriggersDirty = false

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if S and S.SetSelectedAura and savedId then
    S:SetSelectedAura(savedId, "save")
  end

  self.deleteArmedUntil = nil
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
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
  o.previewBanner:SetHeight(30)

  o.previewBannerText = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.previewBannerText:SetPoint("LEFT", 10, 0)
  o.previewBannerText:SetPoint("RIGHT", -10, 0)
  o.previewBannerText:SetJustifyH("LEFT")
  o.previewBannerText:SetText("No aura selected")

  o.previewBannerHint = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.previewBannerHint:SetPoint("TOPLEFT", 10, -24)
  o.previewBannerHint:SetPoint("RIGHT", -10, 0)
  o.previewBannerHint:SetJustifyH("LEFT")
  o.previewBannerHint:SetText("")
  o.previewBannerHint:Hide()

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 10, -82)
  o.tabStrip:SetPoint("TOPRIGHT", -138, -82)
  o.tabStrip:SetHeight(26)

  o.btnMode = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnMode:SetSize(118, 22)
  o.btnMode:SetPoint("TOPRIGHT", -12, -82)
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
  o.scroll:SetPoint("TOPLEFT", 8, -110)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 48)

  o.content = CreateFrame("Frame", nil, o.scroll)
  o.content:SetSize(1, 1)
  o.scroll:SetScrollChild(o.content)

  o.status = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.status:SetPoint("BOTTOMLEFT", 12, 38)
  o.status:SetPoint("RIGHT", -12, 0)
  o.status:SetJustifyH("LEFT")
  o.status:SetText("Ready")

  function o:RefreshDeleteButton()
    if not self.btnDelete then
      return
    end
    local now = GetTime and GetTime() or 0
    local armed = self.deleteArmedUntil and self.deleteArmedUntil >= now
    self.btnDelete:SetText(armed and "Confirm Delete" or "Delete")
  end

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
  o.btnReset:SetText("Discard")
  o.btnReset:SetScript("OnClick", function()
    o:DiscardCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnReset, "ghost")
  end

  o.btnDelete = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnDelete:SetSize(90, 24)
  o.btnDelete:SetPoint("LEFT", o.btnDuplicate, "RIGHT", 96, 0)
  o.btnDelete:SetText("Delete")
  o.btnDelete:SetScript("OnClick", function()
    o:DeleteCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnDelete, "danger")
  end
  o:RefreshDeleteButton()

  o.btnDuplicate = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnDuplicate:SetSize(90, 24)
  o.btnDuplicate:SetPoint("LEFT", o.btnReset, "RIGHT", 8, 0)
  o.btnDuplicate:SetText("Duplicate")
  o.btnDuplicate:SetScript("OnClick", function()
    o:DuplicateCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnDuplicate, "ghost")
  end
  o.duplicateButton = o.btnDuplicate

  o.btnExport = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnExport:SetSize(80, 24)
  o.btnExport:SetPoint("LEFT", o.btnDuplicate, "RIGHT", 8, 0)
  o.btnExport:SetText("Export")
  o.btnExport:SetScript("OnClick", function()
    o:ExportCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnExport, "ghost")
  end

  o.btnDelete:ClearAllPoints()
  o.btnDelete:SetPoint("LEFT", o.btnExport, "RIGHT", 8, 0)

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
      if S and S.SetDirty then
        S:SetDirty(true)
      end
    end)

    E:On(E.Names.STATE_CHANGED, function(state)
      if not state or not o.status then
        return
      end
      local dirty = state.dirty == true
      if dirty then
        o.status:SetTextColor(1.0, 0.84, 0.22)
        o.status:SetText("Unsaved changes")
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
        o.status:SetText("All changes saved")
      end
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
      local dirty = S and S.Get and S:Get().dirty == true
      if status == "error" then
        o.status:SetTextColor(1, 0.35, 0.35)
        o.status:SetText(msg)
      elseif status == "warn" then
        o.status:SetTextColor(1, 0.82, 0.2)
        o.status:SetText(msg)
      elseif dirty then
        o.status:SetTextColor(1.0, 0.84, 0.22)
        o.status:SetText("Unsaved changes")
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
        o.status:SetText("All changes saved")
      end
    end)
  end

  o:LoadAura(nil)
  return o
end

Panels.AuraEditorPanel = AuraEditorPanel


