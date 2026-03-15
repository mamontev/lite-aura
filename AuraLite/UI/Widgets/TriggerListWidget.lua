local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local Skin = ns.UISkin
local FieldFactory = UI.FieldFactory

local TriggerList = {}
TriggerList.__index = TriggerList

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

local function getSpellRowPreview(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return 134400, "Choose a spell"
  end

  local icon = (ns.AuraAPI and ns.AuraAPI.GetSpellTexture and ns.AuraAPI:GetSpellTexture(spellID)) or 134400
  local name = (ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID)) or ("Spell " .. tostring(spellID))
  return icon, name
end

local function getSpellCastTimeMS(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return 0
  end

  if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local ok, info = pcall(C_Spell.GetSpellInfo, spellID)
    if ok and type(info) == "table" then
      return math.max(0, tonumber(info.castTime) or 0)
    end
  end

  if GetSpellInfo then
    local _, _, _, castTime = GetSpellInfo(spellID)
    return math.max(0, tonumber(castTime) or 0)
  end

  return 0
end

local function getTriggerTimingLabel(spellID)
  local castTime = getSpellCastTimeMS(spellID)
  if castTime > 0 then
    return "After the cast finishes"
  end
  return "On successful cast"
end

local function normalizeProduceTriggers(draft)
  if UI and UI.Bindings and UI.Bindings.GetProduceTriggers then
    return UI.Bindings:GetProduceTriggers(draft)
  end
  return {}
end

local function syncProduceTriggersToDraft(draft)
  if not draft then
    return
  end
  normalizeProduceTriggers(draft)
end

function TriggerList:Commit()
  if not self.draft then
    return
  end

  local triggers = {}
  for i = 1, #(self.rowWidgets or {}) do
    local row = self.rowWidgets[i]
    if row then
      local spellText = row.spellBox and row.spellBox.GetText and row.spellBox:GetText() or ""
      local amountText = row.amountBox and row.amountBox.GetText and row.amountBox:GetText() or ""
      triggers[#triggers + 1] = {
        spellID = tonumber(spellText) or 0,
        stackAmount = math.max(1, tonumber(amountText) or tonumber(self.draft.stackAmount) or 1),
      }
    end
  end

  self.draft.produceTriggers = triggers
  syncProduceTriggersToDraft(self.draft)
end

function TriggerList:ClearRows()
  for i = 1, #(self.widgets or {}) do
    local widget = self.widgets[i]
    if widget then
      widget:Hide()
      widget:SetParent(nil)
    end
  end
  self.widgets = {}
  self.rowWidgets = {}
end

function TriggerList:Render()
  self:ClearRows()
  if not self.frame or not self.draft then
    return
  end

  local triggers = normalizeProduceTriggers(self.draft)
  if #triggers == 0 then
    triggers[1] = {
      spellID = 0,
      stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1),
    }
    self.draft.produceTriggers = triggers
    syncProduceTriggersToDraft(self.draft)
  end

  local stackable = self.isStackable and self.isStackable(self.draft) or false
  self.title:SetText("Produce Triggers")
  self.desc:SetText(stackable and "Add one row for each spell that grants this aura. Each spell can give a different number of charges." or "Add the spells that should show or refresh this aura.")
  local invalidCount = 0

  local rowHeight = stackable and 108 or 86
  local contentY = -2

  local function markTriggerChanged()
    self.draft._produceTriggersDirty = true
    syncProduceTriggersToDraft(self.draft)
    if self.onChanged then
      self.onChanged()
    end
  end

  for i = 1, #triggers do
    local row = triggers[i]

    local rowFrame = CreateFrame("Frame", nil, self.content)
    rowFrame:SetPoint("TOPLEFT", 2, contentY)
    rowFrame:SetPoint("RIGHT", -2, 0)
    rowFrame:SetHeight(rowHeight)
    self.widgets[#self.widgets + 1] = rowFrame

    local spellLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", 0, 0)
    spellLabel:SetText((#triggers > 1) and string.format("Trigger %d", i) or "Trigger")
    self.widgets[#self.widgets + 1] = spellLabel

    local iconTexture = rowFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetSize(18, 18)
    iconTexture:SetPoint("TOPLEFT", 0, -18)
    self.widgets[#self.widgets + 1] = iconTexture

    local spellBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
    spellBox:SetAutoFocus(false)
    spellBox:SetSize(120, 24)
    spellBox:SetPoint("TOPLEFT", 22, -16)
    spellBox:SetText((tonumber(row.spellID) and tonumber(row.spellID) > 0) and tostring(row.spellID) or "")
    self.widgets[#self.widgets + 1] = spellBox

    local spellNameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellNameText:SetPoint("TOPLEFT", spellBox, "TOPRIGHT", 10, -2)
    spellNameText:SetPoint("RIGHT", -34, 0)
    spellNameText:SetJustifyH("LEFT")
    self.widgets[#self.widgets + 1] = spellNameText

    local timingText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timingText:SetPoint("TOPLEFT", 22, -44)
    timingText:SetPoint("RIGHT", -34, 0)
    timingText:SetJustifyH("LEFT")
    self.widgets[#self.widgets + 1] = timingText

    local summaryText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryText:SetPoint("TOPLEFT", 22, -60)
    summaryText:SetPoint("RIGHT", -34, 0)
    summaryText:SetJustifyH("LEFT")
    self.widgets[#self.widgets + 1] = summaryText

    local function refreshRowPreview()
      local icon, name = getSpellRowPreview(row.spellID)
      iconTexture:SetTexture(icon)
      spellNameText:SetText(name)
      if tonumber(row.spellID) and tonumber(row.spellID) > 0 and name ~= ("Spell " .. tostring(tonumber(row.spellID))) then
        spellNameText:SetTextColor(0.92, 0.95, 1.0)
      elseif tonumber(row.spellID) and tonumber(row.spellID) > 0 then
        spellNameText:SetTextColor(1.0, 0.35, 0.35)
        invalidCount = invalidCount + 1
      else
        spellNameText:SetTextColor(0.62, 0.68, 0.76)
      end
      if tonumber(row.spellID) and tonumber(row.spellID) > 0 then
        timingText:SetText(getTriggerTimingLabel(row.spellID))
      else
        timingText:SetText("Enter a SpellID or shift-click a spell.")
      end
      if stackable then
        local amount = math.max(1, tonumber(row.stackAmount) or 1)
        summaryText:SetText(string.format("%s gives %d charge(s)", name, amount))
      else
        summaryText:SetText(string.format("%s shows or refreshes this aura", name))
      end
    end

    spellBox:SetScript("OnTextChanged", function(_, userInput)
      if not userInput then
        return
      end
      row.spellID = tonumber(spellBox:GetText()) or 0
      markTriggerChanged()
      refreshRowPreview()
    end)

    if FieldFactory and FieldFactory.AttachSpellResolver then
      FieldFactory.AttachSpellResolver(rowFrame, spellBox, { key = "produceTriggerSpell", widget = "spellid" }, function(_, value)
        row.spellID = tonumber(value) or 0
        markTriggerChanged()
        refreshRowPreview()
      end)
    end

    local amountBox = nil
    if stackable then
      local amountLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      amountLabel:SetPoint("TOPLEFT", 252, 0)
      amountLabel:SetText("Gives")
      self.widgets[#self.widgets + 1] = amountLabel

      amountBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
      amountBox:SetAutoFocus(false)
      amountBox:SetNumeric(true)
      amountBox:SetMaxLetters(2)
      amountBox:SetSize(48, 24)
      amountBox:SetPoint("TOPLEFT", 252, -16)
      amountBox:SetText(tostring(math.max(1, tonumber(row.stackAmount) or 1)))
      amountBox:SetScript("OnTextChanged", function(_, userInput)
        if not userInput then
          return
        end
        row.stackAmount = math.max(1, tonumber(amountBox:GetText()) or 1)
        self.draft.stackAmount = tonumber(row.stackAmount) or self.draft.stackAmount
        markTriggerChanged()
        refreshRowPreview()
      end)
      self.widgets[#self.widgets + 1] = amountBox

      local amountHint = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      amountHint:SetPoint("LEFT", amountBox, "RIGHT", 6, 0)
      amountHint:SetText("charge(s)")
      self.widgets[#self.widgets + 1] = amountHint
    end

    local removeBtn = CreateFrame("Button", nil, rowFrame, "UIPanelButtonTemplate")
    removeBtn:SetSize(24, 20)
    removeBtn:SetPoint("TOPRIGHT", -2, -18)
    removeBtn:SetText("x")
    removeBtn:SetEnabled(#triggers > 1)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(removeBtn, "ghost")
    end
    removeBtn:SetScript("OnClick", function()
      table.remove(triggers, i)
      if #triggers == 0 then
        triggers[1] = {
          spellID = 0,
          stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1),
        }
      end
      self.draft.produceTriggers = triggers
      self.draft._produceTriggersDirty = true
      if self.onRequestRender then
        self.onRequestRender()
      end
    end)
    self.widgets[#self.widgets + 1] = removeBtn

    self.rowWidgets[#self.rowWidgets + 1] = {
      spellBox = spellBox,
      amountBox = amountBox,
    }

    refreshRowPreview()
    if self.pendingFocusIndex == i then
      spellBox:SetFocus()
      spellBox:HighlightText()
      self.pendingFocusIndex = nil
    end
    contentY = contentY - rowHeight
  end

  local addBtn = CreateFrame("Button", nil, self.content, "UIPanelButtonTemplate")
  addBtn:SetSize(136, 22)
  addBtn:SetPoint("TOPLEFT", 2, contentY + 4)
  addBtn:SetText((#triggers > 0) and "+ Add Another Trigger" or "+ Add Trigger")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(addBtn, "segment")
  end
  addBtn:SetScript("OnClick", function()
    triggers[#triggers + 1] = {
      spellID = 0,
      stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1),
    }
    self.pendingFocusIndex = #triggers
    self.draft.produceTriggers = triggers
    self.draft._produceTriggersDirty = true
    syncProduceTriggersToDraft(self.draft)
    if self.onChanged then
      self.onChanged()
    end
    if self.onRequestRender then
      self.onRequestRender()
    end
  end)
  self.widgets[#self.widgets + 1] = addBtn

  self.content:SetHeight((-contentY) + 30)
  self.frame:SetHeight(math.max(118, (-contentY) + 86))
  if invalidCount > 0 then
    self.desc:SetText(string.format("One or more trigger SpellIDs could not be resolved. Check the red rows before saving. (%d)", invalidCount))
    self.desc:SetTextColor(1.0, 0.50, 0.50)
  else
    if stackable then
      self.desc:SetText("Add one row per spell that grants this aura. Cast-time spells trigger after the cast finishes; instant spells trigger on successful cast.")
    else
      self.desc:SetText("Add the spells that should show or refresh this aura. Cast-time spells trigger after the cast finishes.")
    end
    self.desc:SetTextColor(0.62, 0.68, 0.76)
  end
end

function TriggerList:SetDraft(draft)
  self.draft = draft or {}
  self:Render()
end

function TriggerList:Create(parent, opts)
  local o = setmetatable({}, self)
  opts = opts or {}
  o.onChanged = opts.onChanged
  o.onRequestRender = opts.onRequestRender
  o.isStackable = opts.isStackable
  o.widgets = {}
  o.rowWidgets = {}

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createCardBackdrop(o.frame)

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.title:SetPoint("TOPLEFT", 12, -10)
  o.title:SetText("Produce Triggers")

  o.desc = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.desc:SetPoint("TOPLEFT", 12, -28)
  o.desc:SetPoint("RIGHT", -12, 0)
  o.desc:SetJustifyH("LEFT")
  o.desc:SetText("")

  o.content = CreateFrame("Frame", nil, o.frame)
  o.content:SetPoint("TOPLEFT", 10, -46)
  o.content:SetPoint("TOPRIGHT", -10, -46)
  o.content:SetHeight(24)

  return o
end

W.TriggerListWidget = TriggerList
