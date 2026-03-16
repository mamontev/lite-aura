local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local FieldFactory = UI.FieldFactory
local Widgets = UI.Widgets or {}
local Skin = ns.UISkin

local AuraWizard = {}
AuraWizard.__index = AuraWizard

local STEPS = {
  "Intent",
  "Trigger",
  "Artifact",
  "Review",
}

local INTENT_PRESETS = {
  {
    key = "buff_player",
    label = "Buff On Me",
    body = "Track a proc, buff, or self aura from your own casts.",
  },
  {
    key = "cooldown_player",
    label = "My Cooldown",
    body = "Read the cooldown directly and style it like an artifact.",
  },
  {
    key = "debuff_target",
    label = "Debuff On Target",
    body = "Start a local timer from your casts on the current target.",
  },
}

local ARTIFACT_PRESETS = {
  { key = "icon", label = "Icon", body = "Single icon with timer text.", displayMode = "icon", timerVisual = "icon" },
  { key = "bar", label = "Bar", body = "Wide timer bar for maintenance effects.", displayMode = "bar", timerVisual = "bar" },
  { key = "iconbar", label = "Icon + Bar", body = "Icon with a supporting timer bar.", displayMode = "iconbar", timerVisual = "iconbar" },
  { key = "targetbar", label = "Target Bar", body = "Bar-first layout for target tracking.", displayMode = "bar", timerVisual = "bar", barSide = "right" },
}

local QUICK_STARTS = {
  { key = "minimal_proc", label = "Minimal Proc", body = "Large icon with timer focus." },
  { key = "clean_bar", label = "Clean Bar", body = "Wide readable bar." },
  { key = "center_burst", label = "Center Burst", body = "Icon plus accent bar." },
  { key = "compact_tracker", label = "Compact Tracker", body = "Small footprint HUD style." },
}

local SOUND_PRESETS = {
  { key = "silent", label = "Silent" },
  { key = "default", label = "Default" },
  { key = "raid", label = "Raid" },
}

local GLOW_PROFILES = {
  { key = "quiet", label = "Quiet", onGain = "off", lowTime = "subtle", maxStacks = "off" },
  { key = "balanced", label = "Balanced", onGain = "soft", lowTime = "warning", maxStacks = "gold" },
  { key = "heroic", label = "Heroic", onGain = "burst", lowTime = "intense", maxStacks = "heroic" },
}

local function createBackdrop(frame)
  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.01, 0.07, 0.15, 0.97)
  frame:SetBackdropBorderColor(0.12, 0.52, 0.86, 0.95)
end

local function applyFloatingWindowChrome(frame)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:Raise()
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)
end

local function attachDragHandle(frame, handle)
  if not frame or not handle then
    return
  end
  local dragHandle = handle
  if type(dragHandle) == "table" and dragHandle.frame and dragHandle.frame.GetObjectType then
    dragHandle = dragHandle.frame
  end
  if not (dragHandle and dragHandle.EnableMouse and dragHandle.RegisterForDrag and dragHandle.SetScript) then
    local proxy = CreateFrame("Frame", nil, frame)
    proxy:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, 0)
    proxy:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 0, 0)
    dragHandle = proxy
  end
  dragHandle:EnableMouse(true)
  dragHandle:RegisterForDrag("LeftButton")
  dragHandle:SetScript("OnDragStart", function()
    frame:Raise()
    frame:StartMoving()
  end)
  dragHandle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
end

local function trim(value)
  value = tostring(value or "")
  return value:gsub("^%s+", ""):gsub("%s+$", "")
end

local function toSpellID(value)
  local n = tonumber(value)
  if n and n > 0 then
    return tostring(math.floor(n))
  end
  return ""
end

local function appendSpellIDCSV(csv, spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return trim(csv)
  end
  local wanted = tostring(spellID)
  local out = {}
  local seen = {}
  for token in tostring(csv or ""):gmatch("[^,%s]+") do
    local id = tostring(tonumber(token) or "")
    if id ~= "" and not seen[id] then
      out[#out + 1] = id
      seen[id] = true
    end
  end
  if not seen[wanted] then
    out[#out + 1] = wanted
  end
  return table.concat(out, ",")
end

local function getSpellName(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return ""
  end
  if ns.AuraAPI and ns.AuraAPI.GetSpellName then
    return tostring(ns.AuraAPI:GetSpellName(spellID) or "")
  end
  return ""
end

local function resolvePayloadSpellID()
  local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
  if cursorType == "spell" and cursorSpellID then
    return tonumber(cursorSpellID)
  end
  if cursorType == "item" and cursorID and C_Item and C_Item.GetItemSpell then
    local _, itemSpellID = C_Item.GetItemSpell(cursorID)
    return tonumber(itemSpellID)
  end
  if cursorType == "petaction" and cursorID then
    return tonumber(cursorID)
  end
  return nil
end

local function createChoiceButton(parent, width, height, label, body, active, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  btn:SetSize(width, height)
  if Skin and Skin.ApplyClickableRow then
    Skin:ApplyClickableRow(btn, "row")
  end
  if Skin and Skin.SetClickableRowState then
    Skin:SetClickableRowState(btn, active and "selected" or "normal")
    btn:SetScript("OnEnter", function(selfBtn)
      Skin:SetClickableRowState(selfBtn, "hover")
    end)
    btn:SetScript("OnLeave", function(selfBtn)
      Skin:SetClickableRowState(selfBtn, active and "selected" or "normal")
    end)
  end

  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  btn.label:SetPoint("TOPLEFT", 12, -8)
  btn.label:SetPoint("RIGHT", -12, 0)
  btn.label:SetJustifyH("LEFT")
  btn.label:SetText(label or "")

  btn.body = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  btn.body:SetPoint("TOPLEFT", 12, -28)
  btn.body:SetPoint("RIGHT", -12, 0)
  btn.body:SetJustifyH("LEFT")
  btn.body:SetJustifyV("TOP")
  btn.body:SetWordWrap(true)
  btn.body:SetText(body or "")

  btn:SetScript("OnClick", onClick)
  return btn
end

local function createChipButton(parent, width, label, active, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width or 88, 20)
  btn:SetText(label or "")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, "segment")
    if Skin.SetButtonSelected then
      Skin:SetButtonSelected(btn, active == true)
    end
  end
  btn:SetScript("OnClick", onClick)
  return btn
end

local function applyIntent(model, intent)
  model._wizardIntent = tostring(intent or "buff_player")
  model.actionMode = "produce"
  model.stackBehavior = tostring(model.stackBehavior or "replace")
  model.stackAmount = tonumber(model.stackAmount) or 1
  model.maxStacks = tonumber(model.maxStacks) or 1

  if model._wizardIntent == "cooldown_player" then
    model.unit = "player"
    model.trackingMode = "cooldown"
    model.triggerType = "cooldown"
    model.castSpellIDs = ""
    model.produceTriggers = {}
  elseif model._wizardIntent == "debuff_target" then
    model.unit = "target"
    model.trackingMode = "estimated"
    model.triggerType = "cast"
    model.onlyMine = true
    model.estimatedDuration = tonumber(model.estimatedDuration) or 8
  else
    model.unit = "player"
    model.trackingMode = "confirmed"
    model.triggerType = "cast"
    model.onlyMine = false
  end
end

local function applyArtifact(model, artifact)
  artifact = tostring(artifact or "iconbar")
  model._wizardArtifact = artifact
  if artifact == "icon" then
    model.displayMode = "icon"
    model.timerVisual = "icon"
  elseif artifact == "bar" then
    model.displayMode = "bar"
    model.timerVisual = "bar"
  elseif artifact == "targetbar" then
    model.displayMode = "bar"
    model.timerVisual = "bar"
    model.barSide = "right"
  else
    model.displayMode = "iconbar"
    model.timerVisual = "iconbar"
    model.iconWidth = 32
    model.iconHeight = 32
    model.barWidth = 94
    model.barHeight = 32
    model.barSide = "right"
  end
end

local function applySoundPreset(model, presetKey)
  presetKey = tostring(presetKey or "default")
  model._wizardSoundPreset = presetKey
  if presetKey == "silent" then
    model.soundOnShow = "none"
    model.soundOnLow = "none"
    model.soundOnExpire = "none"
  elseif presetKey == "raid" then
    model.soundOnShow = "default"
    model.soundOnLow = "raidwarning"
    model.soundOnExpire = "default"
  else
    model.soundOnShow = "default"
    model.soundOnLow = "default"
    model.soundOnExpire = "none"
  end
end

local function applyGlowProfile(model, profileKey)
  model.visualStates = model.visualStates or {}
  profileKey = tostring(profileKey or "balanced")
  model._wizardGlowProfile = profileKey
  for i = 1, #GLOW_PROFILES do
    local row = GLOW_PROFILES[i]
    if row.key == profileKey then
      model.visualStates.onGain = row.onGain
      model.visualStates.lowTime = row.lowTime
      model.visualStates.maxStacks = row.maxStacks
      return
    end
  end
end

local function ensureDraftTriggers(model)
  if tostring(model._wizardIntent or "") == "cooldown_player" then
    model.produceTriggers = {}
    model.castSpellIDs = ""
    return
  end

  local triggers = {}
  if UI and UI.Bindings and UI.Bindings.ParseCSVNumbers then
    local ids = UI.Bindings:ParseCSVNumbers(model.castSpellIDs)
    for i = 1, #ids do
      local spellID = tonumber(ids[i])
      if spellID and spellID > 0 then
        triggers[#triggers + 1] = {
          spellID = spellID,
          stackAmount = math.max(1, tonumber(model.stackAmount) or 1),
        }
      end
    end
  end
  model.produceTriggers = triggers
end

local function getIntentSummary(model)
  local intent = tostring(model._wizardIntent or "buff_player")
  if intent == "cooldown_player" then
    return "My cooldown"
  elseif intent == "debuff_target" then
    return "Debuff on target"
  end
  return "Buff on me"
end

function AuraWizard:HideStage()
  for i = 1, #(self.intentButtons or {}) do
    self.intentButtons[i]:Hide()
  end
  for i = 1, #(self.artifactButtons or {}) do
    self.artifactButtons[i]:Hide()
  end
  for i = 1, #(self.quickStartButtons or {}) do
    self.quickStartButtons[i]:Hide()
  end

  self.nameLabel:Hide()
  self.nameEdit:Hide()
  self.auraLabel:Hide()
  self.auraEdit:Hide()
  self.triggerLabel:Hide()
  self.triggerEdit:Hide()
  self.durationLabel:Hide()
  self.durationEdit:Hide()
  self.groupLabel:Hide()
  self.groupEdit:Hide()
  self.lowTimeLabel:Hide()
  self.lowTimeEdit:Hide()
  self.textLabel:Hide()
  self.layoutLabel:Hide()
  self.emphasisLabel:Hide()
  self.soundLabel:Hide()
  self.glowProfileLabel:Hide()
  self.detailNote:Hide()
  self.review:Hide()
  if self.dropTarget then
    self.dropTarget:Hide()
  end
  for i = 1, #(self.labelButtons or {}) do
    self.labelButtons[i]:Hide()
  end
  for i = 1, #(self.timerButtons or {}) do
    self.timerButtons[i]:Hide()
  end
  for i = 1, #(self.emphasisButtons or {}) do
    self.emphasisButtons[i]:Hide()
  end
  for i = 1, #(self.soundButtons or {}) do
    self.soundButtons[i]:Hide()
  end
  for i = 1, #(self.timerAnchorButtons or {}) do
    self.timerAnchorButtons[i]:Hide()
  end
  for i = 1, #(self.textAnchorButtons or {}) do
    self.textAnchorButtons[i]:Hide()
  end
  for i = 1, #(self.glowProfileButtons or {}) do
    self.glowProfileButtons[i]:Hide()
  end
end

function AuraWizard:SyncFromFields()
  self.model.name = trim(self.nameEdit:GetText())
  self.model.spellID = toSpellID(self.auraEdit:GetText())
  self.model.castSpellIDs = trim(self.triggerEdit:GetText())
  self.model.group = trim(self.groupEdit:GetText())
  self.model.lowTime = tonumber(self.lowTimeEdit:GetText()) or 3

  if tostring(self.model._wizardIntent or "") == "debuff_target" then
    self.model.estimatedDuration = tonumber(self.durationEdit:GetText()) or 8
  else
    self.model.duration = tonumber(self.durationEdit:GetText()) or 8
  end

  if self.model.name == "" then
    local spellName = getSpellName(self.model.spellID)
    if spellName ~= "" then
      self.model.name = spellName
    else
      self.model.name = "New Aura"
    end
    self.nameEdit:SetText(self.model.name)
  end
end

function AuraWizard:RenderIntentStep()
  self.nameLabel:SetText("Aura Name")
  self.nameLabel:SetPoint("TOPLEFT", 24, -118)
  self.nameLabel:Show()
  self.nameEdit:SetPoint("TOPLEFT", 24, -136)
  self.nameEdit:SetText(tostring(self.model.name or "New Aura"))
  self.nameEdit:Show()

  self.auraLabel:SetText("Aura SpellID")
  self.auraLabel:SetPoint("TOPLEFT", 24, -178)
  self.auraLabel:Show()
  self.auraEdit:SetPoint("TOPLEFT", 24, -196)
  self.auraEdit:SetText(tostring(self.model.spellID or ""))
  self.auraEdit:Show()

  self.detailNote:SetPoint("TOPLEFT", 24, -234)
  self.detailNote:SetPoint("RIGHT", -24, 0)
  self.detailNote:SetText("Start with the aura you want to show, then choose the job AuraLite should do for it.")
  self.detailNote:Show()

  local positions = {
    { 24, -278 },
    { 298, -278 },
    { 24, -364 },
    { 298, -364 },
  }
  for i = 1, #self.intentButtons do
    local btn = self.intentButtons[i]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", positions[i][1], positions[i][2])
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, (INTENT_PRESETS[i].key == self.model._wizardIntent) and "selected" or "normal")
    end
    btn:Show()
  end
end

function AuraWizard:RenderTriggerStep()
  local intent = tostring(self.model._wizardIntent or "buff_player")
  local requiresCastInput = (intent == "buff_player" or intent == "debuff_target")
  local cooldownRead = (intent == "cooldown_player")

  self.detailNote:SetPoint("TOPLEFT", 24, -118)
  self.detailNote:SetPoint("RIGHT", -24, 0)
  if cooldownRead then
    self.detailNote:SetText("Cooldown artifacts read the spell cooldown directly. No trigger list is needed here.")
  else
    self.detailNote:SetText("Drag spells into the drop zone or type SpellIDs. AuraLite will use them as the primary trigger list.")
  end
  self.detailNote:Show()

  if self.dropTarget then
    self.dropTarget:SetPoint("TOPLEFT", 24, -154)
    self.dropTarget:SetPoint("RIGHT", -24, 0)
    self.dropTarget:SetTitle("Drop a spell or item here")
    self.dropTarget:SetSubtitle("Add trigger spells directly from your spellbook, action bar, or a usable item.")
    self.dropTarget:SetShown(not cooldownRead)
  end

  if requiresCastInput then
    self.triggerLabel:SetText("Trigger SpellIDs")
    self.triggerLabel:SetPoint("TOPLEFT", 24, -226)
    self.triggerLabel:Show()
    self.triggerEdit:SetPoint("TOPLEFT", 24, -244)
    self.triggerEdit:SetText(tostring(self.model.castSpellIDs or ""))
    self.triggerEdit:Show()
    self.durationLabel:SetText((intent == "debuff_target") and "Expected Duration (sec)" or "Duration (sec)")
    self.durationLabel:SetPoint("TOPLEFT", 24, -286)
    self.durationLabel:Show()
    self.durationEdit:SetPoint("TOPLEFT", 24, -304)
    self.durationEdit:SetText(tostring((intent == "debuff_target") and (self.model.estimatedDuration or 8) or (self.model.duration or 8)))
    self.durationEdit:Show()
  end
end

function AuraWizard:RenderArtifactStep()
  self.detailNote:SetPoint("TOPLEFT", 24, -118)
  self.detailNote:SetPoint("RIGHT", -24, 0)
  self.detailNote:SetText("Choose the artifact shell first, then pick a quick start. The full inspector will open on this aura for deeper tuning.")
  self.detailNote:Show()

  local positions = {
    { 24, -154 },
    { 298, -154 },
    { 24, -240 },
    { 298, -240 },
  }
  for i = 1, #self.artifactButtons do
    local btn = self.artifactButtons[i]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", positions[i][1], positions[i][2])
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, (ARTIFACT_PRESETS[i].key == self.model._wizardArtifact) and "selected" or "normal")
    end
    btn:Show()
  end

  self.quickStartLabel:SetPoint("TOPLEFT", 24, -330)
  self.quickStartLabel:SetText("Quick Starts")
  self.quickStartLabel:Show()

  local quickPositions = {
    { 24, -348 },
    { 298, -348 },
    { 24, -404 },
    { 298, -404 },
  }
  for i = 1, #self.quickStartButtons do
    local btn = self.quickStartButtons[i]
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", quickPositions[i][1], quickPositions[i][2])
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, (QUICK_STARTS[i].key == self.model.stylePreset) and "selected" or "normal")
    end
    btn:Show()
  end

  self.textLabel:SetPoint("TOPLEFT", 24, -470)
  self.textLabel:SetText("Text")
  self.textLabel:Show()

  self.labelButtons[1]:SetPoint("TOPLEFT", 24, -488)
  self.labelButtons[2]:SetPoint("TOPLEFT", 120, -488)
  self.timerButtons[1]:SetPoint("TOPLEFT", 298, -488)
  self.timerButtons[2]:SetPoint("TOPLEFT", 394, -488)
  for i = 1, #self.labelButtons do
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(self.labelButtons[i], (i == 1 and self.model.showCustomText ~= false) or (i == 2 and self.model.showCustomText == false))
    end
    self.labelButtons[i]:Show()
  end
  for i = 1, #self.timerButtons do
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(self.timerButtons[i], (i == 1 and self.model.showTimerText ~= false) or (i == 2 and self.model.showTimerText == false))
    end
    self.timerButtons[i]:Show()
  end

  self.layoutLabel:SetPoint("TOPLEFT", 24, -522)
  self.layoutLabel:SetText("Placement")
  self.layoutLabel:Show()
  self.timerAnchorButtons[1]:SetPoint("TOPLEFT", 24, -540)
  self.timerAnchorButtons[2]:SetPoint("TOPLEFT", 120, -540)
  self.textAnchorButtons[1]:SetPoint("TOPLEFT", 298, -540)
  self.textAnchorButtons[2]:SetPoint("TOPLEFT", 394, -540)
  for i = 1, #self.timerAnchorButtons do
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(self.timerAnchorButtons[i], self.timerAnchorButtons[i]._wizardValue == tostring(self.model.timerAnchor or "BOTTOM"))
    end
    self.timerAnchorButtons[i]:Show()
  end
  for i = 1, #self.textAnchorButtons do
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(self.textAnchorButtons[i], self.textAnchorButtons[i]._wizardValue == tostring(self.model.customTextAnchor or "TOP"))
    end
    self.textAnchorButtons[i]:Show()
  end

  self.emphasisLabel:SetPoint("TOPLEFT", 24, -574)
  self.emphasisLabel:SetText("Emphasis")
  self.emphasisLabel:Show()
  local emphasisX = 24
  local gainMode = tostring(((self.model.visualStates or {}).onGain) or "off")
  for i = 1, #self.emphasisButtons do
    local btn = self.emphasisButtons[i]
    btn:SetPoint("TOPLEFT", emphasisX, -592)
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(btn, btn._wizardValue == gainMode)
    end
    btn:Show()
    emphasisX = emphasisX + btn:GetWidth() + 6
  end

  self.soundLabel:SetPoint("TOPLEFT", 298, -574)
  self.soundLabel:SetText("Sound")
  self.soundLabel:Show()
  local soundX = 298
  local soundPreset = tostring(self.model._wizardSoundPreset or "default")
  for i = 1, #self.soundButtons do
    local btn = self.soundButtons[i]
    btn:SetPoint("TOPLEFT", soundX, -592)
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(btn, btn._wizardValue == soundPreset)
    end
    btn:Show()
    soundX = soundX + btn:GetWidth() + 6
  end

  self.glowProfileLabel:SetPoint("TOPLEFT", 24, -626)
  self.glowProfileLabel:SetText("Glow Profile")
  self.glowProfileLabel:Show()
  local glowX = 24
  local glowProfile = tostring(self.model._wizardGlowProfile or "balanced")
  for i = 1, #self.glowProfileButtons do
    local btn = self.glowProfileButtons[i]
    btn:SetPoint("TOPLEFT", glowX, -644)
    if Skin and Skin.SetButtonSelected then
      Skin:SetButtonSelected(btn, btn._wizardValue == glowProfile)
    end
    btn:Show()
    glowX = glowX + btn:GetWidth() + 6
  end

  self.groupLabel:SetText("Group")
  self.groupLabel:SetPoint("TOPLEFT", 24, -678)
  self.groupLabel:Show()
  self.groupEdit:SetPoint("TOPLEFT", 24, -696)
  self.groupEdit:SetText(tostring(self.model.group or ""))
  self.groupEdit:Show()

  self.lowTimeLabel:SetText("Low-Time Warning (sec)")
  self.lowTimeLabel:SetPoint("TOPLEFT", 312, -678)
  self.lowTimeLabel:Show()
  self.lowTimeEdit:SetPoint("TOPLEFT", 312, -696)
  self.lowTimeEdit:SetText(tostring(self.model.lowTime or 3))
  self.lowTimeEdit:Show()
end

function AuraWizard:RenderReviewStep()
  ensureDraftTriggers(self.model)
  self.review:SetPoint("TOPLEFT", 24, -122)
  self.review:SetPoint("RIGHT", -24, 0)
  self.review:SetJustifyH("LEFT")
  self.review:SetJustifyV("TOP")

  local durationValue = tostring((self.model._wizardIntent == "debuff_target") and (self.model.estimatedDuration or 8) or (self.model.duration or 8))
  local lines = {
    "Intent: " .. getIntentSummary(self.model),
    "Aura: " .. (getSpellName(self.model.spellID) ~= "" and (getSpellName(self.model.spellID) .. " (" .. tostring(self.model.spellID or "") .. ")") or tostring(self.model.spellID or "")),
    "Name: " .. tostring(self.model.name or "New Aura"),
    "Triggers: " .. ((trim(self.model.castSpellIDs) ~= "" and tostring(self.model.castSpellIDs)) or "Direct read / cooldown"),
    "Artifact: " .. tostring(self.model._wizardArtifact or "iconbar"),
    "Quick Start: " .. ((trim(self.model.stylePreset) ~= "" and tostring(self.model.stylePreset)) or "None"),
    "Label Text: " .. ((self.model.showCustomText ~= false) and "Shown" or "Hidden"),
    "Timer Text: " .. ((self.model.showTimerText ~= false) and "Shown" or "Hidden"),
    "Timer Placement: " .. tostring(self.model.timerAnchor or "BOTTOM"),
    "Text Placement: " .. tostring(self.model.customTextAnchor or "TOP"),
    "Emphasis: " .. tostring((((self.model.visualStates or {}).onGain) or "off")),
    "Sound: " .. tostring(self.model._wizardSoundPreset or "default"),
    "Glow Profile: " .. tostring(self.model._wizardGlowProfile or "balanced"),
    "Duration: " .. durationValue .. " sec",
    "Group: " .. ((trim(self.model.group) ~= "" and tostring(self.model.group)) or "No group"),
  }
  self.review:SetText(table.concat(lines, "\n"))
  self.review:Show()
end

function AuraWizard:RenderStep()
  local stepName = STEPS[self.step] or STEPS[1]
  self:HideStage()
  self.lblStep:SetText(string.format("Step %d/%d - %s", self.step, #STEPS, stepName))

  if stepName == "Intent" then
    self:RenderIntentStep()
  elseif stepName == "Trigger" then
    self:RenderTriggerStep()
  elseif stepName == "Artifact" then
    self:RenderArtifactStep()
  else
    self:RenderReviewStep()
  end

  self.btnPrev:SetEnabled(self.step > 1)
  self.btnNext:SetEnabled(self.step < #STEPS)
  self.btnFinish:SetEnabled(self.step == #STEPS)
end

function AuraWizard:Open(anchor)
  self.model = UI.Bindings and UI.Bindings:NewDraft("") or {}
  self.model.name = "New Aura"
  self.model.soundOnShow = self.model.soundOnShow or "default"
  self.model.soundOnLow = self.model.soundOnLow or "default"
  self.model.soundOnExpire = self.model.soundOnExpire or "none"
  self.model.lowTime = self.model.lowTime or 3
  self.model.duration = self.model.duration or 8
  self.model.estimatedDuration = self.model.estimatedDuration or 8
  self.model.stylePreset = self.model.stylePreset or "compact_tracker"
  self.model.showCustomText = self.model.showCustomText ~= false
  self.model.showTimerText = self.model.showTimerText ~= false
  self.model.timerAnchor = self.model.timerAnchor or "BOTTOM"
  self.model.customTextAnchor = self.model.customTextAnchor or "TOP"
  self.model.visualStates = self.model.visualStates or {}
  applyIntent(self.model, "buff_player")
  applyArtifact(self.model, "iconbar")
  applySoundPreset(self.model, "default")
  applyGlowProfile(self.model, "balanced")
  self.step = 1
  self.frame:ClearAllPoints()
  self.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 36)
  self.frame:Raise()
  self.frame:Show()
  self:RenderStep()
end

function AuraWizard:Finish()
  self:SyncFromFields()
  ensureDraftTriggers(self.model)

  local repo = UI.AuraRepository
  if not repo or not repo.CreateDraft then
    self.frame:Hide()
    return
  end

  local draft = repo:CreateDraft()
  for key, value in pairs(self.model) do
    draft[key] = value
  end

  applyIntent(draft, draft._wizardIntent)
  applyArtifact(draft, draft._wizardArtifact)

  if tostring(draft._wizardIntent or "") == "cooldown_player" then
    draft.castSpellIDs = ""
    draft.produceTriggers = {}
  elseif tostring(draft._wizardIntent or "") == "debuff_target" then
    draft.onlyMine = true
    draft.duration = tonumber(draft.estimatedDuration or draft.duration) or 8
  else
    draft.duration = tonumber(draft.duration) or 8
  end

  local savedId = draft.id
  if repo.SaveDraft then
    local ok, newSavedId = repo:SaveDraft(draft)
    if ok then
      savedId = newSavedId or savedId
      if S and S.SetSelectedAura then
        S:SetSelectedAura(savedId, "wizard")
      end
      if S and S.SetActiveTab then
        S:SetActiveTab("Appearance")
      end
      if S and S.SetDirty then
        S:SetDirty(false)
      end
    end
  end

  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "wizard", value = savedId })
  end
  self.frame:Hide()
end

function AuraWizard:Create(parent)
  local o = setmetatable({}, self)
  o.step = 1
  o.model = {}
  o.intentButtons = {}
  o.artifactButtons = {}
  o.quickStartButtons = {}
  o.labelButtons = {}
  o.timerButtons = {}
  o.emphasisButtons = {}
  o.soundButtons = {}
  o.timerAnchorButtons = {}
  o.textAnchorButtons = {}
  o.glowProfileButtons = {}

  o.auraField = { key = "spellID", widget = "spellid" }
  o.triggerField = { key = "castSpellIDs", widget = "spellcsv" }

  o.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  o.frame:SetSize(586, 744)
  applyFloatingWindowChrome(o.frame)
  createBackdrop(o.frame)
  o.frame:Hide()

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 18, -18)
  title:SetText("New Aura Flow")
  title:SetTextColor(0.98, 0.88, 0.34)
  attachDragHandle(o.frame, title)

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 18, -38)
  o.subtitle:SetPoint("RIGHT", -18, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("Choose the intent, capture the trigger, pick the artifact, then land in the full inspector for detailed authoring.")
  attachDragHandle(o.frame, o.subtitle)

  o.hero = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  o.hero:SetPoint("TOPLEFT", 18, -62)
  o.hero:SetPoint("TOPRIGHT", -18, -62)
  o.hero:SetHeight(36)
  if Skin and Skin.ApplyInsetPanel then
    Skin:ApplyInsetPanel(o.hero)
  end
  attachDragHandle(o.frame, o.hero)

  o.lblStep = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblStep:SetPoint("LEFT", o.hero, "LEFT", 12, 0)
  o.lblStep:SetText("Step")

  o.heroHint = o.hero:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.heroHint:SetPoint("RIGHT", -12, 0)
  o.heroHint:SetText("Artifact-first authoring flow")

  o.nameLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.nameEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.nameEdit:SetAutoFocus(false)
  o.nameEdit:SetSize(248, 24)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.nameEdit)
  end

  o.auraLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.auraEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.auraEdit:SetAutoFocus(false)
  o.auraEdit:SetSize(248, 24)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.auraEdit)
  end

  o.triggerLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.triggerEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.triggerEdit:SetAutoFocus(false)
  o.triggerEdit:SetSize(420, 24)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.triggerEdit)
  end

  o.durationLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.durationEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.durationEdit:SetAutoFocus(false)
  o.durationEdit:SetSize(118, 24)
  o.durationEdit:SetNumeric(true)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.durationEdit)
  end

  o.groupLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.groupEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.groupEdit:SetAutoFocus(false)
  o.groupEdit:SetSize(248, 24)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.groupEdit)
  end

  o.lowTimeLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lowTimeEdit = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.lowTimeEdit:SetAutoFocus(false)
  o.lowTimeEdit:SetSize(118, 24)
  o.lowTimeEdit:SetNumeric(true)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(o.lowTimeEdit)
  end

  o.textLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.layoutLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.emphasisLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.soundLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")

  o.detailNote = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.detailNote:SetJustifyH("LEFT")
  o.detailNote:SetJustifyV("TOP")
  o.detailNote:SetWordWrap(true)
  o.detailNote:Hide()

  o.quickStartLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.quickStartLabel:Hide()
  o.glowProfileLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.glowProfileLabel:Hide()

  o.labelButtons = {
    createChipButton(o.frame, 88, "Label On", true, function()
      o.model.showCustomText = true
      o:RenderStep()
    end),
    createChipButton(o.frame, 88, "Label Off", false, function()
      o.model.showCustomText = false
      o:RenderStep()
    end),
  }
  o.timerButtons = {
    createChipButton(o.frame, 88, "Timer On", true, function()
      o.model.showTimerText = true
      o:RenderStep()
    end),
    createChipButton(o.frame, 88, "Timer Off", false, function()
      o.model.showTimerText = false
      o:RenderStep()
    end),
  }
  o.timerAnchorButtons = {
    createChipButton(o.frame, 88, "Timer Top", false, function()
      o.model.timerAnchor = "TOP"
      o:RenderStep()
    end),
    createChipButton(o.frame, 88, "Timer Bottom", true, function()
      o.model.timerAnchor = "BOTTOM"
      o:RenderStep()
    end),
  }
  o.timerAnchorButtons[1]._wizardValue = "TOP"
  o.timerAnchorButtons[2]._wizardValue = "BOTTOM"
  o.textAnchorButtons = {
    createChipButton(o.frame, 88, "Text Top", true, function()
      o.model.customTextAnchor = "TOP"
      o:RenderStep()
    end),
    createChipButton(o.frame, 88, "Text Bottom", false, function()
      o.model.customTextAnchor = "BOTTOM"
      o:RenderStep()
    end),
  }
  o.textAnchorButtons[1]._wizardValue = "TOP"
  o.textAnchorButtons[2]._wizardValue = "BOTTOM"
  o.emphasisButtons = {
    createChipButton(o.frame, 64, "Off", false, function()
      o.model.visualStates = o.model.visualStates or {}
      o.model.visualStates.onGain = "off"
      o:RenderStep()
    end),
    createChipButton(o.frame, 64, "Soft", false, function()
      o.model.visualStates = o.model.visualStates or {}
      o.model.visualStates.onGain = "soft"
      o:RenderStep()
    end),
    createChipButton(o.frame, 72, "Burst", false, function()
      o.model.visualStates = o.model.visualStates or {}
      o.model.visualStates.onGain = "burst"
      o:RenderStep()
    end),
  }
  o.emphasisButtons[1]._wizardValue = "off"
  o.emphasisButtons[2]._wizardValue = "soft"
  o.emphasisButtons[3]._wizardValue = "burst"
  o.soundButtons = {
    createChipButton(o.frame, 74, "Silent", false, function()
      applySoundPreset(o.model, "silent")
      o:RenderStep()
    end),
    createChipButton(o.frame, 78, "Default", true, function()
      applySoundPreset(o.model, "default")
      o:RenderStep()
    end),
    createChipButton(o.frame, 68, "Raid", false, function()
      applySoundPreset(o.model, "raid")
      o:RenderStep()
    end),
  }
  o.soundButtons[1]._wizardValue = "silent"
  o.soundButtons[2]._wizardValue = "default"
  o.soundButtons[3]._wizardValue = "raid"
  o.glowProfileButtons = {
    createChipButton(o.frame, 72, "Quiet", false, function()
      applyGlowProfile(o.model, "quiet")
      o:RenderStep()
    end),
    createChipButton(o.frame, 84, "Balanced", true, function()
      applyGlowProfile(o.model, "balanced")
      o:RenderStep()
    end),
    createChipButton(o.frame, 72, "Heroic", false, function()
      applyGlowProfile(o.model, "heroic")
      o:RenderStep()
    end),
  }
  o.glowProfileButtons[1]._wizardValue = "quiet"
  o.glowProfileButtons[2]._wizardValue = "balanced"
  o.glowProfileButtons[3]._wizardValue = "heroic"

  o.review = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.review:Hide()

  if Widgets.DropTargetWidget and Widgets.DropTargetWidget.Create then
    o.dropTarget = Widgets.DropTargetWidget:Create(o.frame, {
      title = "Drop a spell or item here",
      subtitle = "Add trigger spells directly from your spellbook or action bar.",
      height = 56,
      onPayload = function()
        local spellID = resolvePayloadSpellID()
        if spellID and spellID > 0 then
          o.model.castSpellIDs = appendSpellIDCSV(o.model.castSpellIDs, spellID)
          o.triggerEdit:SetText(o.model.castSpellIDs)
          if trim(o.model.name) == "" or o.model.name == "New Aura" then
            local spellName = getSpellName(o.model.spellID)
            if spellName ~= "" then
              o.model.name = spellName
              o.nameEdit:SetText(spellName)
            end
          end
          ClearCursor()
        end
      end,
    })
  end

  for i = 1, #INTENT_PRESETS do
    local preset = INTENT_PRESETS[i]
    local btn = createChoiceButton(o.frame, 252, 72, preset.label, preset.body, i == 1, function()
      applyIntent(o.model, preset.key)
      o:RenderStep()
    end)
    o.intentButtons[#o.intentButtons + 1] = btn
  end

  for i = 1, #ARTIFACT_PRESETS do
    local preset = ARTIFACT_PRESETS[i]
    local btn = createChoiceButton(o.frame, 252, 72, preset.label, preset.body, preset.key == "iconbar", function()
      applyArtifact(o.model, preset.key)
      o:RenderStep()
    end)
    o.artifactButtons[#o.artifactButtons + 1] = btn
  end

  for i = 1, #QUICK_STARTS do
    local preset = QUICK_STARTS[i]
    local btn = createChoiceButton(o.frame, 252, 44, preset.label, preset.body, preset.key == "compact_tracker", function()
      o.model.stylePreset = preset.key
      o:RenderStep()
    end)
    o.quickStartButtons[#o.quickStartButtons + 1] = btn
  end

  if FieldFactory and FieldFactory.AttachSpellResolver then
    FieldFactory.AttachSpellResolver(o.frame, o.auraEdit, o.auraField, function(key, value)
      o.model[key] = value
      local spellName = getSpellName(value)
      if spellName ~= "" and (trim(o.model.name) == "" or o.model.name == "New Aura") then
        o.model.name = spellName
        o.nameEdit:SetText(spellName)
      end
    end)
    FieldFactory.AttachSpellResolver(o.frame, o.triggerEdit, o.triggerField, function(key, value)
      o.model[key] = value
    end)
  end

  o.btnPrev = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnPrev:SetSize(80, 22)
  o.btnPrev:SetPoint("BOTTOMLEFT", 18, 16)
  o.btnPrev:SetText("Prev")
  o.btnPrev:SetScript("OnClick", function()
    o:SyncFromFields()
    o.step = math.max(1, o.step - 1)
    o:RenderStep()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnPrev, "ghost")
  end

  o.btnNext = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnNext:SetSize(80, 22)
  o.btnNext:SetPoint("LEFT", o.btnPrev, "RIGHT", 6, 0)
  o.btnNext:SetText("Next")
  o.btnNext:SetScript("OnClick", function()
    o:SyncFromFields()
    o.step = math.min(#STEPS, o.step + 1)
    o:RenderStep()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnNext, "default")
  end

  o.btnFinish = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnFinish:SetSize(102, 22)
  o.btnFinish:SetPoint("LEFT", o.btnNext, "RIGHT", 6, 0)
  o.btnFinish:SetText("Create Aura")
  o.btnFinish:SetScript("OnClick", function()
    o:Finish()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnFinish, "primary")
  end

  o.btnCancel = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnCancel:SetSize(74, 22)
  o.btnCancel:SetPoint("LEFT", o.btnFinish, "RIGHT", 6, 0)
  o.btnCancel:SetText("Cancel")
  o.btnCancel:SetScript("OnClick", function()
    o.frame:Hide()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnCancel, "ghost")
  end

  return o
end

Panels.AuraWizard = AuraWizard
UI.AuraWizard = AuraWizard
