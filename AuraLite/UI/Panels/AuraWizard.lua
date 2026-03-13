local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local FieldFactory = UI.FieldFactory
local Skin = ns.UISkin

local AuraWizard = {}
AuraWizard.__index = AuraWizard

local STEPS = {
  "Basics",
  "Tracking",
  "Display",
  "Review",
}

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.01, 0.07, 0.15, 0.97)
  frame:SetBackdropBorderColor(0.12, 0.52, 0.86, 0.95)
end

local function toSpellID(value)
  local n = tonumber(value)
  if n and n > 0 then
    return tostring(math.floor(n))
  end
  return ""
end

local function setDropdownText(dropdown, value, options)
  value = tostring(value or "")
  for i = 1, #(options or {}) do
    local row = options[i]
    if tostring(row.value) == value then
      UIDropDownMenu_SetText(dropdown, row.label)
      return
    end
  end
  UIDropDownMenu_SetText(dropdown, value ~= "" and value or "Choose...")
end

local function applyUnitMode(model, unit)
  model.unit = unit or "player"
  if model.unit == "target" then
    model.trackingMode = tostring(model.trackingMode or "confirmed")
    model.triggerType = (model.trackingMode == "estimated") and "cast" or "aura"
    model.actionMode = "produce"
  else
    model.trackingMode = "confirmed"
    model.triggerType = "cast"
    model.actionMode = tostring(model.actionMode or "produce")
  end
end

local function applyTargetTrackingMode(model, trackingMode)
  model.trackingMode = (tostring(trackingMode or "confirmed") == "estimated") and "estimated" or "confirmed"
  applyUnitMode(model, "target")
  if model.trackingMode == "estimated" then
    model.onlyMine = true
  end
end

local function isEstimatedTarget(model)
  return tostring(model.unit or "player") == "target" and tostring(model.trackingMode or "confirmed") == "estimated"
end

local function isConfirmedTarget(model)
  return tostring(model.unit or "player") == "target" and tostring(model.trackingMode or "confirmed") ~= "estimated"
end

function AuraWizard:SyncSpellBindings(stepName)
  self.editAField.key = "editA"
  self.editAField.widget = "text"
  self.editBField.key = "editB"
  self.editBField.widget = "text"
  self.editCField.key = "editC"
  self.editCField.widget = "text"
  self.editDField.key = "editD"
  self.editDField.widget = "text"

  if stepName == "Basics" then
    self.editBField.key = "spellID"
    self.editBField.widget = "spellid"
  elseif stepName == "Tracking" then
    if isEstimatedTarget(self.model) then
      self.editCField.key = "castSpellIDs"
      self.editCField.widget = "spellcsv"
    elseif tostring(self.model.unit or "player") ~= "target" then
      self.editBField.key = "castSpellIDs"
      self.editBField.widget = "spellcsv"
      self.editCField.key = "duration"
    end
  end
end

function AuraWizard:HideInputs()
  self.editA:Hide()
  self.editB:Hide()
  self.editC:Hide()
  self.editD:Hide()
  self.ddA:Hide()
  self.ddB:Hide()
  self.lblA:SetText("")
  self.lblB:SetText("")
  self.lblC:SetText("")
  self.lblD:SetText("")
  self.review:SetText("")
  self.stepNote:SetText("")
  self.stepNote:Hide()
end

function AuraWizard:RenderStep()
  local stepName = STEPS[self.step] or "Basics"
  self.lblStep:SetText(string.format("Step %d/%d - %s", self.step, #STEPS, stepName))
  self:HideInputs()
  self:SyncSpellBindings(stepName)

  if stepName == "Basics" then
    self.lblA:SetText("Aura Name")
    self.editA:SetText(tostring(self.model.name or "New Aura"))
    self.editA:Show()

    self.lblB:SetText("Aura SpellID")
    self.editB:SetText(tostring(self.model.spellID or ""))
    self.editB:Show()

    self.stepNote:SetPoint("TOPLEFT", 14, -180)
    self.stepNote:SetPoint("RIGHT", -18, 0)
    self.stepNote:SetText("Start with the aura you want to display. The next step will ask how AuraLite should trigger it.")
    self.stepNote:Show()
  elseif stepName == "Tracking" then
    self.lblA:SetText("Where To Track")
    self.ddA:Show()
    setDropdownText(self.ddA, self.model.unit or "player", {
      { value = "player", label = "Player" },
      { value = "target", label = "Target" },
    })

    if tostring(self.model.unit or "player") == "target" then
      self.lblB:SetText("How To Track")
      self.ddB:Show()
      setDropdownText(self.ddB, self.model.trackingMode or "confirmed", {
        { value = "confirmed", label = "Confirmed Aura Read" },
        { value = "estimated", label = "Estimated From My Cast" },
      })

      if isEstimatedTarget(self.model) then
        self.lblC:SetText("SpellIDs I Cast (CSV)")
        self.editC:SetText(tostring(self.model.castSpellIDs or ""))
        self.editC:Show()

        self.lblD:SetText("Expected Duration (sec)")
        self.editD:SetText(tostring(self.model.estimatedDuration or 8))
        self.editD:Show()

        self.stepNote:SetPoint("TOPLEFT", 14, -296)
        self.stepNote:SetPoint("RIGHT", -18, 0)
        self.stepNote:SetText("Best for debuffs you apply yourself. AuraLite watches your cast SpellIDs, then starts a local timer on your current target.")
        self.stepNote:Show()
      else
        self.stepNote:SetPoint("TOPLEFT", 14, -238)
        self.stepNote:SetPoint("RIGHT", -18, 0)
        self.stepNote:SetText("AuraLite will try to read the target aura directly. This is simpler to configure, but Blizzard can restrict target aura data in combat.")
        self.stepNote:Show()
      end
    else
      self.lblB:SetText("SpellIDs I Cast (CSV)")
      self.editB:SetText(tostring(self.model.castSpellIDs or ""))
      self.editB:Show()

      self.lblC:SetText("Timer Duration (sec)")
      self.editC:SetText(tostring(self.model.duration or 8))
      self.editC:Show()

      self.stepNote:SetPoint("TOPLEFT", 14, -296)
      self.stepNote:SetPoint("RIGHT", -18, 0)
      self.stepNote:SetText("Use this for player auras and proc-style timers. Add the cast SpellIDs that should start the aura.")
      self.stepNote:Show()
    end
  elseif stepName == "Display" then
    self.lblA:SetText("Display Mode")
    self.ddA:Show()
    setDropdownText(self.ddA, self.model.displayMode or "iconbar", {
      { value = "icon", label = "Icon" },
      { value = "bar", label = "Bar" },
      { value = "iconbar", label = "Icon + Bar" },
    })

    self.lblB:SetText("Group")
    self.editB:SetText(tostring(self.model.group or "important_procs"))
    self.editB:Show()

    self.lblC:SetText("Low-Time Warning (sec)")
    self.editC:SetText(tostring(self.model.lowTime or 3))
    self.editC:Show()

    self.stepNote:SetPoint("TOPLEFT", 14, -296)
    self.stepNote:SetPoint("RIGHT", -18, 0)
    self.stepNote:SetText("Keep this light. You can always open the full editor later if you want sounds, load conditions, or advanced styling.")
    self.stepNote:Show()
  elseif stepName == "Review" then
    local lines = {
      "Name: " .. tostring(self.model.name or ""),
      "Aura SpellID: " .. tostring(self.model.spellID or ""),
      "Track On: " .. tostring(self.model.unit or "player"),
      "Tracking: " .. (isEstimatedTarget(self.model) and "Estimated from your cast" or (isConfirmedTarget(self.model) and "Confirmed target aura read" or "Rule-based cast trigger")),
      "Cast SpellIDs: " .. tostring(self.model.castSpellIDs or "-"),
      "Duration: " .. tostring(isEstimatedTarget(self.model) and (self.model.estimatedDuration or 8) or (self.model.duration or 8)),
      "Display: " .. tostring(self.model.displayMode or "iconbar"),
      "Group: " .. tostring(self.model.group or "important_procs"),
    }
    self.review:SetText(table.concat(lines, "\n"))
  end

  self.btnPrev:SetEnabled(self.step > 1)
  self.btnNext:SetEnabled(self.step < #STEPS)
  self.btnFinish:SetEnabled(self.step == #STEPS)
end

function AuraWizard:SyncFromFields()
  local stepName = STEPS[self.step]
  if stepName == "Basics" then
    self.model.name = tostring(self.editA:GetText() or "")
    self.model.spellID = toSpellID(self.editB:GetText())
  elseif stepName == "Tracking" then
    if isEstimatedTarget(self.model) then
      self.model.castSpellIDs = tostring(self.editC:GetText() or "")
      self.model.estimatedDuration = tonumber(self.editD:GetText()) or 8
    elseif tostring(self.model.unit or "player") == "player" then
      self.model.castSpellIDs = tostring(self.editB:GetText() or "")
      self.model.duration = tonumber(self.editC:GetText()) or 8
    end
  elseif stepName == "Display" then
    self.model.group = tostring(self.editB:GetText() or "important_procs")
    self.model.lowTime = tonumber(self.editC:GetText()) or 3
  end
end

function AuraWizard:Open(anchor)
  self.model = UI.Bindings and UI.Bindings:NewDraft("") or {}
  self.model.name = "New Aura"
  self.model.displayMode = "iconbar"
  self.model.group = "important_procs"
  self.model.soundOnShow = self.model.soundOnShow or "default"
  self.model.soundOnExpire = self.model.soundOnExpire or "none"
  self.model.duration = self.model.duration or 8
  self.model.estimatedDuration = self.model.estimatedDuration or 8
  self.model.lowTime = self.model.lowTime or 3
  applyUnitMode(self.model, "player")
  self.step = 1
  if anchor then
    self.frame:ClearAllPoints()
    self.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -8)
  end
  self.frame:Show()
  self:RenderStep()
end

function AuraWizard:Create(parent)
  local o = setmetatable({}, self)
  o.step = 1
  o.model = {}
  o.editAField = { key = "editA", widget = "text" }
  o.editBField = { key = "editB", widget = "text" }
  o.editCField = { key = "editC", widget = "text" }
  o.editDField = { key = "editD", widget = "text" }

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetSize(430, 410)
  o.frame:SetFrameStrata("DIALOG")
  o.frame:SetToplevel(true)
  createBackdrop(o.frame)
  o.frame:Hide()

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 12, -10)
  title:SetText("Quick New Aura")

  o.lblStep = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblStep:SetPoint("TOPLEFT", 12, -32)
  o.lblStep:SetText("Step")

  o.lblA = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblA:SetPoint("TOPLEFT", 14, -60)

  o.editA = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editA:SetAutoFocus(false)
  o.editA:SetSize(300, 24)
  o.editA:SetPoint("TOPLEFT", 14, -76)

  o.ddA = CreateFrame("Frame", nil, o.frame, "UIDropDownMenuTemplate")
  o.ddA:SetPoint("TOPLEFT", -4, -70)
  UIDropDownMenu_SetWidth(o.ddA, 220)
  if Skin and Skin.ApplyDropdown then
    Skin:ApplyDropdown(o.ddA)
  end

  o.lblB = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblB:SetPoint("TOPLEFT", 14, -118)

  o.editB = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editB:SetAutoFocus(false)
  o.editB:SetSize(300, 24)
  o.editB:SetPoint("TOPLEFT", 14, -134)

  o.ddB = CreateFrame("Frame", nil, o.frame, "UIDropDownMenuTemplate")
  o.ddB:SetPoint("TOPLEFT", -4, -128)
  UIDropDownMenu_SetWidth(o.ddB, 220)
  if Skin and Skin.ApplyDropdown then
    Skin:ApplyDropdown(o.ddB)
  end

  o.lblC = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblC:SetPoint("TOPLEFT", 14, -176)

  o.editC = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editC:SetAutoFocus(false)
  o.editC:SetSize(300, 24)
  o.editC:SetPoint("TOPLEFT", 14, -192)

  o.lblD = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblD:SetPoint("TOPLEFT", 14, -234)

  o.editD = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editD:SetAutoFocus(false)
  o.editD:SetSize(300, 24)
  o.editD:SetPoint("TOPLEFT", 14, -250)

  UIDropDownMenu_Initialize(o.ddA, function(_, level)
    if level ~= 1 then
      return
    end
    local stepName = STEPS[o.step]
    local function add(value, label, onPick)
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        onPick(value)
        o:RenderStep()
      end
      UIDropDownMenu_AddButton(info, level)
    end

    if stepName == "Tracking" then
      add("player", "Player", function(value)
        applyUnitMode(o.model, value)
      end)
      add("target", "Target", function(value)
        applyUnitMode(o.model, value)
      end)
    elseif stepName == "Display" then
      add("icon", "Icon", function(value)
        o.model.displayMode = value
      end)
      add("bar", "Bar", function(value)
        o.model.displayMode = value
      end)
      add("iconbar", "Icon + Bar", function(value)
        o.model.displayMode = value
      end)
    end
  end)

  UIDropDownMenu_Initialize(o.ddB, function(_, level)
    if level ~= 1 then
      return
    end
    local stepName = STEPS[o.step]
    local function add(value, label, onPick)
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        onPick(value)
        o:RenderStep()
      end
      UIDropDownMenu_AddButton(info, level)
    end

    if stepName == "Tracking" and tostring(o.model.unit or "player") == "target" then
      add("confirmed", "Confirmed Aura Read", function(value)
        applyTargetTrackingMode(o.model, value)
      end)
      add("estimated", "Estimated From My Cast", function(value)
        applyTargetTrackingMode(o.model, value)
      end)
    end
  end)

  o.stepNote = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.stepNote:SetJustifyH("LEFT")
  o.stepNote:SetJustifyV("TOP")
  o.stepNote:Hide()

  o.review = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.review:SetPoint("TOPLEFT", 14, -64)
  o.review:SetPoint("RIGHT", -14, 0)
  o.review:SetJustifyH("LEFT")
  o.review:SetJustifyV("TOP")

  if FieldFactory and FieldFactory.AttachSpellResolver then
    FieldFactory.AttachSpellResolver(o.frame, o.editA, o.editAField, function(key, value)
      o.model[key] = value
    end)
    FieldFactory.AttachSpellResolver(o.frame, o.editB, o.editBField, function(key, value)
      o.model[key] = value
    end)
    FieldFactory.AttachSpellResolver(o.frame, o.editC, o.editCField, function(key, value)
      o.model[key] = value
    end)
    FieldFactory.AttachSpellResolver(o.frame, o.editD, o.editDField, function(key, value)
      o.model[key] = value
    end)
  end

  o.btnPrev = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnPrev:SetSize(80, 22)
  o.btnPrev:SetPoint("BOTTOMLEFT", 12, 10)
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
  o.btnFinish:SetSize(94, 22)
  o.btnFinish:SetPoint("LEFT", o.btnNext, "RIGHT", 6, 0)
  o.btnFinish:SetText("Create Aura")
  o.btnFinish:SetScript("OnClick", function()
    o:SyncFromFields()
    local repo = UI.AuraRepository
    if not repo or not repo.CreateDraft then
      o.frame:Hide()
      return
    end

    local draft = repo:CreateDraft()
    for k, v in pairs(o.model) do
      draft[k] = v
    end
    if isEstimatedTarget(draft) then
      draft.triggerType = "cast"
      draft.actionMode = "produce"
      draft.onlyMine = true
      draft.estimatedDuration = tonumber(draft.estimatedDuration) or 8
    elseif isConfirmedTarget(draft) then
      draft.triggerType = "aura"
      draft.actionMode = "produce"
      draft.castSpellIDs = ""
    else
      draft.triggerType = "cast"
      draft.actionMode = tostring(draft.actionMode or "produce")
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
      end
    end
    if E then
      E:Emit(E.Names.FILTER_CHANGED, { key = "wizard", value = savedId })
    end
    o.frame:Hide()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnFinish, "primary")
  end

  o.btnCancel = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnCancel:SetSize(70, 22)
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
