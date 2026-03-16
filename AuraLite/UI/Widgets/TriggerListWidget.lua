local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local Skin = ns.UISkin
local FieldFactory = UI.FieldFactory
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local WIDGET_TYPE = "AuraLiteTriggerList"
local WIDGET_VERSION = 1

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
  frame:SetBackdropColor(0.09, 0.10, 0.12, 0.28)
  frame:SetBackdropBorderColor(0.22, 0.24, 0.28, 0.24)
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

local function getTriggerBehaviorLabel(draft, row, stackable)
  local amount = math.max(1, tonumber(row and row.stackAmount) or 1)
  local timerBehavior = tostring(draft and draft.timerBehavior or "reset")
  if stackable then
    if amount == 1 then
      return "This spell gives 1 charge."
    end
    return string.format("This spell gives %d charges.", amount)
  end
  if timerBehavior == "extend" then
    return "This spell refreshes and extends the timer."
  end
  if timerBehavior == "keep" then
    return "This spell refreshes the aura without shortening it."
  end
  return "This spell gives or refreshes the aura."
end

local function resolveTypedSpellID(text)
  if not FieldFactory or not FieldFactory.ResolveSpellInput then
    return tonumber(text) or 0
  end
  local normalized, _, ok = FieldFactory.ResolveSpellInput(text, { widget = "spellid" })
  if ok then
    return tonumber(normalized) or 0
  end
  return tonumber(text) or 0
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

local function getCursorPayloadSpellID()
  local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
  if cursorType == "spell" and cursorSpellID then
    return tonumber(cursorSpellID)
  end
  if cursorType == "petaction" and cursorID then
    return tonumber(cursorID)
  end
  if cursorType == "item" and cursorID and C_Item and C_Item.GetItemSpell then
    local _, itemSpellID = C_Item.GetItemSpell(cursorID)
    return tonumber(itemSpellID)
  end
  return nil
end

local function setTriggerFromCursor(row, callback)
  local spellID = getCursorPayloadSpellID()
  if not spellID or spellID <= 0 or not row then
    return false
  end
  row.spellID = spellID
  if type(callback) == "function" then
    callback(spellID)
  end
  ClearCursor()
  return true
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

  local rowHeight = stackable and 82 or 74
  local contentY = -2

  local function markTriggerChanged()
    self.draft._produceTriggersDirty = true
    syncProduceTriggersToDraft(self.draft)
    if self.onChanged then
      self.onChanged()
    end
  end

  local dropState = "normal"
  local function setDropZoneState(state)
    if not self.dropZone then
      return
    end
    dropState = state or "normal"
    if dropState == "armed" then
      self.dropZone.bg:SetColorTexture(0.15, 0.22, 0.30, 0.82)
      self.dropZone.border:SetColorTexture(0.44, 0.74, 0.98, 0.92)
      self.dropZone.accent:SetColorTexture(1.0, 0.82, 0.18, 0.72)
    elseif dropState == "hover" then
      self.dropZone.bg:SetColorTexture(0.11, 0.14, 0.18, 0.68)
      self.dropZone.border:SetColorTexture(0.26, 0.30, 0.36, 0.70)
      self.dropZone.accent:SetColorTexture(1.0, 0.82, 0.18, 0.18)
    else
      self.dropZone.bg:SetColorTexture(0.08, 0.09, 0.11, 0.52)
      self.dropZone.border:SetColorTexture(0.18, 0.20, 0.24, 0.56)
      self.dropZone.accent:SetColorTexture(1.0, 0.82, 0.18, 0.08)
    end
  end

  local function addTriggerFromSpellID(spellID)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 then
      return
    end
    triggers[#triggers + 1] = {
      spellID = spellID,
      stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1),
    }
    self.pendingFocusIndex = nil
    self.draft.produceTriggers = triggers
    self.draft._produceTriggersDirty = true
    syncProduceTriggersToDraft(self.draft)
    if self.onChanged then
      self.onChanged()
    end
    if self.onRequestRender then
      self.onRequestRender()
    end
  end

  if self.dropZone then
    self.dropZone:ClearAllPoints()
    self.dropZone:SetPoint("TOPLEFT", 12, contentY)
    self.dropZone:SetPoint("RIGHT", -12, 0)
    self.dropZone:SetHeight(42)
    self.dropZone:Show()
    contentY = contentY - 48
  end

  for i = 1, #triggers do
    local row = triggers[i]

    local rowFrame = CreateFrame("Button", nil, self.content, "BackdropTemplate")
    rowFrame:SetPoint("TOPLEFT", 12, contentY)
    rowFrame:SetPoint("RIGHT", -12, 0)
    rowFrame:SetHeight(rowHeight)
    rowFrame:RegisterForDrag("LeftButton")
    rowFrame:EnableMouse(true)
    createCardBackdrop(rowFrame)
    if Skin and Skin.ApplyClickableRow then
      Skin:ApplyClickableRow(rowFrame, "row")
      if Skin.SetClickableRowState then
        Skin:SetClickableRowState(rowFrame, "normal")
      end
    end
    self.widgets[#self.widgets + 1] = rowFrame

    local spellLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    spellLabel:SetPoint("TOPLEFT", 14, -6)
    spellLabel:SetText((#triggers > 1) and string.format("Spell %d", i) or "Spell")
    self.widgets[#self.widgets + 1] = spellLabel

    local iconTexture = rowFrame:CreateTexture(nil, "ARTWORK")
    iconTexture:SetSize(18, 18)
    iconTexture:SetPoint("TOPLEFT", 14, -24)
    self.widgets[#self.widgets + 1] = iconTexture

    local spellBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
    spellBox:SetAutoFocus(false)
    spellBox:SetSize(96, 22)
    spellBox:SetPoint("TOPLEFT", 36, -24)
    spellBox:SetText((tonumber(row.spellID) and tonumber(row.spellID) > 0) and tostring(row.spellID) or "")
    if Skin and Skin.ApplyEditBox then
      Skin:ApplyEditBox(spellBox)
    end
    self.widgets[#self.widgets + 1] = spellBox

    local spellNameText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    spellNameText:SetPoint("TOPLEFT", spellBox, "TOPRIGHT", 10, -1)
    spellNameText:SetPoint("RIGHT", stackable and -192 or -42, 0)
    spellNameText:SetJustifyH("LEFT")
    spellNameText:SetWordWrap(false)
    self.widgets[#self.widgets + 1] = spellNameText

    local timingText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    timingText:SetPoint("TOPLEFT", spellNameText, "BOTTOMLEFT", 0, -4)
    timingText:SetPoint("RIGHT", stackable and -192 or -42, 0)
    timingText:SetJustifyH("LEFT")
    timingText:SetTextColor(0.66, 0.70, 0.76)
    timingText:SetWordWrap(false)
    self.widgets[#self.widgets + 1] = timingText

    local summaryText = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    summaryText:SetPoint("TOPLEFT", 36, -58)
    summaryText:SetPoint("RIGHT", stackable and -192 or -42, 0)
    summaryText:SetJustifyH("LEFT")
    summaryText:SetWordWrap(false)
    summaryText:SetTextColor(0.54, 0.59, 0.66)
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
      summaryText:SetText(getTriggerBehaviorLabel(self.draft, row, stackable))
    end

    spellBox:SetScript("OnTextChanged", function(_, userInput)
      if not userInput then
        return
      end
      row.spellID = tonumber(spellBox:GetText()) or 0
      markTriggerChanged()
      refreshRowPreview()
    end)
    spellBox:SetScript("OnEnterPressed", function(edit)
      local resolved = resolveTypedSpellID(edit:GetText())
      row.spellID = resolved
      edit:SetText((resolved and resolved > 0) and tostring(resolved) or "")
      markTriggerChanged()
      refreshRowPreview()
      edit:ClearFocus()
    end)
    spellBox:SetScript("OnEditFocusLost", function(edit)
      local resolved = resolveTypedSpellID(edit:GetText())
      row.spellID = resolved
      edit:SetText((resolved and resolved > 0) and tostring(resolved) or "")
      markTriggerChanged()
      refreshRowPreview()
    end)

    rowFrame:SetScript("OnReceiveDrag", function()
      if setTriggerFromCursor(row, function(nextSpellID)
        spellBox:SetText(tostring(nextSpellID))
        markTriggerChanged()
        refreshRowPreview()
      end) then
        setDropZoneState("normal")
      end
    end)
    rowFrame:SetScript("OnMouseUp", function()
      if setTriggerFromCursor(row, function(nextSpellID)
        spellBox:SetText(tostring(nextSpellID))
        markTriggerChanged()
        refreshRowPreview()
      end) then
        setDropZoneState("normal")
      end
    end)

    local amountBox = nil
    if stackable then
      local amountLabel = rowFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      amountLabel:SetPoint("TOPLEFT", 318, -6)
      amountLabel:SetText("Gives")
      self.widgets[#self.widgets + 1] = amountLabel

      amountBox = CreateFrame("EditBox", nil, rowFrame, "InputBoxTemplate")
      amountBox:SetAutoFocus(false)
      amountBox:SetNumeric(true)
      amountBox:SetMaxLetters(2)
      amountBox:SetSize(46, 20)
      amountBox:SetPoint("TOPLEFT", rowFrame, "TOPRIGHT", -154, -24)
      amountBox:SetText(tostring(math.max(1, tonumber(row.stackAmount) or 1)))
      if Skin and Skin.ApplyEditBox then
        Skin:ApplyEditBox(amountBox)
      end
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
    removeBtn:SetSize(22, 18)
    removeBtn:SetPoint("TOPRIGHT", -8, -12)
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
    contentY = contentY - rowHeight - 6
  end

  local addBtn = CreateFrame("Button", nil, self.content, "UIPanelButtonTemplate")
  addBtn:SetSize(182, 20)
  addBtn:SetPoint("TOPLEFT", 12, contentY + 2)
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

  self.content:SetHeight((-contentY) + 22)
  self.frame:SetHeight(math.max(84, (-contentY) + 62))
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

  if self.dropZone then
    self.dropZone.label:SetText((#triggers > 0) and "Drop a spell here to append another trigger" or "Drop a spell here to create the first trigger")
    self.dropZone.hint:SetText("Drag from spellbook, action bar, or an item that resolves to a spell.")
    self.dropZone:SetScript("OnEnter", function()
      setDropZoneState(getCursorPayloadSpellID() and "armed" or "hover")
    end)
    self.dropZone:SetScript("OnLeave", function()
      setDropZoneState("normal")
    end)
    self.dropZone:SetScript("OnReceiveDrag", function()
      local spellID = getCursorPayloadSpellID()
      if spellID then
        addTriggerFromSpellID(spellID)
        ClearCursor()
      end
      setDropZoneState("normal")
    end)
    self.dropZone:SetScript("OnMouseUp", function()
      local spellID = getCursorPayloadSpellID()
      if spellID then
        addTriggerFromSpellID(spellID)
        ClearCursor()
      end
      setDropZoneState("normal")
    end)
    setDropZoneState("normal")
  end
end

function TriggerList:SetDraft(draft)
  self.draft = draft or {}
  self:Render()
end

local function buildTriggerListShell(o, parent, opts)
  opts = opts or {}
  o.onChanged = opts.onChanged
  o.onRequestRender = opts.onRequestRender
  o.isStackable = opts.isStackable
  o.embedded = opts.embedded == true
  o.widgets = {}
  o.rowWidgets = {}

  o.frame = CreateFrame("Frame", nil, parent or UIParent, "BackdropTemplate")
  if not o.embedded then
    createCardBackdrop(o.frame)
  end

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  o.title:SetPoint("TOPLEFT", 12, -10)
  o.title:SetText("Produce Triggers")
  o.title:SetTextColor(1.0, 0.86, 0.18)

  o.desc = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.desc:SetPoint("TOPLEFT", 12, -24)
  o.desc:SetPoint("RIGHT", -12, 0)
  o.desc:SetJustifyH("LEFT")
  o.desc:SetText("")

  o.content = CreateFrame("Frame", nil, o.frame)
  o.content:SetPoint("TOPLEFT", 0, o.embedded and 0 or -36)
  o.content:SetPoint("TOPRIGHT", 0, o.embedded and 0 or -36)
  o.content:SetHeight(24)

  if o.embedded then
    o.title:Hide()
    o.desc:Hide()
  end

  o.dropZone = CreateFrame("Button", nil, o.content, "BackdropTemplate")
  o.dropZone:RegisterForDrag("LeftButton")
  o.dropZone:EnableMouse(true)

  o.dropZone.bg = o.dropZone:CreateTexture(nil, "BACKGROUND")
  o.dropZone.bg:SetAllPoints()

  o.dropZone.border = o.dropZone:CreateTexture(nil, "BORDER")
  o.dropZone.border:SetPoint("TOPLEFT", 0, 0)
  o.dropZone.border:SetPoint("BOTTOMRIGHT", 0, 0)

  o.dropZone.accent = o.dropZone:CreateTexture(nil, "ARTWORK")
  o.dropZone.accent:SetPoint("TOPLEFT", 1, -1)
  o.dropZone.accent:SetPoint("TOPRIGHT", -1, -1)
  o.dropZone.accent:SetHeight(1)

  o.dropZone.plus = o.dropZone:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.dropZone.plus:SetPoint("LEFT", 10, 0)
  o.dropZone.plus:SetText("+")
  o.dropZone.plus:SetTextColor(1.0, 0.82, 0.18)

  o.dropZone.label = o.dropZone:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.dropZone.label:SetPoint("TOPLEFT", 28, -7)
  o.dropZone.label:SetPoint("RIGHT", -10, 0)
  o.dropZone.label:SetJustifyH("LEFT")
  o.dropZone.label:SetWordWrap(false)
  o.dropZone.label:SetText("Drop a spell here to add a trigger")

  o.dropZone.hint = o.dropZone:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.dropZone.hint:SetPoint("TOPLEFT", 28, -22)
  o.dropZone.hint:SetPoint("RIGHT", -10, 0)
  o.dropZone.hint:SetJustifyH("LEFT")
  o.dropZone.hint:SetJustifyV("TOP")
  o.dropZone.hint:SetWordWrap(true)
  o.dropZone.hint:SetText("Drag from spellbook, action bar, or item.")

  return o
end

if AceGUI and (AceGUI:GetWidgetVersion(WIDGET_TYPE) or 0) < WIDGET_VERSION then
  local methods = {
    OnAcquire = function(self)
      self.widgets = self.widgets or {}
      self.rowWidgets = self.rowWidgets or {}
      self.onChanged = nil
      self.onRequestRender = nil
      self.isStackable = nil
      self.embedded = false
      self.draft = {}
      self.frame:Show()
    end,

    OnRelease = function(self)
      self:ClearRows()
      self.onChanged = nil
      self.onRequestRender = nil
      self.isStackable = nil
      self.draft = nil
      self.frame:ClearAllPoints()
      self.frame:SetParent(UIParent)
    end,

    Configure = function(self, opts)
      opts = opts or {}
      self.onChanged = opts.onChanged
      self.onRequestRender = opts.onRequestRender
      self.isStackable = opts.isStackable
      self.embedded = opts.embedded == true
      if self.embedded then
        self.title:Hide()
        self.desc:Hide()
      else
        self.title:Show()
        self.desc:Show()
      end
      self.content:ClearAllPoints()
      self.content:SetPoint("TOPLEFT", 0, self.embedded and 0 or -36)
      self.content:SetPoint("TOPRIGHT", 0, self.embedded and 0 or -36)
      if not self.embedded then
        createCardBackdrop(self.frame)
      elseif self.frame.SetBackdrop then
        self.frame:SetBackdrop(nil)
      end
    end,

    Commit = TriggerList.Commit,
    ClearRows = TriggerList.ClearRows,
    Render = TriggerList.Render,
    SetDraft = TriggerList.SetDraft,
  }

  local function Constructor()
    local widget = buildTriggerListShell(setmetatable({}, TriggerList), nil, {})
    widget.type = WIDGET_TYPE

    for key, value in pairs(TriggerList) do
      if type(value) == "function" and widget[key] == nil and key ~= "Create" then
        widget[key] = value
      end
    end

    for method, func in pairs(methods) do
      widget[method] = func
    end

    widget.frame.obj = widget
    return AceGUI:RegisterAsWidget(widget)
  end

  AceGUI:RegisterWidgetType(WIDGET_TYPE, Constructor, WIDGET_VERSION)
end

function TriggerList:Create(parent, opts)
  if AceGUI then
    local widget = AceGUI:Create(WIDGET_TYPE)
    widget.frame:SetParent(parent)
    widget.frame._aceWidget = widget
    widget.Commit = TriggerList.Commit
    widget.ClearRows = TriggerList.ClearRows
    widget.Render = TriggerList.Render
    widget.SetDraft = TriggerList.SetDraft
    widget:Configure(opts)
    return widget
  end

  local o = buildTriggerListShell(setmetatable({}, self), parent, opts)

  return o
end

W.TriggerListWidget = TriggerList
