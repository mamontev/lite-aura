local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local FieldFactory = UI.FieldFactory

local AuraWizard = {}
AuraWizard.__index = AuraWizard

local STEPS = {
  "Type",
  "Trigger",
  "Display",
  "Behavior",
  "Sound",
  "Review",
}

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.01, 0.07, 0.15, 0.96)
  frame:SetBackdropBorderColor(0.12, 0.52, 0.86, 0.95)
end

local function toSpellID(value)
  local n = tonumber(value)
  if n and n > 0 then
    return tostring(math.floor(n))
  end
  return ""
end

local function soundOptions()
  if ns.SoundManager and ns.SoundManager.GetDropdownOptions then
    return ns.SoundManager:GetDropdownOptions(true)
  end
  return {
    { value = "default", label = "Default" },
    { value = "none", label = "None" },
  }
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
  model.triggerType = (model.unit == "target") and "aura" or "cast"
  if model.triggerType == "aura" then
    model.actionMode = "produce"
  end
end

function AuraWizard:SyncSpellBindings(stepName)
  self.editAField.key = "editA"
  self.editAField.widget = "text"
  self.editBField.key = "editB"
  self.editBField.widget = "text"

  if stepName == "Type" then
    self.editBField.key = "spellID"
    self.editBField.widget = "spellid"
  elseif stepName == "Trigger" and tostring(self.model.unit or "player") ~= "target" then
    self.editAField.key = "castSpellIDs"
    self.editAField.widget = "spellcsv"
  end
end

function AuraWizard:RenderStep()
  local stepName = STEPS[self.step] or "Type"
  local isTargetAura = tostring(self.model.unit or "player") == "target"

  self.lblStep:SetText(string.format("Step %d/%d - %s", self.step, #STEPS, stepName))
  self.editA:SetShown(false)
  self.editB:SetShown(false)
  self.ddA:SetShown(false)
  self.ddB:SetShown(false)
  self.lblA:SetText("")
  self.lblB:SetText("")
  self.review:SetText("")
  self.stepNote:SetText("")
  self.stepNote:Hide()

  self:SyncSpellBindings(stepName)

  if stepName == "Type" then
    self.lblA:SetText("Aura Name")
    self.editA:SetText(tostring(self.model.name or "New Aura"))
    self.editA:SetShown(true)

    self.lblB:SetText("Aura SpellID")
    self.editB:SetText(tostring(self.model.spellID or ""))
    self.editB:SetShown(true)
  elseif stepName == "Trigger" then
    if isTargetAura then
      self.lblA:SetText("Target Aura Check")
      self.stepNote:SetPoint("TOPLEFT", 10, -74)
      self.stepNote:SetPoint("RIGHT", -18, 0)
      self.stepNote:SetText("Target tracking is direct: no cast list and no produce/consume rule are required.")
      self.stepNote:Show()
    else
      self.lblA:SetText("WHEN Cast SpellIDs (CSV)")
      self.editA:SetText(tostring(self.model.castSpellIDs or ""))
      self.editA:SetShown(true)
    end

    self.lblB:SetText("Track Aura On")
    self.ddB:SetShown(true)
    setDropdownText(self.ddB, self.model.unit or "player", {
      { value = "player", label = "Player" },
      { value = "target", label = "Target" },
    })
  elseif stepName == "Display" then
    self.lblA:SetText("Display Mode")
    self.ddA:SetShown(true)
    setDropdownText(self.ddA, self.model.displayMode or "iconbar", {
      { value = "icon", label = "Icon" },
      { value = "bar", label = "Bar" },
      { value = "iconbar", label = "Icon + Bar" },
    })

    if isTargetAura then
      self.lblB:SetText("Target Tracking")
      self.stepNote:SetPoint("TOPLEFT", 10, -130)
      self.stepNote:SetPoint("RIGHT", -18, 0)
      self.stepNote:SetText("Target auras use the real aura presence on the target, so the action selector is disabled here.")
      self.stepNote:Show()
    else
      self.lblB:SetText("Action")
      self.ddB:SetShown(true)
      setDropdownText(self.ddB, self.model.actionMode or "produce", {
        { value = "produce", label = "Produce" },
        { value = "consume", label = "Consume" },
      })
    end
  elseif stepName == "Behavior" then
    self.lblA:SetText("Duration (sec)")
    self.editA:SetText(tostring(self.model.duration or 8))
    self.editA:SetShown(true)

    self.lblB:SetText("Low-Time")
    self.editB:SetText(tostring(self.model.lowTime or 3))
    self.editB:SetShown(true)
  elseif stepName == "Sound" then
    self.lblA:SetText("Sound On Show")
    self.ddA:SetShown(true)
    setDropdownText(self.ddA, self.model.soundOnShow or "default", soundOptions())

    self.lblB:SetText("Sound On Expire")
    self.ddB:SetShown(true)
    setDropdownText(self.ddB, self.model.soundOnExpire or "none", soundOptions())
  elseif stepName == "Review" then
    local lines = {
      "Name: " .. tostring(self.model.name or ""),
      "Aura SpellID: " .. tostring(self.model.spellID or ""),
      "Track On: " .. tostring(self.model.unit or "player"),
      "Trigger: " .. (isTargetAura and "Direct target aura" or ("Cast " .. tostring(self.model.castSpellIDs or ""))),
      "Action: " .. (isTargetAura and "Direct aura tracking" or tostring(self.model.actionMode or "produce")),
      "Display: " .. tostring(self.model.displayMode or "iconbar"),
      "Duration: " .. tostring(self.model.duration or 8),
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
  if stepName == "Type" then
    self.model.name = tostring(self.editA:GetText() or "")
    self.model.spellID = toSpellID(self.editB:GetText())
  elseif stepName == "Trigger" then
    if tostring(self.model.unit or "player") ~= "target" then
      self.model.castSpellIDs = tostring(self.editA:GetText() or "")
    end
  elseif stepName == "Behavior" then
    self.model.duration = tonumber(self.editA:GetText()) or 8
    self.model.lowTime = tonumber(self.editB:GetText()) or 3
  end
end

function AuraWizard:Open(anchor)
  self.model = UI.Bindings and UI.Bindings:NewDraft("") or {}
  self.model.displayMode = "iconbar"
  self.model.group = "important_procs"
  self.model.soundOnShow = self.model.soundOnShow or "default"
  self.model.soundOnExpire = self.model.soundOnExpire or "none"
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

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetSize(390, 330)
  o.frame:SetFrameStrata("DIALOG")
  o.frame:SetToplevel(true)
  createBackdrop(o.frame)
  o.frame:Hide()

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("Aura Wizard")

  o.lblStep = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblStep:SetPoint("TOPLEFT", 10, -30)
  o.lblStep:SetText("Step")

  o.lblA = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblA:SetPoint("TOPLEFT", 10, -56)
  o.lblB = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblB:SetPoint("TOPLEFT", 10, -112)

  o.editA = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editA:SetAutoFocus(false)
  o.editA:SetSize(280, 24)
  o.editA:SetPoint("TOPLEFT", 10, -72)

  o.editB = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editB:SetAutoFocus(false)
  o.editB:SetSize(280, 24)
  o.editB:SetPoint("TOPLEFT", 10, -128)

  o.ddA = CreateFrame("Frame", nil, o.frame, "UIDropDownMenuTemplate")
  o.ddA:SetPoint("TOPLEFT", -8, -72)
  UIDropDownMenu_SetWidth(o.ddA, 180)
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

    if stepName == "Display" then
      add("icon", "Icon", function(value)
        o.model.displayMode = value
      end)
      add("bar", "Bar", function(value)
        o.model.displayMode = value
      end)
      add("iconbar", "Icon + Bar", function(value)
        o.model.displayMode = value
      end)
    elseif stepName == "Sound" then
      local rows = soundOptions()
      for i = 1, #rows do
        local row = rows[i]
        add(row.value, row.label, function(value)
          o.model.soundOnShow = value
        end)
      end
    end
  end)

  o.ddB = CreateFrame("Frame", nil, o.frame, "UIDropDownMenuTemplate")
  o.ddB:SetPoint("TOPLEFT", -8, -128)
  UIDropDownMenu_SetWidth(o.ddB, 180)
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

    if stepName == "Trigger" then
      add("player", "Player", function(value)
        applyUnitMode(o.model, value)
      end)
      add("target", "Target", function(value)
        applyUnitMode(o.model, value)
      end)
    elseif stepName == "Display" and tostring(o.model.unit or "player") ~= "target" then
      add("produce", "Produce", function(value)
        o.model.actionMode = value
      end)
      add("consume", "Consume", function(value)
        o.model.actionMode = value
      end)
    elseif stepName == "Sound" then
      local rows = soundOptions()
      for i = 1, #rows do
        local row = rows[i]
        add(row.value, row.label, function(value)
          o.model.soundOnExpire = value
        end)
      end
    end
  end)

  o.stepNote = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.stepNote:SetJustifyH("LEFT")
  o.stepNote:SetJustifyV("TOP")
  o.stepNote:Hide()

  o.review = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.review:SetPoint("TOPLEFT", 10, -64)
  o.review:SetPoint("RIGHT", -12, 0)
  o.review:SetJustifyH("LEFT")
  o.review:SetJustifyV("TOP")

  if FieldFactory and FieldFactory.AttachSpellResolver then
    FieldFactory.AttachSpellResolver(o.frame, o.editA, o.editAField, function(key, value)
      o.model[key] = value
    end)
    FieldFactory.AttachSpellResolver(o.frame, o.editB, o.editBField, function(key, value)
      o.model[key] = value
    end)
  end

  o.btnPrev = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnPrev:SetSize(80, 22)
  o.btnPrev:SetPoint("BOTTOMLEFT", 10, 10)
  o.btnPrev:SetText("Prev")
  o.btnPrev:SetScript("OnClick", function()
    o:SyncFromFields()
    o.step = math.max(1, o.step - 1)
    o:RenderStep()
  end)

  o.btnNext = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnNext:SetSize(80, 22)
  o.btnNext:SetPoint("LEFT", o.btnPrev, "RIGHT", 6, 0)
  o.btnNext:SetText("Next")
  o.btnNext:SetScript("OnClick", function()
    o:SyncFromFields()
    o.step = math.min(#STEPS, o.step + 1)
    o:RenderStep()
  end)

  o.btnFinish = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnFinish:SetSize(90, 22)
  o.btnFinish:SetPoint("LEFT", o.btnNext, "RIGHT", 6, 0)
  o.btnFinish:SetText("Create")
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
    if repo.SaveDraft then
      local ok, savedId = repo:SaveDraft(draft)
      if ok and S and S.SetSelectedAura then
        S:SetSelectedAura(savedId, "wizard")
      end
    end
    if E then
      E:Emit(E.Names.FILTER_CHANGED, { key = "wizard", value = draft.id })
    end
    o.frame:Hide()
  end)

  o.btnCancel = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnCancel:SetSize(80, 22)
  o.btnCancel:SetPoint("LEFT", o.btnFinish, "RIGHT", 6, 0)
  o.btnCancel:SetText("Cancel")
  o.btnCancel:SetScript("OnClick", function()
    o.frame:Hide()
  end)

  return o
end

Panels.AuraWizard = AuraWizard
UI.AuraWizard = AuraWizard

