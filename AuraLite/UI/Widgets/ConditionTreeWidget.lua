local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets

local ConditionTree = {}
ConditionTree.__index = ConditionTree

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.05, 0.12, 0.62)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.8)
end

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

function ConditionTree:SetDraft(draft)
  self.draft = draft or {}
  if not self.draft.conditionLogic or self.draft.conditionLogic == "" then
    self.draft.conditionLogic = "all"
  end

  UIDropDownMenu_SetText(self.ddLogic, self.draft.conditionLogic == "any" and "OR (any)" or "AND (all)")
  self.editTalents:SetText(self.draft.talentSpellIDs or "")
  self.editAuras:SetText(self.draft.requiredAuraSpellIDs or "")
  self.cbCombat:SetChecked(self.draft.inCombatOnly == true)
  self:UpdateSummary()
end

function ConditionTree:UpdateSummary()
  local logic = (self.draft.conditionLogic == "any") and "OR" or "AND"
  local talents = trim(self.draft.talentSpellIDs)
  local auras = trim(self.draft.requiredAuraSpellIDs)
  local parts = { "IF " .. logic }
  if talents ~= "" then
    parts[#parts + 1] = "talent(" .. talents .. ")"
  end
  if auras ~= "" then
    parts[#parts + 1] = "aura(" .. auras .. ")"
  end
  if self.draft.inCombatOnly then
    parts[#parts + 1] = "inCombat"
  end
  if #parts == 1 then
    parts[#parts + 1] = "<none>"
  end
  self.summary:SetText(table.concat(parts, " + "))
end

function ConditionTree:NotifyChanged()
  self:UpdateSummary()
  if self.onChanged then
    self.onChanged(self.draft)
  end
end

function ConditionTree:Create(parent, onChanged)
  local o = setmetatable({}, self)
  o.onChanged = onChanged

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetHeight(186)
  createBackdrop(o.frame)

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.title:SetPoint("TOPLEFT", 10, -8)
  o.title:SetText("Condition Builder")

  o.ddLogic = CreateFrame("Frame", nil, o.frame, "UIDropDownMenuTemplate")
  o.ddLogic:SetPoint("TOPLEFT", -6, -22)
  UIDropDownMenu_SetWidth(o.ddLogic, 150)
  UIDropDownMenu_Initialize(o.ddLogic, function(_, level)
    if level ~= 1 then
      return
    end
    local function add(value, label)
      local info = UIDropDownMenu_CreateInfo()
      info.text = label
      info.func = function()
        o.draft.conditionLogic = value
        UIDropDownMenu_SetText(o.ddLogic, label)
        o:NotifyChanged()
      end
      UIDropDownMenu_AddButton(info, level)
    end
    add("all", "AND (all)")
    add("any", "OR (any)")
  end)

  local lblTal = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lblTal:SetPoint("TOPLEFT", 10, -54)
  lblTal:SetText("Talent SpellIDs (CSV)")

  o.editTalents = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editTalents:SetAutoFocus(false)
  o.editTalents:SetSize(240, 22)
  o.editTalents:SetPoint("TOPLEFT", 10, -70)
  o.editTalents:SetScript("OnTextChanged", function(edit)
    o.draft.talentSpellIDs = tostring(edit:GetText() or "")
    o:NotifyChanged()
  end)

  local lblAura = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  lblAura:SetPoint("TOPLEFT", 10, -96)
  lblAura:SetText("Required Aura SpellIDs (CSV)")

  o.editAuras = CreateFrame("EditBox", nil, o.frame, "InputBoxTemplate")
  o.editAuras:SetAutoFocus(false)
  o.editAuras:SetSize(240, 22)
  o.editAuras:SetPoint("TOPLEFT", 10, -112)
  o.editAuras:SetScript("OnTextChanged", function(edit)
    o.draft.requiredAuraSpellIDs = tostring(edit:GetText() or "")
    o:NotifyChanged()
  end)

  o.cbCombat = CreateFrame("CheckButton", nil, o.frame, "UICheckButtonTemplate")
  o.cbCombat:SetPoint("TOPLEFT", 260, -72)
  o.cbCombat:SetScript("OnClick", function(btn)
    o.draft.inCombatOnly = btn:GetChecked() == true
    o:NotifyChanged()
  end)

  o.cbCombatLabel = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.cbCombatLabel:SetPoint("LEFT", o.cbCombat, "RIGHT", 2, 0)
  o.cbCombatLabel:SetText("In combat only")

  o.summary = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.summary:SetPoint("TOPLEFT", 260, -100)
  o.summary:SetPoint("RIGHT", -10, 0)
  o.summary:SetJustifyH("LEFT")
  o.summary:SetText("IF AND <none>")

  return o
end

W.ConditionTreeWidget = ConditionTree
