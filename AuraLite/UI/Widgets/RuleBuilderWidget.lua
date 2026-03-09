local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets

local RuleBuilder = {}
RuleBuilder.__index = RuleBuilder

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.04, 0.08, 0.68)
  frame:SetBackdropBorderColor(0.1, 0.38, 0.66, 0.8)
end

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function narrative(draft)
  local cast = trim(draft.castSpellIDs)
  if cast == "" then
    cast = "?"
  end
  local cond = (tostring(draft.conditionLogic or "all") == "any") and "OR (any)" or "AND (all)"
  local thenText = (tostring(draft.actionMode or "produce") == "consume") and "Consume aura" or ("Show aura for " .. tostring(tonumber(draft.duration) or 8) .. "s")
  return string.format("WHEN Cast %s | IF %s | THEN %s", cast, cond, thenText)
end

function RuleBuilder:SetDraft(draft)
  self.draft = draft or {}
  if self.lblNarrative then
    self.lblNarrative:SetText(narrative(self.draft))
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
    if tonumber(self.draft.duration) == nil or tonumber(self.draft.duration) <= 0 then
      self.draft.duration = 8
    end
  elseif kind == "talent" then
    self.draft.actionMode = "produce"
    self.draft.triggerType = "cast"
    self.draft.conditionLogic = "all"
    self.draft.notes = trim(self.draft.notes) ~= "" and self.draft.notes or "Talent condition required"
    self.draft.duration = tonumber(self.draft.duration) or 8
  elseif kind == "consume" then
    self.draft.actionMode = "consume"
    self.draft.triggerType = "cast"
  end

  self:SetDraft(self.draft)
  if self.onChanged then
    self.onChanged(self.draft)
  end
end

function RuleBuilder:Create(parent, onChanged)
  local o = setmetatable({}, self)
  o.onChanged = onChanged
  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetHeight(112)
  createBackdrop(o.frame)

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.title:SetPoint("TOPLEFT", 10, -8)
  o.title:SetText("Rule Builder")

  o.lblNarrative = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.lblNarrative:SetPoint("TOPLEFT", 10, -30)
  o.lblNarrative:SetPoint("RIGHT", -10, 0)
  o.lblNarrative:SetJustifyH("LEFT")
  o.lblNarrative:SetText("WHEN Cast ? | IF AND (all) | THEN Show aura for 8s")

  o.btnShow = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnShow:SetSize(92, 20)
  o.btnShow:SetPoint("TOPLEFT", 10, -56)
  o.btnShow:SetText("Show Aura")
  o.btnShow:SetScript("OnClick", function()
    o:ApplyPreset("show")
  end)

  o.btnTalent = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnTalent:SetSize(108, 20)
  o.btnTalent:SetPoint("LEFT", o.btnShow, "RIGHT", 8, 0)
  o.btnTalent:SetText("Show+Talent")
  o.btnTalent:SetScript("OnClick", function()
    o:ApplyPreset("talent")
  end)

  o.btnConsume = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnConsume:SetSize(108, 20)
  o.btnConsume:SetPoint("LEFT", o.btnTalent, "RIGHT", 8, 0)
  o.btnConsume:SetText("Consume")
  o.btnConsume:SetScript("OnClick", function()
    o:ApplyPreset("consume")
  end)

  return o
end

W.RuleBuilderWidget = RuleBuilder
