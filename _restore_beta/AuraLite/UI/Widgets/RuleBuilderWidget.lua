local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local E = UI.Events
local Skin = ns.UISkin

local RuleBuilder = {}
RuleBuilder.__index = RuleBuilder

local function createBackdrop(frame)
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
  frame:SetBackdropColor(0.03, 0.08, 0.16, 0.72)
  frame:SetBackdropBorderColor(0.18, 0.28, 0.40, 0.72)
end

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function hasExtraConditions(draft)
  draft = draft or {}
  if trim(draft.talentSpellIDs) ~= "" then
    return true
  end
  if trim(draft.requiredAuraSpellIDs) ~= "" then
    return true
  end
  if draft.inCombatOnly == true then
    return true
  end
  return false
end

local function resolveSpellName(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return nil
  end
  if ns.AuraAPI and ns.AuraAPI.GetSpellName then
    local name = ns.AuraAPI:GetSpellName(spellID)
    if type(name) == "string" and name ~= "" then
      return name
    end
  end
  return nil
end

local function spellListLabel(csv)
  local parts = {}
  local seen = {}
  for token in trim(csv):gmatch("[^,%s;]+") do
    local spellID = tonumber(token)
    if spellID and spellID > 0 and not seen[spellID] then
      seen[spellID] = true
      parts[#parts + 1] = resolveSpellName(spellID) or ("Spell " .. tostring(spellID))
    end
  end
  if #parts == 0 then
    return "No trigger spell"
  end
  return table.concat(parts, ", ")
end

local function auraLabel(spellID)
  local sid = tonumber(spellID)
  if not sid or sid <= 0 then
    return "No aura selected"
  end
  return resolveSpellName(sid) or ("Aura " .. tostring(sid))
end

local function ruleNarrative(draft)
  local cast = spellListLabel(draft.castSpellIDs)
  local mode = tostring(draft.actionMode or "produce")
  local auraName = auraLabel(draft.spellID)
  local thenText = mode == "consume" and ("Consume " .. auraName) or ("Show " .. auraName)
  if hasExtraConditions(draft) then
    local cond = (tostring(draft.conditionLogic or "all") == "any") and "OR" or "AND"
    return string.format("WHEN %s  |  IF %s conditions  |  THEN %s", cast, cond, thenText)
  end
  return string.format("WHEN %s  |  THEN %s", cast, thenText)
end

function RuleBuilder:SetDraft(draft)
  self.draft = draft or {}
  local showIf = hasExtraConditions(self.draft)
  if self.whenValue then
    self.whenValue:SetText(spellListLabel(self.draft.castSpellIDs))
  end
  if self.ifBox and self.ifValue then
    self.ifValue:SetText((tostring(self.draft.conditionLogic or "all") == "any") and "OR (any)" or "AND (all)")
    self.ifBox:SetShown(showIf)
  end
  if self.thenValue then
    local auraName = auraLabel(self.draft.spellID)
    local text = (tostring(self.draft.actionMode or "produce") == "consume") and ("Consume " .. auraName) or ("Show " .. auraName)
    self.thenValue:SetText(text)
  end
  if self.whenBox and self.thenBox then
    self.whenBox:ClearAllPoints()
    self.thenBox:ClearAllPoints()
    self.whenBox:SetPoint("TOPLEFT", 10, -52)
    self.whenBox:SetWidth(showIf and 240 or 320)
    if showIf and self.ifBox then
      self.ifBox:ClearAllPoints()
      self.ifBox:SetPoint("TOPLEFT", 260, -52)
      self.thenBox:SetPoint("TOPLEFT", 440, -52)
      self.thenBox:SetWidth(200)
    else
      self.thenBox:SetPoint("TOPLEFT", 340, -52)
      self.thenBox:SetWidth(300)
    end
  end
  if self.narrative then
    self.narrative:SetText(ruleNarrative(self.draft))
  end
end

function RuleBuilder:Create(parent, onChanged)
  local o = setmetatable({}, self)
  o.onChanged = onChanged
  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetHeight(118)
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
    return box, val
  end

  o.whenBox, o.whenValue = buildColumn("WHEN", 10)
  o.ifBox, o.ifValue = buildColumn("IF", 190)
  o.thenBox, o.thenValue = buildColumn("THEN", 370)

  return o
end

W.RuleBuilderWidget = RuleBuilder
