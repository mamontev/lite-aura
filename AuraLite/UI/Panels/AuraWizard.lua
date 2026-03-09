local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State

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

function AuraWizard:RenderStep()
  local stepName = STEPS[self.step] or "Type"
  self.lblStep:SetText(string.format("Step %d/%d - %s", self.step, #STEPS, stepName))
  self.editA:SetShown(false)
  self.editB:SetShown(false)
  self.ddA:SetShown(false)
  self.ddB:SetShown(false)
  self.lblA:SetText("")
  self.lblB:SetText("")
  self.review:SetText("")

  if stepName == "Type" then
    self.lblA:SetText("Aura Name")
    self.editA:SetText(tostring(self.model.name or "New Aura"))
    self.editA:SetShown(true)

    self.lblB:SetText("Aura SpellID")
    self.editB:SetText(tostring(self.model.spellID or ""))
    self.editB:SetShown(true)
  elseif stepName == "Trigger" then
    self.lblA:SetText("WHEN Cast SpellIDs (CSV)")
    self.editA:SetText(tostring(self.model.castSpellIDs or ""))
    self.editA:SetShown(true)

    self.lblB:SetText("Action")
    self.ddA:SetShown(true)
    UIDropDownMenu_SetText(self.ddA, self.model.actionMode == "consume" and "Consume" or "Produce")
  elseif stepName == "Display" then
    self.lblA:SetText("Display Mode")
    self.ddA:SetShown(true)
    UIDropDownMenu_SetText(self.ddA, tostring(self.model.displayMode or "iconbar"))

    self.lblB:SetText("Unit")
    self.ddB:SetShown(true)
    UIDropDownMenu_SetText(self.ddB, tostring(self.model.unit or "player"))
  elseif stepName == "Behavior" then
    self.lblA:SetText("Duration (sec)")
    self.editA:SetText(tostring(self.model.duration or 8))
    self.editA:SetShown(true)

    self.lblB:SetText("Low-Time")
    self.editB:SetText(tostring(self.model.lowTime or 3))
    self.editB:SetShown(true)
  elseif stepName == "Sound" then
    self.lblA:SetText("Sound On Show")
    self.editA:SetText(tostring(self.model.soundOnShow or "default"))
    self.editA:SetShown(true)

    self.lblB:SetText("Sound On Expire")
    self.editB:SetText(tostring(self.model.soundOnExpire or "none"))
    self.editB:SetShown(true)
  elseif stepName == "Review" then
    local lines = {
      "Name: " .. tostring(self.model.name or ""),
      "Aura SpellID: " .. tostring(self.model.spellID or ""),
      "Cast SpellIDs: " .. tostring(self.model.castSpellIDs or ""),
      "Action: " .. tostring(self.model.actionMode or "produce"),
      "Display: " .. tostring(self.model.displayMode or "iconbar"),
      "Duration: " .. tostring(self.model.duration or 8),
      "Unit: " .. tostring(self.model.unit or "player"),
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
    self.model.castSpellIDs = tostring(self.editA:GetText() or "")
  elseif stepName == "Behavior" then
    self.model.duration = tonumber(self.editA:GetText()) or 8
    self.model.lowTime = tonumber(self.editB:GetText()) or 3
  elseif stepName == "Sound" then
    self.model.soundOnShow = tostring(self.editA:GetText() or "default")
    self.model.soundOnExpire = tostring(self.editB:GetText() or "none")
  end
end

function AuraWizard:Open(anchor)
  self.model = UI.Bindings and UI.Bindings:NewDraft("") or {}
  self.model.displayMode = "iconbar"
  self.model.unit = "player"
  self.model.group = "important_procs"
  self.model.actionMode = "produce"
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
    local function add(value, label)
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        if stepName == "Trigger" then
          o.model.actionMode = value
        elseif stepName == "Display" then
          o.model.displayMode = value
        end
        o:RenderStep()
      end
      UIDropDownMenu_AddButton(info, level)
    end
    if stepName == "Trigger" then
      add("produce", "Produce")
      add("consume", "Consume")
    elseif stepName == "Display" then
      add("icon", "icon")
      add("bar", "bar")
      add("iconbar", "iconbar")
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
    if stepName ~= "Display" then
      return
    end
    local function add(value, label)
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        o.model.unit = value
        o:RenderStep()
      end
      UIDropDownMenu_AddButton(info, level)
    end
    add("player", "player")
    add("target", "target")
  end)

  o.review = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.review:SetPoint("TOPLEFT", 10, -64)
  o.review:SetPoint("RIGHT", -12, 0)
  o.review:SetJustifyH("LEFT")
  o.review:SetJustifyV("TOP")

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
