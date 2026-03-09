local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local E = UI.Events

local RuleBuilder = {}
RuleBuilder.__index = RuleBuilder

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.06, 0.14, 0.70)
  frame:SetBackdropBorderColor(0.12, 0.52, 0.82, 0.86)
end

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function ruleNarrative(draft)
  local cast = trim(draft.castSpellIDs)
  if cast == "" then
    cast = "?"
  end
  local cond = (tostring(draft.conditionLogic or "all") == "any") and "OR" or "AND"
  local mode = tostring(draft.actionMode or "produce")
  local thenText = mode == "consume" and "Consume aura" or ("Show aura for " .. tostring(tonumber(draft.duration) or 8) .. "s")
  return string.format("WHEN cast %s  |  IF %s conditions  |  THEN %s", cast, cond, thenText)
end

function RuleBuilder:SetDraft(draft)
  self.draft = draft or {}
  if self.whenValue then
    self.whenValue:SetText((trim(self.draft.castSpellIDs) ~= "") and trim(self.draft.castSpellIDs) or "?")
  end
  if self.ifValue then
    self.ifValue:SetText((tostring(self.draft.conditionLogic or "all") == "any") and "OR (any)" or "AND (all)")
  end
  if self.thenValue then
    local text = (tostring(self.draft.actionMode or "produce") == "consume") and "Consume Aura" or "Produce Aura"
    self.thenValue:SetText(text)
  end
  if self.narrative then
    self.narrative:SetText(ruleNarrative(self.draft))
  end
end

function RuleBuilder:ApplyPreset(kind)
  if not self.draft then
    return
  end

  if kind == "show" then
    self.draft.actionMode = "produce"
    self.draft.triggerType = "cast"
    self.draft.conditionLogic = "all"
    self.draft.duration = tonumber(self.draft.duration) or 8
  elseif kind == "talent" then
    self.draft.actionMode = "produce"
    self.draft.triggerType = "cast"
    self.draft.conditionLogic = "all"
    if trim(self.draft.talentSpellIDs) == "" and tonumber(self.draft.spellID) then
      self.draft.talentSpellIDs = tostring(tonumber(self.draft.spellID))
    end
    self.draft.duration = tonumber(self.draft.duration) or 8
  elseif kind == "consume" then
    self.draft.actionMode = "consume"
    self.draft.triggerType = "cast"
    if trim(self.draft.requiredAuraSpellIDs) == "" and tonumber(self.draft.spellID) then
      self.draft.requiredAuraSpellIDs = tostring(tonumber(self.draft.spellID))
    end
  end

  self:SetDraft(self.draft)
  if self.onChanged then
    self.onChanged(self.draft)
  end
end

function RuleBuilder:EmitSimulation(simType)
  if not E then
    return
  end
  E:Emit(E.Names.SIMULATE_TRIGGER, {
    kind = simType,
    draft = self.draft,
    duration = tonumber(self.draft and self.draft.duration) or 8,
  })
end

function RuleBuilder:Create(parent, onChanged)
  local o = setmetatable({}, self)
  o.onChanged = onChanged
  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetHeight(174)
  createBackdrop(o.frame)

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.title:SetPoint("TOPLEFT", 10, -8)
  o.title:SetText("Rule Builder")

  o.narrative = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.narrative:SetPoint("TOPLEFT", 10, -28)
  o.narrative:SetPoint("RIGHT", -10, 0)
  o.narrative:SetJustifyH("LEFT")
  o.narrative:SetText("WHEN cast ?  |  IF AND conditions  |  THEN Produce Aura")

  local function buildColumn(label, x)
    local box = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
    box:SetSize(170, 52)
    box:SetPoint("TOPLEFT", x, -52)
    createBackdrop(box)

    local lbl = box:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    lbl:SetPoint("TOPLEFT", 8, -7)
    lbl:SetText(label)

    local val = box:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    val:SetPoint("TOPLEFT", 8, -24)
    val:SetPoint("RIGHT", -8, 0)
    val:SetJustifyH("LEFT")
    val:SetText("-")
    return val
  end

  o.whenValue = buildColumn("WHEN", 10)
  o.ifValue = buildColumn("IF", 190)
  o.thenValue = buildColumn("THEN", 370)

  o.btnShow = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnShow:SetSize(98, 20)
  o.btnShow:SetPoint("TOPLEFT", 10, -116)
  o.btnShow:SetText("Show Aura")
  o.btnShow:SetScript("OnClick", function()
    o:ApplyPreset("show")
  end)

  o.btnTalent = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnTalent:SetSize(112, 20)
  o.btnTalent:SetPoint("LEFT", o.btnShow, "RIGHT", 6, 0)
  o.btnTalent:SetText("Show + Talent")
  o.btnTalent:SetScript("OnClick", function()
    o:ApplyPreset("talent")
  end)

  o.btnConsume = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnConsume:SetSize(112, 20)
  o.btnConsume:SetPoint("LEFT", o.btnTalent, "RIGHT", 6, 0)
  o.btnConsume:SetText("Consume")
  o.btnConsume:SetScript("OnClick", function()
    o:ApplyPreset("consume")
  end)

  o.btnSimShow = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSimShow:SetSize(92, 20)
  o.btnSimShow:SetPoint("TOPLEFT", 10, -142)
  o.btnSimShow:SetText("Sim Show")
  o.btnSimShow:SetScript("OnClick", function()
    o:EmitSimulation("show")
  end)

  o.btnSimConsume = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSimConsume:SetSize(110, 20)
  o.btnSimConsume:SetPoint("LEFT", o.btnSimShow, "RIGHT", 6, 0)
  o.btnSimConsume:SetText("Sim Consume")
  o.btnSimConsume:SetScript("OnClick", function()
    o:EmitSimulation("consume")
  end)

  return o
end

W.RuleBuilderWidget = RuleBuilder
