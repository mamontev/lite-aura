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

local function produceTriggerLabel(draft)
  draft = draft or {}
  local triggers = draft.produceTriggers
  if type(triggers) ~= "table" or #triggers == 0 then
    return spellListLabel(draft.castSpellIDs)
  end

  local parts = {}
  for i = 1, #triggers do
    local row = triggers[i]
    local spellID = tonumber(type(row) == "table" and row.spellID or row)
    if spellID and spellID > 0 then
      local name = resolveSpellName(spellID) or ("Spell " .. tostring(spellID))
      local amount = math.max(1, tonumber(type(row) == "table" and row.stackAmount or 1) or 1)
      if (tonumber(draft.maxStacks) or 1) > 1 or tostring(draft.stackBehavior or "replace") == "add" then
        if amount == 1 then
          parts[#parts + 1] = string.format("%s gives 1 charge", name)
        else
          parts[#parts + 1] = string.format("%s gives %d charges", name, amount)
        end
      elseif tostring(draft.timerBehavior or "reset") == "extend" then
        parts[#parts + 1] = string.format("%s refreshes the timer", name)
      else
        parts[#parts + 1] = string.format("%s gives the aura", name)
      end
    end
  end

  if #parts == 0 then
    return spellListLabel(draft.castSpellIDs)
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
  local mode = tostring(draft.actionMode or "produce")
  local cast = (mode == "consume") and spellListLabel(draft.consumeCastSpellIDs or draft.castSpellIDs) or produceTriggerLabel(draft)
  local auraName = auraLabel(draft.spellID)
  local thenText
  if mode == "consume" then
    thenText = ((tostring(draft.consumeBehavior or "hide") == "decrement") and ("spend one charge from " .. auraName) or ("consume " .. auraName))
  else
    thenText = ("show " .. auraName)
  end
  if hasExtraConditions(draft) then
    local cond = (tostring(draft.conditionLogic or "all") == "any") and "any" or "all"
    return string.format("When %s, if %s extra conditions pass, %s.", cast, cond, thenText)
  end
  return string.format("When %s, %s.", cast, thenText)
end

function RuleBuilder:SetDraft(draft)
  self.draft = draft or {}
  local showIf = hasExtraConditions(self.draft)
  if self.whenValue then
    local mode = tostring(self.draft.actionMode or "produce")
    self.whenValue:SetText((mode == "consume") and spellListLabel(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs) or produceTriggerLabel(self.draft))
  end
  if self.ifBox and self.ifValue then
    self.ifValue:SetText((tostring(self.draft.conditionLogic or "all") == "any") and "Any condition can pass" or "All conditions must pass")
    self.ifBox:SetShown(showIf)
  end
  if self.thenValue then
    local auraName = auraLabel(self.draft.spellID)
    local text = (tostring(self.draft.actionMode or "produce") == "consume")
      and (((tostring(self.draft.consumeBehavior or "hide") == "decrement") and "Spend 1 Charge") or "Consume Aura")
      or ("Show " .. auraName)
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
  o.title:SetText("How This Aura Works")

  o.narrative = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.narrative:SetPoint("TOPLEFT", 10, -28)
  o.narrative:SetPoint("RIGHT", -10, 0)
  o.narrative:SetJustifyH("LEFT")
  o.narrative:SetText("When one of your chosen spells happens, AuraLite decides whether to show or spend this aura.")

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

  o.whenBox, o.whenValue = buildColumn("When This Happens", 10)
  o.ifBox, o.ifValue = buildColumn("Only If", 190)
  o.thenBox, o.thenValue = buildColumn("Aura Will", 370)

  return o
end

W.RuleBuilderWidget = RuleBuilder
