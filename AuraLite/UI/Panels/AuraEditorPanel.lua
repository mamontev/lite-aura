local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local V = UI.ValidationBus
local Schemas = UI.Schemas
local Repo = UI.AuraRepository
local RuleRepo = UI.RuleRepository
local FieldFactory = UI.FieldFactory
local Widgets = UI.Widgets or {}
local Skin = ns.UISkin
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local AuraEditorPanel = {}
AuraEditorPanel.__index = AuraEditorPanel

local function ensureBackdropHost(frame)
  if not frame then
    return nil
  end
  if type(frame.SetBackdrop) == "function" then
    return frame
  end
  if not frame._alBackdropHost then
    local host = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    host:SetPoint("TOPLEFT", 0, 0)
    host:SetPoint("BOTTOMRIGHT", 0, 0)
    host:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
    frame._alBackdropHost = host
  end
  return frame._alBackdropHost
end

local function createBackdrop(frame)
  if not frame then
    return
  end
  local target = ensureBackdropHost(frame)
  if target and type(target.SetBackdrop) == "function" then
    target:SetBackdrop(nil)
  end
end

local function createCardBackdrop(frame)
  local target = ensureBackdropHost(frame)
  if not target then
    return
  end

  target:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  target:SetBackdropColor(0.075, 0.082, 0.095, 0.36)
  target:SetBackdropBorderColor(0.20, 0.23, 0.28, 0.42)

  if not target._alCardShade then
    target._alCardShade = target:CreateTexture(nil, "BACKGROUND")
    target._alCardShade:SetPoint("TOPLEFT", 1, -1)
    target._alCardShade:SetPoint("BOTTOMRIGHT", -1, 1)
    target._alCardShade:SetTexture("Interface\\Buttons\\WHITE8x8")
    target._alCardShade:SetVertexColor(1, 1, 1, 0.018)
  end

  if not target._alCardAccent then
    target._alCardAccent = target:CreateTexture(nil, "ARTWORK")
    target._alCardAccent:SetPoint("TOPLEFT", 10, -10)
    target._alCardAccent:SetPoint("TOPRIGHT", -10, -10)
    target._alCardAccent:SetHeight(1)
    target._alCardAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  target._alCardAccent:SetColorTexture(0.90, 0.76, 0.24, 0.16)

  if not target._alCardHeaderShade then
    target._alCardHeaderShade = target:CreateTexture(nil, "BORDER")
    target._alCardHeaderShade:SetPoint("TOPLEFT", 1, -1)
    target._alCardHeaderShade:SetPoint("TOPRIGHT", -1, -1)
    target._alCardHeaderShade:SetHeight(28)
    target._alCardHeaderShade:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  target._alCardHeaderShade:SetColorTexture(0.13, 0.14, 0.17, 0.28)
end

local function isDirectAuraTracking(draft)
  if UI and UI.Bindings and UI.Bindings.IsDirectAuraTracking then
    return UI.Bindings:IsDirectAuraTracking(draft)
  end
  return tostring(draft and draft.unit or "player") == "target"
end

local function isEstimatedTargetTracking(draft)
  if UI and UI.Bindings and UI.Bindings.IsEstimatedTargetDebuffTracking then
    return UI.Bindings:IsEstimatedTargetDebuffTracking(draft)
  end
  return false
end

local function isCooldownTracking(draft)
  if UI and UI.Bindings and UI.Bindings.IsCooldownTracking then
    return UI.Bindings:IsCooldownTracking(draft)
  end
  return tostring(draft and draft.unit or "player") == "player"
    and tostring(draft and draft.trackingMode or "") == "cooldown"
end

local function getTrackingSummary(draft)
  draft = draft or {}
  if isCooldownTracking(draft) then
    return "Player cooldown"
  end
  local unit = tostring(draft.unit or "player")
  if unit == "target" then
    if isEstimatedTargetTracking(draft) then
      return "Estimated from your cast"
    end
    return "Confirmed read"
  end
  return "Rule-based cast trigger"
end

local function applyGroupConfigToDraft(draft, groupID)
  if type(draft) ~= "table" then
    return
  end
  groupID = tostring(groupID or "")
  draft.group = groupID
  draft.groupID = groupID
  if groupID == "" then
    draft.groupName = ""
    draft.groupDirection = "RIGHT"
    draft.groupSpacing = 4
    draft.groupSort = "list"
    draft.groupWrapAfter = 0
    draft.groupOffsetX = 0
    draft.groupOffsetY = 0
    return
  end

  if ns.SettingsData and ns.SettingsData.GetGroupConfig then
    local groupConfig = ns.SettingsData:GetGroupConfig(groupID)
    local layout = (groupConfig and groupConfig.layout) or {}
    draft.groupName = tostring(groupConfig and groupConfig.name or draft.groupName or "")
    draft.groupDirection = tostring(layout.direction or "RIGHT")
    draft.groupSpacing = tonumber(layout.spacing) or 4
    draft.groupSort = tostring(layout.sort or "list")
    draft.groupWrapAfter = tonumber(layout.wrapAfter) or 0
    draft.groupOffsetX = tonumber(layout.nudgeX) or 0
    draft.groupOffsetY = tonumber(layout.nudgeY) or 0
  end
end

local function inferTrackingPreset(draft)
  draft = draft or {}
  if isCooldownTracking(draft) then
    return "cooldown_player"
  end
  local unit = tostring(draft.unit or "player")
  if unit == "target" then
    return "debuff_target"
  end
  return "buff_player"
end

local function shouldShowConsumeBehavior(draft)
  draft = draft or {}
  local maxStacks = tonumber(draft.maxStacks) or 1
  local stackBehavior = tostring(draft.stackBehavior or "replace")
  return maxStacks > 1 or stackBehavior == "add"
end

local function isStackingSyntheticAura(draft)
  draft = draft or {}
  local maxStacks = tonumber(draft.maxStacks) or 1
  local stackBehavior = tostring(draft.stackBehavior or "replace")
  return maxStacks > 1 or stackBehavior == "add"
end

local function shouldExpandStackOptions(draft, panel)
  if panel and panel.stackOptionsExpanded ~= nil then
    return panel.stackOptionsExpanded == true
  end
  return isStackingSyntheticAura(draft)
end

local function normalizeProduceTriggers(draft)
  if UI and UI.Bindings and UI.Bindings.GetProduceTriggers then
    return UI.Bindings:GetProduceTriggers(draft)
  end
  return {}
end

local function spellIDResolves(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return false
  end
  if ns.AuraAPI and ns.AuraAPI.GetSpellName then
    local name = ns.AuraAPI:GetSpellName(spellID)
    if type(name) == "string" and name ~= "" then
      return true
    end
  end
  return false
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

local function syncProduceTriggersToDraft(draft)
  if not draft then
    return
  end
  normalizeProduceTriggers(draft)
end

local function isTabAvailable(draft, tabKey, showAdvanced)
  if not draft then
    return false
  end
  if showAdvanced ~= true and tabKey == "Advanced" then
    return false
  end
  return true
end

local function getCurrentClassAndSpec()
  local _, classToken = UnitClass and UnitClass("player") or nil
  classToken = tostring(classToken or ""):upper()
  local specID, specName = nil, ""
  if GetSpecialization and GetSpecializationInfo then
    local specIndex = GetSpecialization()
    if specIndex then
      local a, b, c, d = GetSpecializationInfo(specIndex)
      if type(a) == "number" then
        specID = tonumber(a)
        specName = tostring(b or "")
      else
        specID = tonumber(d)
        specName = tostring(a or "")
      end
    end
  end
  return classToken, specID, specName
end

local function normalizeSectionKey(text)
  text = tostring(text or ""):lower()
  text = text:gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
  if text == "" then
    text = "section"
  end
  return text
end

local function lookupOptionLabel(options, wanted)
  wanted = tostring(wanted or "")
  for i = 1, #(options or {}) do
    local row = options[i]
    if tostring(row.value or "") == wanted then
      return tostring(row.label or wanted)
    end
    if type(row.menuList) == "table" then
      for j = 1, #row.menuList do
        local child = row.menuList[j]
        if tostring(child.value or "") == wanted then
          return tostring(child.label or wanted)
        end
      end
    end
  end
  return wanted
end

local function hasLoadSpecOption(options, wanted)
  wanted = tostring(wanted or "")
  if wanted == "" then
    return true
  end
  for i = 1, #(options or {}) do
    local row = options[i]
    if tostring(row and row.value or "") == wanted then
      return true
    end
    if type(row and row.menuList) == "table" and hasLoadSpecOption(row.menuList, wanted) then
      return true
    end
  end
  return false
end

local function addInfoBox(parent, y, title, body, height, options)
  options = type(options) == "table" and options or {}
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createCardBackdrop(frame)
  frame:SetHeight(height or 70)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -14, 0)

  local header = nil
  if Widgets.SectionHeaderWidget and Widgets.SectionHeaderWidget.Create then
    header = Widgets.SectionHeaderWidget:Create(frame, {
      title = title or "",
      compact = true,
      collapsible = options.collapsible,
      collapsed = options.collapsed,
      onToggle = options.onToggle,
    })
    header:SetPoint("TOPLEFT", 10, -2)
    header:SetPoint("TOPRIGHT", -10, -2)
  end

  local text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  text:SetPoint("TOPLEFT", 10, -18)
  text:SetPoint("RIGHT", -10, 0)
  text:SetJustifyH("LEFT")
  text:SetText(body or "")

  frame.header = header
  frame.bodyText = text
  return frame
end

local function addInlineNote(parent, y, text)
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -14, 0)
  frame:SetHeight(22)

  frame.line = frame:CreateTexture(nil, "ARTWORK")
  frame.line:SetPoint("TOPLEFT", 0, 0)
  frame.line:SetPoint("TOPRIGHT", 0, 0)
  frame.line:SetHeight(1)
  frame.line:SetColorTexture(1.0, 0.82, 0.18, 0.12)

  frame.text = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.text:SetPoint("TOPLEFT", 0, -5)
  frame.text:SetPoint("RIGHT", 0, 0)
  frame.text:SetJustifyH("LEFT")
  frame.text:SetText(text or "")
  return frame
end

local function createCard(parent, y, title, body, height, options)
  options = type(options) == "table" and options or {}
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  createCardBackdrop(frame)
  frame:SetHeight(height or 96)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -14, 0)
  frame._alCompactCard = options.compact == true

  if Widgets.SectionHeaderWidget and Widgets.SectionHeaderWidget.Create then
    frame.header = Widgets.SectionHeaderWidget:Create(frame, {
      title = title or "",
      subtitle = (options.compact == true) and "" or (body or ""),
      compact = options.compact == true,
      collapsible = options.collapsible,
      collapsed = options.collapsed,
      onToggle = options.onToggle,
    })
    frame.header:SetPoint("TOPLEFT", 12, -8)
    frame.header:SetPoint("TOPRIGHT", -12, -8)
    frame.heading = frame.header.title
    frame.desc = frame.header.subtitle
  else
    frame.heading = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    frame.heading:SetPoint("TOPLEFT", 12, -10)
    frame.heading:SetText(title or "")

    frame.desc = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.desc:SetPoint("TOPLEFT", 12, -28)
    frame.desc:SetPoint("RIGHT", -12, 0)
    frame.desc:SetJustifyH("LEFT")
    frame.desc:SetText(body or "")
  end

  frame.content = CreateFrame("Frame", nil, frame)
  local contentTop = (options.compact == true) and -36 or -52
  frame.content:SetPoint("TOPLEFT", 10, contentTop)
  frame.content:SetPoint("TOPRIGHT", -10, contentTop)
  frame.content:SetHeight(math.max(24, (height or 96) - ((options.compact == true) and 44 or 62)))

  frame.contentChrome = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  frame.contentChrome:SetPoint("TOPLEFT", frame.content, -6, 6)
  frame.contentChrome:SetPoint("BOTTOMRIGHT", frame.content, 6, -6)
  frame.contentChrome:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame.contentChrome:SetBackdropColor(0.11, 0.12, 0.14, 0.12)
  frame.contentChrome:SetBackdropBorderColor(0.22, 0.25, 0.30, 0.10)
  frame.contentChrome:SetFrameLevel(frame:GetFrameLevel())
  frame.content:SetFrameLevel(frame.contentChrome:GetFrameLevel() + 1)
  if options.collapsed then
    frame.content:Hide()
    frame.contentChrome:Hide()
  end

  return frame
end

local function beginCollapsibleTrackingCard(panel, y, sectionKey, title, body, height)
  local expanded = panel:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local collapsedCard = createCard(panel.content, y, title, body, 56, {
      compact = true,
      collapsible = true,
      collapsed = true,
      onToggle = function(nextExpanded)
        panel:SetSectionExpanded(sectionKey, nextExpanded)
        panel:RenderTab("Tracking")
      end,
    })
    panel.fieldWidgets[#panel.fieldWidgets + 1] = collapsedCard
    return nil, y - 66
  end

  local card = createCard(panel.content, y, title, body, height, {
    compact = true,
    collapsible = true,
    collapsed = false,
    onToggle = function(nextExpanded)
      panel:SetSectionExpanded(sectionKey, nextExpanded)
      panel:RenderTab("Tracking")
    end,
  })
  panel.fieldWidgets[#panel.fieldWidgets + 1] = card
  return card, y
end

local function setTabVisual(btn, active)
  if not btn then
    return
  end

  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btn, active)
    Skin:SetButtonVariant(btn, "tab")
    return
  end

  local fs = btn.GetFontString and btn:GetFontString() or btn.Text
  if active then
    btn:SetNormalFontObject("GameFontNormal")
    if fs and fs.SetTextColor then
      fs:SetTextColor(1.0, 0.85, 0.2)
    end
  else
    btn:SetNormalFontObject("GameFontHighlight")
    if fs and fs.SetTextColor then
      fs:SetTextColor(0.8, 0.88, 1.0)
    end
  end
end

local function createPresetButton(parent, width, xOffset, label, sublabel, active, onClick)
  local btn = CreateFrame("Button", nil, parent, "BackdropTemplate")
  local hasSub = tostring(sublabel or "") ~= ""
  btn:SetSize(width, hasSub and 58 or 34)

  btn.label = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.label:SetPoint("TOPLEFT", 10, -5)
  btn.label:SetPoint("RIGHT", -8, 0)
  btn.label:SetJustifyH("LEFT")
  btn.label:SetJustifyV("TOP")
  btn.label:SetText(label or "")
  btn.label:SetTextColor(0.95, 0.96, 0.98)

  btn.sub = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  btn.sub:SetPoint("TOPLEFT", 10, -22)
  btn.sub:SetPoint("RIGHT", -8, 0)
  btn.sub:SetJustifyH("LEFT")
  btn.sub:SetJustifyV("TOP")
  btn.sub:SetWordWrap(true)
  btn.sub:SetText(sublabel or "")
  btn.sub:SetTextColor(0.64, 0.68, 0.74)
  if hasSub then
    btn.sub:Show()
  else
    btn.sub:Hide()
  end

  btn:SetScript("OnClick", onClick)
  if Skin and Skin.ApplyClickableRow then
    Skin:ApplyClickableRow(btn, "row")
    if Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, active and "selected" or "normal")
    end
  end
  btn:SetScript("OnEnter", function(selfBtn)
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(selfBtn, "hover")
    end
  end)
  btn:SetScript("OnLeave", function(selfBtn)
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(selfBtn, active and "selected" or "normal")
    end
  end)
  return btn
end

local function createTrackingModeButton(parent, width, xOffset, label, sublabel, active, onClick)
  local btn = createPresetButton(parent, width, xOffset, label, sublabel, active, onClick)
  btn:SetHeight(54)
  btn.sub:ClearAllPoints()
  btn.sub:SetPoint("TOPLEFT", 10, -22)
  btn.sub:SetPoint("RIGHT", -8, 0)
  return btn
end

local function createCompactInput(parent, labelText, x, y, width, value, options)
  options = type(options) == "table" and options or {}
  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", x or 0, y or 0)
  frame:SetSize(width or 160, options.height or 42)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.label:SetPoint("TOPLEFT", 0, 0)
  frame.label:SetText(labelText or "")

  frame.edit = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  frame.edit:SetAutoFocus(false)
  frame.edit:SetPoint("TOPLEFT", 0, -16)
  frame.edit:SetSize(width or 160, 20)
  frame.edit:SetText(tostring(value or ""))
  if options.numeric then
    frame.edit:SetNumeric(true)
    frame.edit:SetMaxLetters(options.maxLetters or 4)
  end
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(frame.edit)
  end

  local function commit()
    if type(options.onCommit) == "function" then
      options.onCommit(frame.edit:GetText() or "")
    end
  end

  frame.edit:SetScript("OnEnterPressed", function(selfEdit)
    commit()
    selfEdit:ClearFocus()
  end)
  frame.edit:SetScript("OnEditFocusLost", commit)

  if options.spellWidget and FieldFactory and FieldFactory.AttachSpellResolver then
    FieldFactory.AttachSpellResolver(frame, frame.edit, {
      key = options.fieldKey or "spellID",
      widget = options.spellWidget,
      compactHint = options.compactHint ~= false and false or false,
    }, function(_, nextValue)
      if type(options.onCommit) == "function" then
        options.onCommit(nextValue)
      end
    end)
  end

  return frame
end

local function createValueSlider(parent, labelText, x, y, width, value, options)
  options = type(options) == "table" and options or {}
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetPoint("TOPLEFT", x or 0, y or 0)
  frame:SetSize(width or 240, 44)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.label:SetPoint("TOPLEFT", 0, 0)
  frame.label:SetText(labelText or "")

  frame.value = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.value:SetPoint("TOPRIGHT", 0, 0)
  frame.value:SetJustifyH("RIGHT")

  frame.slider = CreateFrame("Slider", nil, frame, "OptionsSliderTemplate")
  frame.slider:SetPoint("TOPLEFT", 0, -14)
  frame.slider:SetPoint("TOPRIGHT", 0, -14)
  frame.slider:SetHeight(18)
  frame.slider:SetMinMaxValues(tonumber(options.min) or 0, tonumber(options.max) or 100)
  frame.slider:SetValueStep(tonumber(options.step) or 1)
  if frame.slider.SetObeyStepOnDrag then
    frame.slider:SetObeyStepOnDrag(true)
  end

  if frame.slider.Low then
    frame.slider.Low:SetText(tostring(options.minLabel or options.min or ""))
    frame.slider.Low:SetTextColor(0.56, 0.60, 0.68)
  end
  if frame.slider.High then
    frame.slider.High:SetText(tostring(options.maxLabel or options.max or ""))
    frame.slider.High:SetTextColor(0.56, 0.60, 0.68)
  end
  if frame.slider.Text then
    frame.slider.Text:SetText("")
  end

  local function normalize(nextValue)
    local minValue = tonumber(options.min) or 0
    local maxValue = tonumber(options.max) or 100
    local stepValue = tonumber(options.step) or 1
    nextValue = tonumber(nextValue) or minValue
    nextValue = math.max(minValue, math.min(maxValue, nextValue))
    if stepValue > 0 then
      nextValue = minValue + (math.floor(((nextValue - minValue) / stepValue) + 0.5) * stepValue)
    end
    if options.integer ~= false then
      nextValue = math.floor(nextValue + 0.5)
    end
    return nextValue
  end

  local function formatValue(nextValue)
    if type(options.format) == "function" then
      return tostring(options.format(nextValue))
    end
    return tostring(nextValue)
  end

  local initialValue = normalize(value)
  frame._syncing = true
  frame.slider:SetValue(initialValue)
  frame._syncing = false
  frame._lastValue = initialValue
  frame.value:SetText(formatValue(initialValue))

  frame.slider:SetScript("OnValueChanged", function(_, nextValue)
    local normalizedValue = normalize(nextValue)
    frame.value:SetText(formatValue(normalizedValue))
    if frame._syncing then
      frame._lastValue = normalizedValue
      return
    end
    if frame._lastValue == normalizedValue then
      return
    end
    frame._lastValue = normalizedValue
    if type(options.onChanged) == "function" then
      options.onChanged(normalizedValue)
    end
  end)

  return frame
end

local function createLabeledDivider(parent, text, y)
  if AceGUI then
    local heading = AceGUI:Create("Heading")
    heading:SetText(tostring(text or "Section"))
    heading.frame:SetParent(parent)
    heading.frame:ClearAllPoints()
    heading.frame:SetPoint("TOPLEFT", 12, y)
    heading.frame:SetPoint("RIGHT", -12, 0)
    heading.frame:SetHeight(20)
    if heading.label then
      heading.label:SetFontObject("GameFontHighlightSmall")
      heading.label:SetTextColor(0.94, 0.95, 0.98)
    end
    if heading.left then
      heading.left:SetVertexColor(1.0, 0.82, 0.18, 0.95)
      heading.left:SetHeight(7)
    end
    if heading.right then
      heading.right:SetVertexColor(1.0, 0.82, 0.18, 0.95)
      heading.right:SetHeight(7)
    end
    return heading
  end

  local frame = CreateFrame("Frame", nil, parent)
  frame:SetPoint("TOPLEFT", 12, y)
  frame:SetPoint("RIGHT", -12, 0)
  frame:SetHeight(28)

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  frame.bg:SetColorTexture(0.12, 0.13, 0.16, 0.68)

  frame.line = frame:CreateTexture(nil, "ARTWORK")
  frame.line:SetPoint("TOPLEFT", 0, 0)
  frame.line:SetPoint("TOPRIGHT", 0, 0)
  frame.line:SetHeight(1)
  frame.line:SetColorTexture(1.0, 0.82, 0.18, 0.36)

  frame.bottomLine = frame:CreateTexture(nil, "ARTWORK")
  frame.bottomLine:SetPoint("BOTTOMLEFT", 0, 0)
  frame.bottomLine:SetPoint("BOTTOMRIGHT", 0, 0)
  frame.bottomLine:SetHeight(1)
  frame.bottomLine:SetColorTexture(1.0, 0.82, 0.18, 0.22)

  frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  frame.label:SetPoint("LEFT", 10, 0)
  frame.label:SetText(tostring(text or "Section"))
  frame.label:SetTextColor(0.92, 0.95, 0.99)

  frame.tail = frame:CreateTexture(nil, "ARTWORK")
  frame.tail:SetPoint("LEFT", frame.label, "RIGHT", 10, 0)
  frame.tail:SetPoint("RIGHT", -8, 0)
  frame.tail:SetHeight(1)
  frame.tail:SetColorTexture(1.0, 0.82, 0.18, 0.14)
  return frame
end

local function trimText(text)
  return tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function appendSpellToCSV(existing, spellID)
  local out = {}
  local seen = {}
  for token in tostring(existing or ""):gmatch("[^,;%s]+") do
    local n = tonumber(token)
    if n and n > 0 and not seen[n] then
      seen[n] = true
      out[#out + 1] = tostring(n)
    end
  end
  spellID = tonumber(spellID)
  if spellID and spellID > 0 and not seen[spellID] then
    out[#out + 1] = tostring(spellID)
  end
  return table.concat(out, ", ")
end

local function estimateFieldHeight(field)
  if not field then
    return 0
  end
  if field.widget == "multiline" then
    return 92
  end
  if field.widget == "bartexture" then
    return 132
  end
  if field.widget == "soundpicker" then
    return 94
  end
  if field.widget == "groupselect" then
    return 96
  end
  if field.widget == "dropdown" then
    return 64
  end
  if field.widget == "checkbox" then
    return 40
  end
  return 36
end

local function collectFieldsByKeys(fieldsByKey, keys)
  local rows = {}
  for i = 1, #(keys or {}) do
    local field = fieldsByKey and fieldsByKey[keys[i]]
    if field then
      rows[#rows + 1] = field
    end
  end
  return rows
end

local function createSegmentButton(parent, width, height, text, x, y, variant, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width or 92, height or 22)
  btn:SetPoint("TOPLEFT", x or 0, y or 0)
  btn:SetText(text or "")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, variant or "segment")
  end
  btn:SetScript("OnClick", onClick)
  return btn
end

local STYLE_PRESETS = {
  {
    key = "minimal_proc",
    label = "Minimal Proc",
    sublabel = "Large icon with crisp timer focus.",
    summary = "Built for proc popups and easy center-screen recognition.",
    values = {
      displayMode = "icon",
      timerVisual = "icon",
      iconWidth = 44,
      iconHeight = 44,
      showTimerText = true,
      timerAnchor = "BOTTOM",
      customTextAnchor = "TOP",
      lowTime = 3,
      barColor = "",
      barTexture = "",
    },
  },
  {
    key = "clean_bar",
    label = "Clean Bar",
    sublabel = "Wide timer bar with strong readability.",
    summary = "Great for longer buffs, maintenance effects, and utility tracking.",
    values = {
      displayMode = "bar",
      timerVisual = "bar",
      barWidth = 190,
      barHeight = 18,
      showTimerText = true,
      timerAnchor = "BOTTOM",
      customTextAnchor = "TOP",
      lowTime = 4,
      barColor = "0.18,0.68,1.00",
      barTexture = "Interface\\AddOns\\AuraLite\\Media\\StatusBars\\aura_smooth",
    },
  },
  {
    key = "center_burst",
    label = "Center Burst",
    sublabel = "Hero-style icon plus accent bar.",
    summary = "Best for burst windows and high-priority combat moments.",
    values = {
      displayMode = "iconbar",
      timerVisual = "iconbar",
      iconWidth = 44,
      iconHeight = 44,
      barWidth = 128,
      barHeight = 14,
      barSide = "right",
      showTimerText = true,
      timerAnchor = "TOP",
      customTextAnchor = "BOTTOM",
      lowTime = 3,
      barColor = "0.95,0.72,0.18",
      barTexture = "Interface\\AddOns\\AuraLite\\Media\\StatusBars\\aura_pulse",
    },
  },
  {
    key = "compact_tracker",
    label = "Compact Tracker",
    sublabel = "Tight footprint for dense HUDs.",
    summary = "Keeps the aura small while preserving timing signal.",
    values = {
      displayMode = "iconbar",
      timerVisual = "iconbar",
      iconWidth = 30,
      iconHeight = 30,
      barWidth = 82,
      barHeight = 12,
      barSide = "right",
      showTimerText = false,
      timerAnchor = "BOTTOM",
      customTextAnchor = "TOP",
      lowTime = 2,
      barColor = "0.36,0.82,0.96",
      barTexture = "Interface\\AddOns\\AuraLite\\Media\\StatusBars\\aura_carbon",
    },
  },
}

local function findStylePreset(presetKey)
  presetKey = tostring(presetKey or "")
  for i = 1, #STYLE_PRESETS do
    if STYLE_PRESETS[i].key == presetKey then
      return STYLE_PRESETS[i]
    end
  end
  return nil
end

local STYLE_PRESET_FIELDS = {
  displayMode = true,
  timerVisual = true,
  iconWidth = true,
  iconHeight = true,
  barWidth = true,
  barHeight = true,
  barSide = true,
  showTimerText = true,
  barColor = true,
  barGradientEnabled = true,
  barColor2 = true,
  barTexture = true,
  lowTime = true,
  showNameText = true,
  nameTextSize = true,
  nameTextFont = true,
  timerAnchor = true,
  customTextAnchor = true,
}

local LIVE_PREVIEW_FIELDS = {
  name = true,
  displayName = true,
  displayMode = true,
  spellID = true,
  unit = true,
  trackingMode = true,
  iconMode = true,
  customTexture = true,
  barTexture = true,
  customText = true,
  timerVisual = true,
  iconWidth = true,
  iconHeight = true,
  barWidth = true,
  barHeight = true,
  showTimerText = true,
  timerTextSize = true,
  timerTextFont = true,
  barColor = true,
  barGradientEnabled = true,
  barColor2 = true,
  barSide = true,
  showNameText = true,
  nameTextSize = true,
  nameTextFont = true,
  showCustomText = true,
  customTextSize = true,
  customTextFont = true,
  visualStates = true,
  timerAnchor = true,
  timerOffsetX = true,
  timerOffsetY = true,
  customTextAnchor = true,
  customTextOffsetX = true,
  customTextOffsetY = true,
  lowTime = true,
  estimatedDuration = true,
  duration = true,
  soundOnShow = true,
  soundOnLow = true,
  soundOnExpire = true,
}

function AuraEditorPanel:RefreshLivePreview(forceRefresh)
  self:CommitProduceTriggerWidgets()

  if not ns.state then
    return
  end

  if not self.draft then
    ns.state.selectedAura = nil
    ns.state.selectedAuraPreviewItem = nil
    if forceRefresh and ns.EventRouter and ns.EventRouter.RefreshAll then
      ns.EventRouter:RefreshAll()
    end
    return
  end

  ns.state.selectedAura = {
    key = tostring(self.currentAuraId or self.draft._sourceKey or self.draft.id or ""),
    unit = tostring(self.draft.unit or "player"),
    spellID = tonumber(self.draft.spellID) or 0,
    instanceUID = tostring(self.draft.instanceUID or ""),
  }

  local previewItem = nil
  if UI and UI.Bindings and UI.Bindings.ToSettingsDataModel and ns.SettingsData and ns.SettingsData.BuildWatchItemFromModel then
    local settingsModel = UI.Bindings:ToSettingsDataModel(self.draft)
    local existingEntry = nil
    if ns.SettingsData.ResolveEntry then
      local sourceKey = tostring(self.currentAuraId or self.draft._sourceKey or self.draft.id or "")
      existingEntry = ns.SettingsData:ResolveEntry(sourceKey)
      local existingUID = existingEntry and existingEntry.item and tostring(existingEntry.item.instanceUID or "") or ""
      if existingUID ~= "" then
        settingsModel.instanceUID = existingUID
        self.draft.instanceUID = existingUID
        ns.state.selectedAura.instanceUID = existingUID
      end
    end
    previewItem = ns.SettingsData:BuildWatchItemFromModel(settingsModel, { existingItem = existingEntry and existingEntry.item or nil })
  end
  ns.state.selectedAuraPreviewItem = previewItem

  if E and E.Names and E.Names.SIMULATE_TRIGGER and previewItem then
    E:Emit(E.Names.SIMULATE_TRIGGER, {
      draft = previewItem,
      duration = tonumber(previewItem.duration or previewItem.estimatedDuration) or tonumber(self.draft.duration or self.draft.estimatedDuration) or 8,
      kind = "produce",
    })
  end

  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
end

function AuraEditorPanel:CommitProduceTriggerWidgets()
  if not self.draft then
    return
  end

  if self.triggerListWidget and self.triggerListWidget.Commit then
    self.triggerListWidget:Commit()
    return
  end
end

function AuraEditorPanel:ValidateDraft()
  local issues = {}
  if not self.draft then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  if tostring(self.draft.name or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "name", message = "Add a short aura name so it is easier to find later." }
  end

  local sid = tonumber(self.draft.spellID)
  if not sid or sid <= 0 then
    issues[#issues + 1] = { severity = "error", path = "spellID", message = "Aura SpellID is required." }
  end

  if isCooldownTracking(self.draft) then
    self.draft.triggerType = "cooldown"
    self.draft.actionMode = "produce"
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RefreshTabButtons()
    self:RenderTab(self.currentTab or "Tracking")
    self:RefreshLivePreview(true)
    return
  end

  if isEstimatedTargetTracking(self.draft) then
    if tostring(self.draft.castSpellIDs or "") == "" then
      issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "Add at least one spell you cast to start this debuff timer." }
    end
    if tonumber(self.draft.estimatedDuration) == nil or tonumber(self.draft.estimatedDuration) <= 0 then
      issues[#issues + 1] = { severity = "error", path = "estimatedDuration", message = "Set the expected debuff duration in seconds." }
    end
  elseif not isCooldownTracking(self.draft)
    and not isDirectAuraTracking(self.draft)
    and tostring(self.draft.triggerType or "cast") == "cast"
    and tostring(self.draft.castSpellIDs or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "Add at least one trigger spell to drive this aura." }
  end

  if not isCooldownTracking(self.draft) and not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) then
    local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
    if actionMode == "produce" then
      local triggers = normalizeProduceTriggers(self.draft)
      local validCount = 0
      for i = 1, #triggers do
        local trigger = triggers[i]
        if spellIDResolves(trigger and trigger.spellID) then
          validCount = validCount + 1
        elseif tonumber(trigger and trigger.spellID) and tonumber(trigger.spellID) > 0 then
          issues[#issues + 1] = {
            severity = "warn",
            path = "produceTriggers",
            message = string.format("Trigger %d uses a SpellID that could not be resolved.", i),
          }
        end
      end
      if validCount == 0 then
        issues[#issues + 1] = {
          severity = "error",
          path = "produceTriggers",
          message = "Add at least one valid spell that can grant or refresh this aura.",
        }
      end
    elseif actionMode == "consume" then
      local consumeCSV = tostring(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs or "")
      if consumeCSV == "" then
        issues[#issues + 1] = {
          severity = "error",
          path = "consumeCastSpellIDs",
          message = "Add the spell that should spend or remove this aura.",
        }
      end
    end
  end

  if not isCooldownTracking(self.draft) and not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) then
    if tostring(self.draft.actionMode or "produce") == "produce" then
      if tostring(self.draft.timerBehavior or "reset") == "extend" then
        if (tonumber(self.draft.maxDuration) or 0) <= 0 then
          issues[#issues + 1] = { severity = "warn", path = "maxDuration", message = "Set a maximum extended length so the timer has a cap." }
        elseif tonumber(self.draft.maxDuration) < (tonumber(self.draft.duration) or 0) then
          issues[#issues + 1] = { severity = "warn", path = "maxDuration", message = "The cap should be greater than or equal to the base timer length." }
        end
      end
      if tostring(self.draft.stackBehavior or "replace") == "add" and (tonumber(self.draft.maxStacks) or 0) < 2 then
        issues[#issues + 1] = { severity = "warn", path = "maxStacks", message = "Add-stack auras should usually allow at least 2 maximum stacks." }
      end
    end
  end

  local hasErrors = false
  for i = 1, #issues do
    if issues[i].severity == "error" then
      hasErrors = true
      break
    end
  end
  self.hasValidationErrors = hasErrors
  if self.btnSave then
    self.btnSave:SetEnabled(not hasErrors)
  end

  if #issues == 0 then
    V:SetStatus("ok", "Setup looks ready to save.")
  else
    V:SetEntries(issues)
  end
end

function AuraEditorPanel:UpdateHeader()
  if not self.draft then
    self.titleText:SetText("Inspector")
    self.subtitle:SetText("")
    if self.previewBannerText then
      self.previewBannerText:SetText("No aura selected")
    end
    if self.previewBannerHint then
      self.previewBannerHint:SetText("")
      self.previewBannerHint:Hide()
    end
    return
  end
  self.titleText:SetText(tostring(self.draft.name or self.draft.displayName or "Selected Aura"))
  self.subtitle:SetText("")
  if self.previewBannerText then
    self.previewBannerText:SetText(string.format("Spell %s", tostring(self.draft.spellID or "?")))
  end
  if self.previewBannerHint then
    self.previewBannerHint:SetText("")
    self.previewBannerHint:Hide()
  end
end

function AuraEditorPanel:RefreshTabButtons()
  local x = 0
  if self.btnMode then
    self.btnMode:SetText(self.showAdvanced and "Guided" or "Advanced")
  end
  for i = 1, #(Schemas and Schemas.EditorTabs or {}) do
    local tab = Schemas.EditorTabs[i]
    local btn = self.tabs and self.tabs[tab.key]
    if btn then
      if isTabAvailable(self.draft, tab.key, self.showAdvanced) then
        btn:Show()
        btn:ClearAllPoints()
        btn:SetPoint("TOPLEFT", x, 0)
        x = x + 108
      else
        btn:Hide()
      end
    end
  end
end

function AuraEditorPanel:ApplyRuleMode(mode)
  self:CommitProduceTriggerWidgets()

  if not self.draft or isDirectAuraTracking(self.draft) then
    return
  end
  mode = (tostring(mode or "produce") == "consume") and "consume" or "produce"
  self.triggerEditMode = mode
  self.draft.actionMode = mode

  local auraSpellID = tonumber(self.draft.spellID)
  local applied = false
  local preserveDraftProduce = (mode == "produce") and self.draft._produceTriggersDirty == true
  if (not preserveDraftProduce) and RuleRepo and RuleRepo.ApplyRulesForModeToDraft and auraSpellID and auraSpellID > 0 then
    RuleRepo:ApplyRulesForModeToDraft(self.draft, mode)
    applied = true
  elseif not preserveDraftProduce then
    local rule = nil
    if RuleRepo and RuleRepo.GetRuleForAuraByMode and auraSpellID and auraSpellID > 0 then
      rule = RuleRepo:GetRuleForAuraByMode(auraSpellID, mode)
    end
    if rule and UI and UI.Bindings and UI.Bindings.ApplyRuleToDraft then
      UI.Bindings:ApplyRuleToDraft(self.draft, rule)
      applied = true
    end
  end

  if applied then
    if mode == "produce" then
      syncProduceTriggersToDraft(self.draft)
    else
      self.draft.consumeCastSpellIDs = tostring(self.draft.castSpellIDs or "")
    end
  else
    local base = auraSpellID and ("aura" .. tostring(auraSpellID)) or "aura"
    self.draft.ruleID = base
    self.draft.ruleName = (mode == "consume") and "Consume Aura" or "Show Aura"
    self.draft.castSpellIDs = tostring(self.draft.castSpellIDs or "")
    self.draft.conditionLogic = self.draft.conditionLogic or "all"
    self.draft.talentSpellIDs = tostring(self.draft.talentSpellIDs or "")
    self.draft.requiredAuraSpellIDs = (mode == "consume" and auraSpellID) and tostring(auraSpellID) or tostring(self.draft.requiredAuraSpellIDs or "")
    self.draft.duration = tonumber(self.draft.duration) or 8
    self.draft.timerBehavior = tostring(self.draft.timerBehavior or "reset")
    self.draft.maxDuration = tonumber(self.draft.maxDuration) or 0
    self.draft.stackBehavior = tostring(self.draft.stackBehavior or "replace")
    self.draft.stackAmount = tonumber(self.draft.stackAmount) or 1
    self.draft.maxStacks = tonumber(self.draft.maxStacks) or 1
    local defaultConsume = (mode == "consume" and isStackingSyntheticAura(self.draft)) and "decrement" or "hide"
    self.draft.consumeBehavior = tostring(self.draft.consumeBehavior or defaultConsume)
    if mode == "produce" then
      syncProduceTriggersToDraft(self.draft)
    else
      self.draft.consumeCastSpellIDs = tostring(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs or "")
    end
  end

  if self.ruleBuilder and self.ruleBuilder.SetDraft then
    self.ruleBuilder:SetDraft(self.draft)
  end
end

function AuraEditorPanel:ApplyTrackingPreset(presetKey)
  if not self.draft then
    return
  end

  if presetKey == "debuff_target" then
    self.draft.unit = "target"
    self.draft.trackingMode = "estimated"
    self.draft.triggerType = "cast"
    self.draft.actionMode = "produce"
    self.draft.onlyMine = true
    if not tonumber(self.draft.estimatedDuration) or tonumber(self.draft.estimatedDuration) <= 0 then
      self.draft.estimatedDuration = tonumber(self.draft.duration) or 8
    end
  elseif presetKey == "cooldown_player" then
    self.draft.unit = "player"
    self.draft.trackingMode = "cooldown"
    self.draft.triggerType = "cooldown"
    self.draft.actionMode = "produce"
  else
    self.draft.unit = "player"
    self.draft.trackingMode = "confirmed"
    self.draft.triggerType = "cast"
    self.draft.actionMode = "produce"
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:UpdateHeader()
  self:ValidateDraft()
  self:RefreshTabButtons()
  self:RenderTab("Tracking")
  self:RefreshLivePreview(true)
end

function AuraEditorPanel:ApplyLayoutPreset(presetKey)
  if not self.draft then
    return
  end

  if presetKey == "icon" then
    self.draft.displayMode = "icon"
    self.draft.timerVisual = "icon"
    self.draft.iconWidth = 36
    self.draft.iconHeight = 36
    self.draft.showTimerText = true
    self.draft.timerAnchor = "BOTTOM"
    self.draft.customTextAnchor = "TOP"
  elseif presetKey == "compact" then
    self.draft.displayMode = "icon"
    self.draft.timerVisual = "icon"
    self.draft.iconWidth = 28
    self.draft.iconHeight = 28
    self.draft.showTimerText = false
    self.draft.customText = ""
  elseif presetKey == "iconbar" then
    self.draft.displayMode = "iconbar"
    self.draft.timerVisual = "iconbar"
    self.draft.iconWidth = 32
    self.draft.iconHeight = 32
    self.draft.barWidth = 94
    self.draft.barHeight = 32
    self.draft.barSide = "right"
    self.draft.showTimerText = true
  elseif presetKey == "targetbar" then
    self.draft.displayMode = "bar"
    self.draft.timerVisual = "bar"
    self.draft.barWidth = 180
    self.draft.barHeight = 18
    self.draft.showTimerText = true
    self.draft.timerAnchor = "BOTTOM"
    self.draft.customTextAnchor = "TOP"
  end
  self.draft.stylePreset = ""

  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  self:RenderTab("Appearance")
end

function AuraEditorPanel:ApplyStylePreset(presetKey)
  if not self.draft then
    return
  end

  local preset = findStylePreset(presetKey)
  if not preset then
    return
  end

  local values = preset.values or {}
  for key, value in pairs(values) do
    self.draft[key] = value
  end
  self.draft.stylePreset = preset.key

  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  self:RenderTab("Appearance")
end

function AuraEditorPanel:SetVisualStatePreset(kind, value)
  if not self.draft then
    return
  end
  if ns.VisualStyle and ns.VisualStyle.NormalizeStates then
    self.draft.visualStates = ns.VisualStyle:NormalizeStates(self.draft.visualStates)
  else
    self.draft.visualStates = self.draft.visualStates or {}
  end
  self.draft.visualStates[kind] = tostring(value or "off")
  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  self:RenderTab("Appearance")
end

function AuraEditorPanel:SetVisualStateGlowSpeed(value)
  if not self.draft then
    return
  end
  if ns.VisualStyle and ns.VisualStyle.NormalizeStates then
    self.draft.visualStates = ns.VisualStyle:NormalizeStates(self.draft.visualStates)
  else
    self.draft.visualStates = self.draft.visualStates or {}
  end
  self.draft.visualStates.glowSpeed = math.max(0.25, math.min(3.0, tonumber(value) or 1.0))
  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
end

function AuraEditorPanel:LoadAura(auraId)
  auraId = (tostring(auraId or "") ~= "") and tostring(auraId) or nil
  if self._loadAuraInProgress == true and self._loadingAuraId == auraId then
    return
  end
  if self.currentAuraId == auraId and self.draft and self._forceAuraReload ~= true then
    return
  end

  self._loadAuraInProgress = true
  self._loadingAuraId = auraId
  self.draft = Repo:GetAuraDraft(auraId)
  self.deleteArmedUntil = nil
  if self.draft and tostring(self.draft.unit or "player") == "target" and tostring(self.draft.trackingMode or "confirmed") == "confirmed" then
    self.draft.trackingMode = "estimated"
    self.draft.triggerType = "cast"
    self.draft.actionMode = "produce"
    self.draft.onlyMine = true
  end
  self.triggerEditMode = tostring(self.draft and self.draft.actionMode or "produce")
  if self.draft then
    self.draft._produceTriggersDirty = false
  end
  self.currentAuraId = self.draft and self.draft.id or auraId
  if S and S.SetDirty then
    S:SetDirty(false)
  end

  self:UpdateHeader()
  self:RefreshTabButtons()
  local tab = (S and S.Get and S:Get().activeTab) or "Tracking"
  if not isTabAvailable(self.draft, tab, self.showAdvanced) then
    tab = "Tracking"
    if S and S.SetActiveTab then
      S:SetActiveTab(tab)
    end
  end
  self:RenderTab(tab)
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  if S and S.SetDirty then
    S:SetDirty(false)
  end
  self._forceAuraReload = false
  self._loadAuraInProgress = false
  self._loadingAuraId = nil
end

function AuraEditorPanel:RefreshAdvancedLoadConditionWidgets()
  if self.currentTab ~= "Advanced" then
    return
  end

  local fieldWidgetByKey = self.fieldWidgetByKey or {}
  local classWidget = fieldWidgetByKey.loadClassToken
  local specWidget = fieldWidgetByKey.loadSpecID
  local classControl = classWidget and classWidget.control
  local specControl = specWidget and specWidget.control

  if classControl and classControl.SetValue then
    classControl:SetValue(tostring(self.draft and self.draft.loadClassToken or ""), false)
  end

  if specControl and specControl.SetOptions then
    local specOptions = (ns.SettingsData and ns.SettingsData.GetLoadSpecMenuOptions and ns.SettingsData:GetLoadSpecMenuOptions(self.draft and self.draft.loadClassToken or "")) or {}
    specControl:SetOptions(specOptions)
    specControl:SetValue(tostring(self.draft and self.draft.loadSpecID or ""), false)
  end
end

function AuraEditorPanel:OnFieldChanged(key, value)
  if not self.draft then
    return
  end

  self.draft[key] = value
  if key == "group" then
    applyGroupConfigToDraft(self.draft, value)
  elseif key == "groupID" then
    applyGroupConfigToDraft(self.draft, value)
  end
  if self.suspendFieldChanges == true then
    return
  end

  if key ~= "stylePreset" and STYLE_PRESET_FIELDS[key] then
    self.draft.stylePreset = ""
  end

  if key == "unit" then
    self.draft.triggerType = (tostring(value or "player") == "target") and "aura" or "cast"
    if tostring(value or "player") ~= "target" then
      self.draft.trackingMode = "confirmed"
    else
      self.draft.trackingMode = tostring(self.draft.trackingMode or "confirmed")
    end
    if self.draft.triggerType == "aura" then
      self.draft.actionMode = "produce"
    end
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RefreshTabButtons()
    self:RenderTab(self.currentTab or "Tracking")
    self:RefreshLivePreview(true)
    return
  end

  if key == "trackingMode" then
    if tostring(self.draft.unit or "player") == "target" and tostring(value or "confirmed") == "estimated" then
      self.draft.triggerType = "cast"
      self.draft.actionMode = "produce"
      self.draft.onlyMine = true
      if not tonumber(self.draft.estimatedDuration) or tonumber(self.draft.estimatedDuration) <= 0 then
        self.draft.estimatedDuration = tonumber(self.draft.duration) or 8
      end
    else
      self.draft.triggerType = "aura"
    end
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RefreshTabButtons()
    self:RenderTab(self.currentTab or "Tracking")
    self:RefreshLivePreview(true)
    return
  end

  if key == "loadClassToken" then
    local specOptions = (ns.SettingsData and ns.SettingsData.GetLoadSpecMenuOptions and ns.SettingsData:GetLoadSpecMenuOptions(value)) or {}
    if not hasLoadSpecOption(specOptions, self.draft.loadSpecID) then
      self.draft.loadSpecID = ""
    end
    if self.currentTab == "Advanced" then
      self:RefreshAdvancedLoadConditionWidgets()
      if not self._pendingAdvancedLoadRefresh then
        self._pendingAdvancedLoadRefresh = true
        C_Timer.After(0, function()
          if not self then
            return
          end
          self._pendingAdvancedLoadRefresh = false
          if self.currentTab == "Advanced" and self.draft then
            self:RenderTab(self.currentTab)
          end
        end)
      end
    end
  end

  if self.currentTab == "Appearance" and (
    key == "barGradientEnabled"
    or key == "iconMode"
    or key == "showNameText"
    or key == "showCustomText"
  ) then
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:UpdateHeader()
    self:ValidateDraft()
    self:RenderTab(self.currentTab)
    self:RefreshLivePreview(false)
    return
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end

  self:UpdateHeader()
  self:ValidateDraft()

  if self.ruleBuilder then
    self.ruleBuilder:SetDraft(self.draft)
  end
  if self.conditionTree then
    self.conditionTree:SetDraft(self.draft)
  end

  if E then
    E:Emit(E.Names.STATE_CHANGED, S and S:Get() or nil)
  end

  if LIVE_PREVIEW_FIELDS[key] then
    self:RefreshLivePreview(false)
  end
end

function AuraEditorPanel:ClearTabContent()
  self.produceTriggerWidgets = nil
  self.fieldWidgetByKey = {}

  if self.triggerListWidget then
    if type(self.triggerListWidget.Release) == "function" then
      self.triggerListWidget:Release()
    elseif self.triggerListWidget.frame then
      self.triggerListWidget.frame:Hide()
      self.triggerListWidget.frame:SetParent(nil)
    end
  end
  self.triggerListWidget = nil

  local releasedWidgets = {}
  for i = 1, #(self.fieldWidgets or {}) do
    local w = self.fieldWidgets[i]
    if w then
      if type(w.Release) == "function" then
        if not releasedWidgets[w] then
          releasedWidgets[w] = true
          w:Release()
        end
      elseif w._aceWidget and type(w._aceWidget.Release) == "function" then
        if not releasedWidgets[w._aceWidget] then
          releasedWidgets[w._aceWidget] = true
          w._aceWidget:Release()
        end
      elseif w._alReleased ~= true then
        w._alReleased = true
        w:Hide()
        w:SetParent(nil)
      end
    end
  end
  self.fieldWidgets = {}

  if self.ruleBuilder and self.ruleBuilder.frame then
    self.ruleBuilder.frame:Hide()
    self.ruleBuilder.frame:SetParent(nil)
  end
  self.ruleBuilder = nil

  if self.conditionTree and self.conditionTree.frame then
    self.conditionTree.frame:Hide()
    self.conditionTree.frame:SetParent(nil)
  end
  self.conditionTree = nil
end

function AuraEditorPanel:IsSectionExpanded(sectionKey, defaultExpanded)
  self.sectionCollapsed = self.sectionCollapsed or {}
  if self.sectionCollapsed[sectionKey] == nil then
    return defaultExpanded ~= false
  end
  return self.sectionCollapsed[sectionKey] ~= true
end

function AuraEditorPanel:SetSectionExpanded(sectionKey, expanded)
  self.sectionCollapsed = self.sectionCollapsed or {}
  self.sectionCollapsed[sectionKey] = not (expanded == true)
end

function AuraEditorPanel:RenderGenericFields(tab, yStart, parent, leftInset, rightInset)
  local fields = tab.fields or tab or {}
  local y = yStart
  parent = parent or self.content
  leftInset = tonumber(leftInset) or 16
  rightInset = tonumber(rightInset) or -24
  self.fieldWidgetByKey = self.fieldWidgetByKey or {}
  for i = 1, #fields do
    local field = fields[i]
    local widget = FieldFactory:CreateField(parent, field, self.draft, function(fKey, fValue)
      self:OnFieldChanged(fKey, fValue)
    end)
    widget:SetPoint("TOPLEFT", leftInset, y)
    widget:SetPoint("RIGHT", rightInset, 0)
    widget:Show()
    y = y - widget:GetHeight() - 8
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
    if field and field.key then
      self.fieldWidgetByKey[field.key] = widget
    end
  end
  return y
end

function AuraEditorPanel:RenderAppearanceCard(y, title, body, fields)
  local sectionKey = "appearance_" .. normalizeSectionKey(title)
  body = ""
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local card = createCard(self.content, y, title, body, 56, {
      compact = true,
      collapsible = true,
      collapsed = true,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab(self.currentTab or "Appearance")
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = card
    return y - 66
  end
  local cardHeight = 56
  for i = 1, #(fields or {}) do
    local field = fields[i]
    cardHeight = cardHeight + estimateFieldHeight(field) + 6
  end
  local card = createCard(self.content, y, title, body, cardHeight, {
    compact = true,
    collapsible = true,
    collapsed = false,
    onToggle = function(nextExpanded)
      self:SetSectionExpanded(sectionKey, nextExpanded)
      self:RenderTab(self.currentTab or "Appearance")
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = card
  local nextY = self:RenderGenericFields(fields or {}, -2, card.content, 12, -12)
  card.content:SetHeight(math.max(24, -nextY + 10))
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderDisplayCanvas(y)
  local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")
  local hasIconBar = mode == "iconbar"
  local cardHeight = hasIconBar and 128 or 112
  local card = createCard(self.content, y, "Artifact", "", cardHeight, {
    compact = true,
    collapsible = true,
    collapsed = false,
    onToggle = function(nextExpanded)
      self:SetSectionExpanded("appearance_visual_layout", nextExpanded)
      self:RenderTab("Appearance")
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local function makePreset(text, x, presetKey)
    local btn = createSegmentButton(card.content, 92, 22, text, 2 + x, -8, "segment", function()
      self:ApplyLayoutPreset(presetKey)
    end)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
  end

  makePreset("Icon", 0, "icon")
  makePreset("Compact", 102, "compact")
  makePreset("Icon + Bar", 204, "iconbar")
  makePreset("Target Bar", 336, "targetbar")

  local function makeMiniButton(text, x, onClick)
    local btn = createSegmentButton(card.content, 92, 22, text, 2 + x, hasIconBar and -56 or -48, "segment", onClick)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
    return btn
  end

  if hasIconBar then
    makeMiniButton("Icon Left", 0, function()
      self:OnFieldChanged("barSide", "right")
      self:RenderTab("Appearance")
    end)
    makeMiniButton("Icon Right", 88, function()
      self:OnFieldChanged("barSide", "left")
      self:RenderTab("Appearance")
    end)
  end
  makeMiniButton("Timer Above", 0, function()
    self:OnFieldChanged("timerAnchor", "TOP")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 2, hasIconBar and -56 or -48)
  makeMiniButton("Timer Below", 102, function()
    self:OnFieldChanged("timerAnchor", "BOTTOM")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 106, hasIconBar and -56 or -48)
  makeMiniButton("Text Above", 204, function()
    self:OnFieldChanged("customTextAnchor", "TOP")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 210, hasIconBar and -56 or -48)
  makeMiniButton("Text Below", 306, function()
    self:OnFieldChanged("customTextAnchor", "BOTTOM")
    self:RenderTab("Appearance")
  end):SetPoint("TOPLEFT", 314, hasIconBar and -56 or -48)

  card.content:SetHeight(hasIconBar and 96 or 72)
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderStyleStudio(y)
  local sectionKey = "style_studio"
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local collapsedCard = createCard(
      self.content,
      y,
      "Quick Starts",
      "",
      56,
      {
        compact = true,
        collapsible = true,
        collapsed = true,
        onToggle = function(nextExpanded)
          self:SetSectionExpanded(sectionKey, nextExpanded)
          self:RenderTab(self.currentTab or "Appearance")
        end,
      }
    )
    self.fieldWidgets[#self.fieldWidgets + 1] = collapsedCard
    return y - 66
  end
  local activePresetKey = tostring(self.draft and self.draft.stylePreset or "")
  local card = createCard(
    self.content,
    y,
    "Quick Starts",
    "",
    118,
    {
      compact = true,
      collapsible = true,
      collapsed = false,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab(self.currentTab or "Appearance")
      end,
    }
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local colWidth = 178
  local xPositions = { 2, 190 }
  local yPositions = { -4, -42 }
  for i = 1, #STYLE_PRESETS do
    local preset = STYLE_PRESETS[i]
    local col = ((i - 1) % 2) + 1
    local row = math.floor((i - 1) / 2) + 1
    local btn = createPresetButton(
      card.content,
      colWidth,
      xPositions[col],
      preset.label,
      "",
      preset.key == activePresetKey,
      function()
        self:ApplyStylePreset(preset.key)
      end
    )
    btn:SetPoint("TOPLEFT", xPositions[col], yPositions[row])
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
  end

  card.content:SetHeight(82)
  return y - 122
end

function AuraEditorPanel:RenderAppearanceFineTuneCard(y, mode)
  local sectionKey = "appearance_fine_tune"
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local card = createCard(self.content, y, "Fine Tune", "", 56, {
      compact = true,
      collapsible = true,
      collapsed = true,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab(self.currentTab or "Appearance")
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = card
    return y - 66
  end

  local hasIcon = mode == "icon" or mode == "iconbar"
  local hasBar = mode == "bar" or mode == "iconbar"
  local cardHeight = hasBar and 224 or 176
  local card = createCard(self.content, y, "Fine Tune", "", cardHeight, {
    compact = true,
    collapsible = true,
    collapsed = false,
    onToggle = function(nextExpanded)
      self:SetSectionExpanded(sectionKey, nextExpanded)
      self:RenderTab(self.currentTab or "Appearance")
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local leftX = 12
  local rightX = 266
  local topY = -4

  if hasIcon then
    local iconSlider = createValueSlider(card.content, "Icon Size", leftX, topY, 224, tonumber(self.draft.iconWidth) or 36, {
      min = 16,
      max = 96,
      step = 2,
      onChanged = function(nextValue)
        self:OnFieldChanged("iconWidth", nextValue)
        self:OnFieldChanged("iconHeight", nextValue)
      end,
      format = function(nextValue)
        return string.format("%d px", nextValue)
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = iconSlider
  end

  if hasBar then
    local barWidthSlider = createValueSlider(card.content, "Bar Width", hasIcon and rightX or leftX, topY, 224, tonumber(self.draft.barWidth) or 94, {
      min = 60,
      max = 260,
      step = 4,
      onChanged = function(nextValue)
        self:OnFieldChanged("barWidth", nextValue)
      end,
      format = function(nextValue)
        return string.format("%d px", nextValue)
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = barWidthSlider

    local barHeightSlider = createValueSlider(card.content, "Bar Height", leftX, -56, 224, tonumber(self.draft.barHeight) or 16, {
      min = 8,
      max = 32,
      step = 2,
      onChanged = function(nextValue)
        self:OnFieldChanged("barHeight", nextValue)
      end,
      format = function(nextValue)
        return string.format("%d px", nextValue)
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = barHeightSlider
  end

  local timerSliderY = hasBar and -56 or topY
  local timerSliderX = rightX
  local timerSlider = createValueSlider(card.content, "Timer Offset", timerSliderX, timerSliderY, 224, tonumber(self.draft.timerOffsetY) or -1, {
    min = -24,
    max = 24,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("timerOffsetY", nextValue)
    end,
    format = function(nextValue)
      return string.format("%+d px", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = timerSlider

  local textSlider = createValueSlider(card.content, "Label Offset", leftX, hasBar and -108 or -56, 224, tonumber(self.draft.customTextOffsetY) or 2, {
    min = -24,
    max = 24,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("customTextOffsetY", nextValue)
    end,
    format = function(nextValue)
      return string.format("%+d px", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = textSlider

  local timerXSlider = createValueSlider(card.content, "Timer X", rightX, hasBar and -108 or -56, 224, tonumber(self.draft.timerOffsetX) or 0, {
    min = -48,
    max = 48,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("timerOffsetX", nextValue)
    end,
    format = function(nextValue)
      return string.format("%+d px", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = timerXSlider

  local textXSlider = createValueSlider(card.content, "Label X", leftX, hasBar and -160 or -108, 224, tonumber(self.draft.customTextOffsetX) or 0, {
    min = -48,
    max = 48,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("customTextOffsetX", nextValue)
    end,
    format = function(nextValue)
      return string.format("%+d px", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = textXSlider

  local timerToggleLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timerToggleLabel:SetPoint("TOPLEFT", rightX, hasBar and -160 or -108)
  timerToggleLabel:SetText("Timer Text")
  self.fieldWidgets[#self.fieldWidgets + 1] = timerToggleLabel

  local btnTimerOn = createSegmentButton(card.content, 88, 20, "Show", rightX, hasBar and -178 or -126, "segment", function()
    self:OnFieldChanged("showTimerText", true)
    self:RenderTab("Appearance")
  end)
  local btnTimerOff = createSegmentButton(card.content, 88, 20, "Hide", rightX + 96, hasBar and -178 or -126, "segment", function()
    self:OnFieldChanged("showTimerText", false)
    self:RenderTab("Appearance")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnTimerOn, self.draft.showTimerText ~= false)
    Skin:SetButtonSelected(btnTimerOff, self.draft.showTimerText == false)
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnTimerOn
  self.fieldWidgets[#self.fieldWidgets + 1] = btnTimerOff

  card.content:SetHeight(hasBar and 204 or 156)
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderTextControlsCard(y, fields)
  local sectionKey = "appearance_text_controls"
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local card = createCard(self.content, y, "Text", "", 56, {
      compact = true,
      collapsible = true,
      collapsed = true,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab(self.currentTab or "Appearance")
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = card
    return y - 66
  end

  local card = createCard(self.content, y, "Text", "", 244, {
    compact = true,
    collapsible = true,
    collapsed = false,
    onToggle = function(nextExpanded)
      self:SetSectionExpanded(sectionKey, nextExpanded)
      self:RenderTab(self.currentTab or "Appearance")
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local toggleLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  toggleLabel:SetPoint("TOPLEFT", 12, -4)
  toggleLabel:SetText("Aura Name")
  self.fieldWidgets[#self.fieldWidgets + 1] = toggleLabel

  local btnShow = createSegmentButton(card.content, 88, 20, "Show", 12, -22, "segment", function()
    self:OnFieldChanged("showNameText", true)
    self:RenderTab("Appearance")
  end)
  local btnHide = createSegmentButton(card.content, 88, 20, "Hide", 108, -22, "segment", function()
    self:OnFieldChanged("showNameText", false)
    self:RenderTab("Appearance")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnShow, self.draft.showNameText ~= false)
    Skin:SetButtonSelected(btnHide, self.draft.showNameText == false)
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnShow
  self.fieldWidgets[#self.fieldWidgets + 1] = btnHide

  local timerLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  timerLabel:SetPoint("TOPLEFT", 12, -56)
  timerLabel:SetText("Timer Text")
  self.fieldWidgets[#self.fieldWidgets + 1] = timerLabel

  local btnTimerShow = createSegmentButton(card.content, 88, 20, "Show", 12, -74, "segment", function()
    self:OnFieldChanged("showTimerText", true)
    self:RenderTab("Appearance")
  end)
  local btnTimerHide = createSegmentButton(card.content, 88, 20, "Hide", 108, -74, "segment", function()
    self:OnFieldChanged("showTimerText", false)
    self:RenderTab("Appearance")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnTimerShow, self.draft.showTimerText ~= false)
    Skin:SetButtonSelected(btnTimerHide, self.draft.showTimerText == false)
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnTimerShow
  self.fieldWidgets[#self.fieldWidgets + 1] = btnTimerHide

  local extraToggleLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  extraToggleLabel:SetPoint("TOPLEFT", 12, -108)
  extraToggleLabel:SetText("Extra Text")
  self.fieldWidgets[#self.fieldWidgets + 1] = extraToggleLabel

  local btnExtraShow = createSegmentButton(card.content, 88, 20, "Show", 12, -126, "segment", function()
    self:OnFieldChanged("showCustomText", true)
    self:RenderTab("Appearance")
  end)
  local btnExtraHide = createSegmentButton(card.content, 88, 20, "Hide", 108, -126, "segment", function()
    self:OnFieldChanged("showCustomText", false)
    self:RenderTab("Appearance")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnExtraShow, self.draft.showCustomText ~= false)
    Skin:SetButtonSelected(btnExtraHide, self.draft.showCustomText == false)
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnExtraShow
  self.fieldWidgets[#self.fieldWidgets + 1] = btnExtraHide

  local sizeSlider = createValueSlider(card.content, "Aura Name Size", 266, -4, 224, tonumber(self.draft.nameTextSize) or 12, {
    min = 8,
    max = 32,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("nameTextSize", nextValue)
    end,
    format = function(nextValue)
      return string.format("%d pt", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = sizeSlider

  local timerSizeSlider = createValueSlider(card.content, "Timer Size", 266, -56, 224, tonumber(self.draft.timerTextSize) or 12, {
    min = 8,
    max = 32,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("timerTextSize", nextValue)
    end,
    format = function(nextValue)
      return string.format("%d pt", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = timerSizeSlider

  local customSizeSlider = createValueSlider(card.content, "Extra Text Size", 266, -108, 224, tonumber(self.draft.customTextSize) or 12, {
    min = 8,
    max = 32,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("customTextSize", nextValue)
    end,
    format = function(nextValue)
      return string.format("%d pt", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = customSizeSlider

  local offsetSlider = createValueSlider(card.content, "Extra Text Offset", 266, -160, 224, tonumber(self.draft.customTextOffsetY) or 2, {
    min = -24,
    max = 24,
    step = 1,
    onChanged = function(nextValue)
      self:OnFieldChanged("customTextOffsetY", nextValue)
    end,
    format = function(nextValue)
      return string.format("%+d px", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = offsetSlider

  local extraLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  extraLabel:SetPoint("TOPLEFT", 12, -162)
  extraLabel:SetText("Extra Text Content")
  self.fieldWidgets[#self.fieldWidgets + 1] = extraLabel

  local nextY = self:RenderGenericFields(fields or {}, -184, card.content, 12, -12)
  card.content:SetHeight(math.max(284, -nextY + 8))
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderVisualStateStudio(y)
  local sectionKey = "visual_state_studio"
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local collapsedCard = createCard(
      self.content,
      y,
      "Glow & Emphasis",
      "",
      56,
      {
        compact = true,
        collapsible = true,
        collapsed = true,
        onToggle = function(nextExpanded)
          self:SetSectionExpanded(sectionKey, nextExpanded)
          self:RenderTab(self.currentTab or "Appearance")
        end,
      }
    )
    self.fieldWidgets[#self.fieldWidgets + 1] = collapsedCard
    return y - 66
  end
  local states = (ns.VisualStyle and ns.VisualStyle:NormalizeStates(self.draft and self.draft.visualStates)) or (self.draft and self.draft.visualStates) or {}
  local card = createCard(
    self.content,
    y,
    "Glow & Emphasis",
    "",
    182,
    {
      compact = true,
      collapsible = true,
      collapsed = false,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab(self.currentTab or "Appearance")
      end,
    }
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local model = {
    glowOnGain = tostring(states.onGain or "off"),
    glowLowTime = tostring(states.lowTime or "warning"),
    glowMaxStacks = tostring(states.maxStacks or "gold"),
  }
  local fields = {
    { key = "glowOnGain", label = "On Show Glow", widget = "dropdown", options = {
      { value = "off", label = "None" },
      { value = "soft", label = "Soft Pulse" },
      { value = "burst", label = "Auto-Cast Pulse" },
      { value = "button", label = "Button Glow" },
      { value = "shine", label = "Shine" },
    }, minimalHelp = true },
    { key = "glowLowTime", label = "Low Time Glow", widget = "dropdown", options = {
      { value = "off", label = "None" },
      { value = "subtle", label = "Subtle" },
      { value = "warning", label = "Warning" },
      { value = "intense", label = "Intense" },
      { value = "pixel", label = "Pixel" },
    }, minimalHelp = true },
    { key = "glowMaxStacks", label = "Full Charges Glow", widget = "dropdown", options = {
      { value = "off", label = "None" },
      { value = "gold", label = "Gold" },
      { value = "heroic", label = "Heroic" },
      { value = "button", label = "Button Glow" },
    }, minimalHelp = true },
  }

  local nextY = -2
  for i = 1, #fields do
    local widget = FieldFactory:CreateField(card.content, fields[i], model, function(fKey, fValue)
      if fKey == "glowOnGain" then
        self:SetVisualStatePreset("onGain", fValue)
      elseif fKey == "glowLowTime" then
        self:SetVisualStatePreset("lowTime", fValue)
      elseif fKey == "glowMaxStacks" then
        self:SetVisualStatePreset("maxStacks", fValue)
      end
    end)
    widget:SetPoint("TOPLEFT", 12, nextY)
    widget:SetPoint("RIGHT", -12, 0)
    widget:Show()
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
    nextY = nextY - widget:GetHeight() - 6
  end

  local speedSlider = createValueSlider(card.content, "Glow Speed", 12, nextY, 224, tonumber(states.glowSpeed) or 1.0, {
    min = 0.25,
    max = 3.0,
    step = 0.05,
    onChanged = function(nextValue)
      self:SetVisualStateGlowSpeed(nextValue)
    end,
    format = function(nextValue)
      return string.format("%.2fx", nextValue)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = speedSlider

  card.content:SetHeight(math.max(150, -nextY + 42))
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderAppearanceSoundCard(y, fields)
  fields = fields or {}
  if #fields == 0 then
    return y
  end
  return self:RenderAppearanceCard(y, "Sound", "", fields)
end

function AuraEditorPanel:RenderAppearanceLookCard(y, fields)
  fields = fields or {}
  if #fields == 0 then
    return y
  end
  return self:RenderAppearanceCard(y, "Style & Color", "", fields)
end

function AuraEditorPanel:SetStackingEnabled(enabled)
  if not self.draft then
    return
  end
  enabled = enabled == true
  if enabled then
    self.draft.stackBehavior = "add"
    self.draft.stackAmount = math.max(1, tonumber(self.draft.stackAmount) or 1)
    self.draft.maxStacks = math.max(2, tonumber(self.draft.maxStacks) or 2)
    local triggers = normalizeProduceTriggers(self.draft)
    for i = 1, #triggers do
      triggers[i].stackAmount = math.max(1, tonumber(triggers[i].stackAmount) or 1)
    end
    self.stackOptionsExpanded = true
  else
    self.draft.stackBehavior = "replace"
    self.draft.stackAmount = 1
    self.draft.maxStacks = 1
    local triggers = normalizeProduceTriggers(self.draft)
    for i = 1, #triggers do
      triggers[i].stackAmount = 1
    end
    if tostring(self.draft.consumeBehavior or "hide") == "decrement" then
      self.draft.consumeBehavior = "hide"
    end
    self.stackOptionsExpanded = false
  end
  if S and S.SetDirty then
    S:SetDirty(true)
  end
  self:ValidateDraft()
  self:RefreshLivePreview(false)
end

function AuraEditorPanel:RenderTrackingStackCard(y, fieldsByKey)
  local enabled = isStackingSyntheticAura(self.draft)
  local optionFields = collectFieldsByKeys(fieldsByKey, { "stackAmount", "maxStacks" })
  local cardHeight = 116
  for i = 1, #optionFields do
    cardHeight = cardHeight + estimateFieldHeight(optionFields[i])
  end

  local card, nextY = beginCollapsibleTrackingCard(
    self,
    y,
    "tracking_charge_model",
    "Charge Model",
    "Choose whether this aura behaves like a single buff or a stackable charge system.",
    cardHeight
  )
  if not card then
    return nextY
  end

  local hint = card.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", 12, -4)
  hint:SetPoint("RIGHT", -12, 0)
  hint:SetJustifyH("LEFT")
  hint:SetJustifyV("TOP")
  hint:SetWordWrap(true)
  hint:SetText(enabled and "This aura can gain charges. Drag spells into the trigger area below and choose how many charges each spell grants." or "This aura acts like a single buff and simply refreshes when one of its trigger spells fires.")
  self.fieldWidgets[#self.fieldWidgets + 1] = hint

  local btnSingle = createTrackingModeButton(card.content, 248, 12, "Single Aura", "Refresh or show the aura with each valid trigger.", not enabled, function()
    self:SetStackingEnabled(false)
    self:RenderTab("Tracking")
  end)
  btnSingle:SetPoint("TOPLEFT", 12, -46)

  local btnStackable = createTrackingModeButton(card.content, 248, 268, "Stackable Charges", "Each trigger can add one or more charges up to a maximum.", enabled, function()
    self:SetStackingEnabled(true)
    self.stackOptionsExpanded = true
    self:RenderTab("Tracking")
  end)
  btnStackable:SetPoint("TOPLEFT", 268, -46)
  self.fieldWidgets[#self.fieldWidgets + 1] = btnSingle
  self.fieldWidgets[#self.fieldWidgets + 1] = btnStackable

  if enabled and #optionFields > 0 then
    local divider = createLabeledDivider(card.content, "Charge Limits", -112)
    self.fieldWidgets[#self.fieldWidgets + 1] = divider
    local contentBottomY = self:RenderGenericFields(optionFields, -148, card.content, 12, -12)
    card.content:SetHeight(math.max(24, -contentBottomY + 8))
    card:SetHeight(card.content:GetHeight() + 36)
  else
    card.content:SetHeight(114)
    card:SetHeight(150)
  end

  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderConsumeBehaviorCard(y)
  if not shouldShowConsumeBehavior(self.draft) then
    return y
  end

  local card, nextY = beginCollapsibleTrackingCard(
    self,
    y,
    "tracking_spend_behavior",
    "Spend Behavior",
    "Tell AuraLite whether each spender removes one charge or clears the whole aura.",
    114
  )
  if not card then
    return nextY
  end

  local consumeOne = tostring(self.draft.consumeBehavior or "hide") == "decrement"
  local btnOne = createTrackingModeButton(card.content, 248, 12, "Spend One Charge", "Best for stackable buffs where each spender removes a single charge.", consumeOne, function()
    self.draft.consumeBehavior = "decrement"
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:ValidateDraft()
    self:RefreshLivePreview(false)
    self:RenderTab("Tracking")
  end)
  btnOne:SetPoint("TOPLEFT", 12, -10)

  local btnAll = createTrackingModeButton(card.content, 248, 268, "Clear The Aura", "Use this when the spender should hide the aura entirely.", not consumeOne, function()
    self.draft.consumeBehavior = "hide"
    if S and S.SetDirty then
      S:SetDirty(true)
    end
    self:ValidateDraft()
    self:RefreshLivePreview(false)
    self:RenderTab("Tracking")
  end)
  btnAll:SetPoint("TOPLEFT", 268, -10)
  self.fieldWidgets[#self.fieldWidgets + 1] = btnOne
  self.fieldWidgets[#self.fieldWidgets + 1] = btnAll

  card.content:SetHeight(70)
  card:SetHeight(106)
  return y - 126
end

function AuraEditorPanel:RenderTrackingDetailsCard(y, title, body, fields)
  fields = fields or {}
  if #fields == 0 then
    return y
  end

  local cardHeight = 42
  for i = 1, #fields do
    cardHeight = cardHeight + estimateFieldHeight(fields[i])
  end

  local card = createCard(
    self.content,
    y,
    title,
    body,
    cardHeight,
    {
      compact = true,
      collapsible = false,
      collapsed = false,
    }
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local nextY = self:RenderGenericFields(fields, -4, card.content, 2, -2)
  card.content:SetHeight(math.max(24, -nextY + 6))
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderProduceDetailsCard(y)
  local extendMode = tostring(self.draft.timerBehavior or "reset") == "extend"
  local cardHeight = extendMode and 178 or 146
  local card, nextY = beginCollapsibleTrackingCard(
    self,
    y,
    "tracking_aura_definition",
    "Aura Definition",
    "Define where the aura lives, which aura ID should be shown, and how the timer reacts when triggers fire again.",
    cardHeight
  )
  if not card then
    return nextY
  end

  local ownershipDivider = createLabeledDivider(card.content, "Ownership", -2)
  self.fieldWidgets[#self.fieldWidgets + 1] = ownershipDivider

  local unitLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  unitLabel:SetPoint("TOPLEFT", 12, -34)
  unitLabel:SetText("Track This On")
  self.fieldWidgets[#self.fieldWidgets + 1] = unitLabel

  local btnPlayer = createSegmentButton(card.content, 110, 20, "Player", 12, -50, "segment", function()
    self:OnFieldChanged("unit", "player")
    self:RenderTab("Tracking")
  end)
  local btnTarget = createSegmentButton(card.content, 110, 20, "Target", 128, -50, "segment", function()
    self:OnFieldChanged("unit", "target")
    self:RenderTab("Tracking")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnPlayer, tostring(self.draft.unit or "player") == "player")
    Skin:SetButtonSelected(btnTarget, tostring(self.draft.unit or "player") == "target")
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnPlayer
  self.fieldWidgets[#self.fieldWidgets + 1] = btnTarget

  local spellField = createCompactInput(card.content, "Aura To Show", 12, -82, 182, self.draft.spellID, {
    spellWidget = "spellid",
    fieldKey = "spellID",
    onCommit = function(nextValue)
      self:OnFieldChanged("spellID", trimText(nextValue))
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = spellField
  local durationField = createCompactInput(card.content, "Base Duration (sec)", 218, -82, 126, self.draft.duration, {
    numeric = true,
    maxLetters = 4,
    onCommit = function(nextValue)
      self:OnFieldChanged("duration", tonumber(nextValue) or 0)
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = durationField

  local dividerA = createLabeledDivider(card.content, "Timing", -126)
  self.fieldWidgets[#self.fieldWidgets + 1] = dividerA

  local behaviorLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  behaviorLabel:SetPoint("TOPLEFT", 12, -158)
  behaviorLabel:SetText("If Triggered Again")
  self.fieldWidgets[#self.fieldWidgets + 1] = behaviorLabel

  local timerBehavior = tostring(self.draft.timerBehavior or "reset")
  local btnReset = createSegmentButton(card.content, 104, 20, "Reset Timer", 12, -176, "segment", function()
    self:OnFieldChanged("timerBehavior", "reset")
    self:RenderTab("Tracking")
  end)
  local btnExtend = createSegmentButton(card.content, 104, 20, "Extend To Cap", 122, -176, "segment", function()
    self:OnFieldChanged("timerBehavior", "extend")
    if (tonumber(self.draft.maxDuration) or 0) <= 0 then
      self:OnFieldChanged("maxDuration", math.max(tonumber(self.draft.duration) or 0, 1))
    end
    self:RenderTab("Tracking")
  end)
  local btnKeep = createSegmentButton(card.content, 104, 20, "Keep Current", 232, -176, "segment", function()
    self:OnFieldChanged("timerBehavior", "keep")
    self:RenderTab("Tracking")
  end)
  if Skin and Skin.SetButtonSelected then
    Skin:SetButtonSelected(btnReset, timerBehavior == "reset")
    Skin:SetButtonSelected(btnExtend, timerBehavior == "extend")
    Skin:SetButtonSelected(btnKeep, timerBehavior == "keep")
  end
  self.fieldWidgets[#self.fieldWidgets + 1] = btnReset
  self.fieldWidgets[#self.fieldWidgets + 1] = btnExtend
  self.fieldWidgets[#self.fieldWidgets + 1] = btnKeep

  if extendMode then
    local maxField = createCompactInput(card.content, "Maximum Duration (sec)", 356, -82, 142, self.draft.maxDuration, {
      numeric = true,
      maxLetters = 4,
      onCommit = function(nextValue)
        self:OnFieldChanged("maxDuration", tonumber(nextValue) or 0)
      end,
    })
    self.fieldWidgets[#self.fieldWidgets + 1] = maxField
  end

  card.content:SetHeight(extendMode and 202 or 194)
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderConsumeInputsCard(y)
  local card, nextY = beginCollapsibleTrackingCard(
    self,
    y,
    "tracking_spender_inputs",
    "Spender Inputs",
    "Define the aura being consumed, then drag or type the spells that should spend it.",
    146
  )
  if not card then
    return nextY
  end

  local definitionDivider = createLabeledDivider(card.content, "Consumed Aura", -2)
  self.fieldWidgets[#self.fieldWidgets + 1] = definitionDivider

  local spellField = createCompactInput(card.content, "Aura To Spend", 12, -34, 182, self.draft.spellID, {
    spellWidget = "spellid",
    fieldKey = "spellID",
    onCommit = function(nextValue)
      self:OnFieldChanged("spellID", trimText(nextValue))
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = spellField

  local castField = createCompactInput(card.content, "Spender SpellIDs", 206, -34, 250, self.draft.consumeCastSpellIDs or self.draft.castSpellIDs, {
    spellWidget = "spellcsv",
    fieldKey = "castSpellIDs",
    onCommit = function(nextValue)
      self.draft.consumeCastSpellIDs = tostring(nextValue or "")
      self.draft.castSpellIDs = tostring(nextValue or "")
      if S and S.SetDirty then
        S:SetDirty(true)
      end
      self:ValidateDraft()
    end,
  })
  self.fieldWidgets[#self.fieldWidgets + 1] = castField

  local dividerA = createLabeledDivider(card.content, "Drag A Spender", -84)
  self.fieldWidgets[#self.fieldWidgets + 1] = dividerA

  local dropBox = CreateFrame("Button", nil, card.content, "BackdropTemplate")
  dropBox:SetPoint("TOPLEFT", 12, -116)
  dropBox:SetPoint("RIGHT", -12, 0)
  dropBox:SetHeight(34)
  createCardBackdrop(dropBox)
  dropBox:RegisterForDrag("LeftButton")
  dropBox:EnableMouse(true)
  dropBox.label = dropBox:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  dropBox.label:SetPoint("LEFT", 10, 0)
  dropBox.label:SetPoint("RIGHT", -10, 0)
  dropBox.label:SetJustifyH("LEFT")
  dropBox.label:SetText("Drop a spender spell here to append it")
  self.fieldWidgets[#self.fieldWidgets + 1] = dropBox

  local function handleConsumeDrop()
    local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
    local spellID = nil
    if cursorType == "spell" and cursorSpellID then
      spellID = tonumber(cursorSpellID)
    elseif cursorType == "item" and cursorID and C_Item and C_Item.GetItemSpell then
      local _, itemSpellID = C_Item.GetItemSpell(cursorID)
      spellID = tonumber(itemSpellID)
    end
    if spellID and spellID > 0 then
      local nextCSV = appendSpellToCSV(self.draft.consumeCastSpellIDs or self.draft.castSpellIDs, spellID)
      self.draft.consumeCastSpellIDs = nextCSV
      self.draft.castSpellIDs = nextCSV
      castField.edit:SetText(nextCSV)
      if S and S.SetDirty then
        S:SetDirty(true)
      end
      self:ValidateDraft()
      ClearCursor()
    end
  end
  dropBox:SetScript("OnReceiveDrag", handleConsumeDrop)
  dropBox:SetScript("OnMouseUp", handleConsumeDrop)

  card.content:SetHeight(160)
  card:SetHeight(196)
  return y - 206
end

function AuraEditorPanel:RenderTrackingWorkflowCard(y, tab)
  local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
  local fields = tab.fields or {}
  local byKey = {}
  for i = 1, #fields do
    if fields[i] then
      byKey[fields[i].key] = fields[i]
    end
  end

  if actionMode == "produce" then
    y = self:RenderProduceTriggersCard(y)
    y = self:RenderTrackingStackCard(y, byKey)
    y = self:RenderProduceDetailsCard(y)
  else
    y = self:RenderConsumeBehaviorCard(y)
    y = self:RenderConsumeInputsCard(y)
  end

  return y
end

function AuraEditorPanel:RenderLoadConditionsCard(y, fieldsByKey)
  local sectionKey = "advanced_load_conditions"
  local expanded = self:IsSectionExpanded(sectionKey, true)
  if not expanded then
    local collapsedCard = createCard(
      self.content,
      y,
      "Load Conditions",
      "Restrict by class or spec.",
      56,
      {
        compact = true,
        collapsible = true,
        collapsed = true,
        onToggle = function(nextExpanded)
          self:SetSectionExpanded(sectionKey, nextExpanded)
          self:RenderTab("Advanced")
        end,
      }
    )
    self.fieldWidgets[#self.fieldWidgets + 1] = collapsedCard
    return y - 66
  end
  local card = createCard(
    self.content,
    y,
    "Load Conditions",
    "Restrict by class or spec.",
    176,
    {
      compact = true,
      collapsible = true,
      collapsed = false,
      onToggle = function(nextExpanded)
        self:SetSectionExpanded(sectionKey, nextExpanded)
        self:RenderTab("Advanced")
      end,
    }
  )
  self.fieldWidgets[#self.fieldWidgets + 1] = card

  local currentClassToken, currentSpecID, currentSpecName = getCurrentClassAndSpec()
  local loadClassToken = tostring(self.draft and self.draft.loadClassToken or ""):upper()
  local loadSpecID = tostring(self.draft and self.draft.loadSpecID or "")

  local classOptions = (ns.SettingsData and ns.SettingsData.GetLoadClassOptions and ns.SettingsData:GetLoadClassOptions()) or {}
  local specOptions = (ns.SettingsData and ns.SettingsData.GetLoadSpecMenuOptions and ns.SettingsData:GetLoadSpecMenuOptions(loadClassToken)) or {}
  local classLabel = (loadClassToken ~= "") and lookupOptionLabel(classOptions, loadClassToken) or "Any Class"
  local specLabel = (loadSpecID ~= "") and lookupOptionLabel(specOptions, loadSpecID) or "Any Spec"

  local status = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  status:SetPoint("TOPLEFT", 2, -2)
  status:SetPoint("RIGHT", -2, 0)
  status:SetJustifyH("LEFT")
  self.fieldWidgets[#self.fieldWidgets + 1] = status

  local detail = card.content:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail:SetPoint("TOPLEFT", 2, -20)
  detail:SetPoint("RIGHT", -2, 0)
  detail:SetJustifyH("LEFT")
  self.fieldWidgets[#self.fieldWidgets + 1] = detail

  local loaded = true
  local reason = ""
  if loadClassToken ~= "" and loadClassToken ~= currentClassToken then
    loaded = false
    reason = "Wrong Class"
  elseif loadSpecID ~= "" and tostring(currentSpecID or "") ~= loadSpecID then
    loaded = false
    reason = "Wrong Spec"
  end

  if loaded then
    status:SetText("|cff4dff88Loaded for your current character|r")
  else
    status:SetText("|cffff6b6bNot loaded for your current character|r")
  end

  local currentClassLabel = lookupOptionLabel(classOptions, currentClassToken)
  local currentLabel = string.format("Current: %s%s", currentClassLabel ~= "" and currentClassLabel or currentClassToken, currentSpecName ~= "" and (" / " .. currentSpecName) or "")
  local targetLabel = string.format("Aura setting: %s / %s", classLabel, specLabel)
  if loaded then
    detail:SetText(currentLabel .. "\n" .. targetLabel)
  else
    detail:SetText(currentLabel .. "\n" .. targetLabel .. "\nReason: " .. reason)
  end

  local quickLabel = card.content:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  quickLabel:SetPoint("TOPLEFT", 2, -52)
  quickLabel:SetText("Quick setup")
  self.fieldWidgets[#self.fieldWidgets + 1] = quickLabel

  local function makeQuickButton(text, x, onClick)
    local btn = createSegmentButton(card.content, 124, 18, text, x, -68, "segment", onClick)
    self.fieldWidgets[#self.fieldWidgets + 1] = btn
    return btn
  end

  makeQuickButton("Load Everywhere", 2, function()
    self:OnFieldChanged("loadClassToken", "")
    self:OnFieldChanged("loadSpecID", "")
    self:RenderTab("Advanced")
  end)
  makeQuickButton("Only My Class", 132, function()
    self:OnFieldChanged("loadClassToken", currentClassToken)
    self:OnFieldChanged("loadSpecID", "")
    self:RenderTab("Advanced")
  end)
  makeQuickButton("Only This Spec", 262, function()
    self:OnFieldChanged("loadClassToken", currentClassToken)
    self:OnFieldChanged("loadSpecID", tostring(currentSpecID or ""))
    self:RenderTab("Advanced")
  end)

  local nextY = self:RenderGenericFields({
    fieldsByKey.loadClassToken,
    fieldsByKey.loadSpecID,
  }, -96, card.content, 2, -2)

  card.content:SetHeight(math.max(132, -nextY + 8))
  card:SetHeight(card.content:GetHeight() + 36)
  return y - card:GetHeight() - 10
end

function AuraEditorPanel:RenderProduceTriggersCard(y)
  if Widgets.TriggerListWidget and Widgets.TriggerListWidget.Create then
    local card, nextY = beginCollapsibleTrackingCard(
      self,
      y,
      "tracking_produce_triggers",
      "Produce Triggers",
      "Drag spells in, reorder the trigger list, then refine what each spell does.",
      248
    )
    if not card then
      return nextY
    end

    local divider = createLabeledDivider(card.content, "Trigger Inputs", -2)
    self.fieldWidgets[#self.fieldWidgets + 1] = divider

    self.triggerListWidget = Widgets.TriggerListWidget:Create(card.content, {
      embedded = true,
      isStackable = isStackingSyntheticAura,
      onChanged = function()
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:ValidateDraft()
      end,
      onRequestRender = function()
        self._skipProduceTriggerCommitOnce = true
        self:RenderTab("Tracking")
      end,
    })
    self.triggerListWidget.frame:SetPoint("TOPLEFT", 12, -36)
    self.triggerListWidget.frame:SetPoint("RIGHT", -14, 0)
    self.triggerListWidget.frame:Show()
    self.triggerListWidget:SetDraft(self.draft)
    card.content:SetHeight(self.triggerListWidget.frame:GetHeight() + 46)
    card:SetHeight(card.content:GetHeight() + 36)
    return y - card:GetHeight() - 10
  end

  return y
end

function AuraEditorPanel:RenderTab(tabKey)
  if self._skipProduceTriggerCommitOnce == true then
    self._skipProduceTriggerCommitOnce = false
  else
    self:CommitProduceTriggerWidgets()
  end
  self.currentTab = tabKey
  self:ClearTabContent()

  if not self.content or not self.draft then
    return
  end

  local tab = Schemas and Schemas:GetTab(tabKey) or nil
  if not tab then
    return
  end

  for key, btn in pairs(self.tabs or {}) do
    setTabVisual(btn, key == tabKey)
  end
  self:RefreshTabButtons()
  self.suspendFieldChanges = true

  local y = -12

  if tabKey == "Tracking" then
    local presetFrame, nextY = beginCollapsibleTrackingCard(
      self,
      y,
      "tracking_behavior",
      "Behavior",
      "Choose where the aura should live and how AuraLite should observe it.",
      188
    )
    if not presetFrame then
      y = nextY
    else
      local presetContent = presetFrame.content

      local activePreset = inferTrackingPreset(self.draft)
      local btnCooldown = createPresetButton(
        presetContent,
        248,
        12,
        "Track My Cooldown",
        "Use the spell cooldown itself as the tracked artifact.",
        activePreset == "cooldown_player",
        function()
          self:ApplyTrackingPreset("cooldown_player")
        end
      )
      btnCooldown:SetPoint("TOPLEFT", 12, -8)

      local btnPlayer = createPresetButton(
        presetContent,
        248,
        12,
        "Appears On Me",
        "Use for buffs, procs, and effects on your character.",
        activePreset == "buff_player",
        function()
          self:ApplyTrackingPreset("buff_player")
        end
      )
      btnPlayer:SetPoint("TOPLEFT", 12, -74)

      local btnDebuff = createPresetButton(
        presetContent,
        248,
        268,
        "Appears On Target",
        "Create a local timer from your casts for target debuffs.",
        activePreset == "debuff_target",
        function()
          self:ApplyTrackingPreset("debuff_target")
        end
      )
      btnDebuff:SetPoint("TOPLEFT", 268, -74)

      self.fieldWidgets[#self.fieldWidgets + 1] = btnPlayer
      self.fieldWidgets[#self.fieldWidgets + 1] = btnDebuff
      self.fieldWidgets[#self.fieldWidgets + 1] = btnCooldown
      y = y - 198
    end

    if tostring(self.draft.unit or "player") == "target" then
      local modeFrame, modeY = beginCollapsibleTrackingCard(
        self,
        y,
        "tracking_target_mode",
        "Target Mode",
        "Target tracking is authored as a local timer from your casts, because direct target aura reads are not reliable enough.",
        72
      )
      if not modeFrame then
        y = modeY
      else
        local btnEstimated = createPresetButton(
          modeFrame.content,
          504,
          12,
          "Estimate From My Cast",
          "Start a local timer when your spell applies the effect.",
          true,
          function()
            self:OnFieldChanged("trackingMode", "estimated")
          end
        )
        btnEstimated:SetPoint("TOPLEFT", 12, -8)

        self.fieldWidgets[#self.fieldWidgets + 1] = btnEstimated
        y = y - 82
      end
    end

    if isCooldownTracking(self.draft) then
      local infoFrame = addInlineNote(
        self.content,
        y,
        "Reads the spell cooldown directly and styles it like the rest of your setup."
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 30
    elseif isEstimatedTargetTracking(self.draft) then
      local infoFrame = addInlineNote(
        self.content,
        y,
        "Starts a local timer on your target from the spells you cast."
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 30
    elseif isDirectAuraTracking(self.draft) then
      local infoFrame = addInlineNote(
        self.content,
        y,
        "Reads the selected target directly when Blizzard exposes the aura."
      )
      self.fieldWidgets[#self.fieldWidgets + 1] = infoFrame
      y = y - 30
    elseif Widgets.RuleBuilderWidget and Widgets.RuleBuilderWidget.Create then
      local quickModeFrame, modeY = beginCollapsibleTrackingCard(
        self,
        y,
        "tracking_spell_action",
        "Spell Action",
        "Tell AuraLite whether this spell grants the aura or spends one of its charges.",
        118
      )
      if not quickModeFrame then
        y = modeY
      else

        local isConsumeMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce") == "consume"
        local btnGive = createPresetButton(
          quickModeFrame.content,
          248,
          12,
          "This Spell Gives The Aura",
          "Use for procs, buffs, refreshes, and charge generation.",
          not isConsumeMode,
          function()
            self:ApplyRuleMode("produce")
            if S and S.SetDirty then
              S:SetDirty(true)
            end
            self:RenderTab("Tracking")
          end
        )
        btnGive:SetPoint("TOPLEFT", 12, -8)

        local btnSpend = createPresetButton(
          quickModeFrame.content,
          248,
          268,
          "This Spell Spends 1 Charge",
          "Use for spender buttons like Arcane Shot or similar finishers.",
          isConsumeMode and tostring(self.draft.consumeBehavior or "hide") == "decrement",
          function()
            self:ApplyRuleMode("consume")
            self.draft.consumeBehavior = "decrement"
            if S and S.SetDirty then
              S:SetDirty(true)
            end
            self:RenderTab("Tracking")
          end
        )
        btnSpend:SetPoint("TOPLEFT", 268, -8)

        self.fieldWidgets[#self.fieldWidgets + 1] = quickModeFrame
        self.fieldWidgets[#self.fieldWidgets + 1] = btnGive
        self.fieldWidgets[#self.fieldWidgets + 1] = btnSpend
        y = y - 128

        local activeMode = (tostring(self.triggerEditMode or self.draft.actionMode or "produce") == "consume") and "consume" or "produce"
        self.triggerEditMode = activeMode
      end
    end

    local fields = tab.fields or {}
    local filtered = {}
    for i = 1, #fields do
      local key = fields[i].key
      if isCooldownTracking(self.draft) then
        if key == "unit" or key == "spellID" then
          filtered[#filtered + 1] = fields[i]
        end
      elseif isDirectAuraTracking(self.draft) then
        if key == "unit" or key == "spellID" then
          filtered[#filtered + 1] = fields[i]
        end
      elseif isEstimatedTargetTracking(self.draft) then
        if key == "unit" or key == "spellID" or key == "castSpellIDs" or key == "estimatedDuration" then
          filtered[#filtered + 1] = fields[i]
        end
      elseif not self.showAdvanced then
        local actionMode = tostring(self.triggerEditMode or self.draft.actionMode or "produce")
        if key == "unit" or key == "spellID" or (key == "castSpellIDs" and actionMode == "consume") then
          filtered[#filtered + 1] = fields[i]
      elseif actionMode == "produce" and (
          key == "duration"
          or key == "timerBehavior"
          or (key == "maxDuration" and tostring(self.draft.timerBehavior or "reset") == "extend")
        ) then
          filtered[#filtered + 1] = fields[i]
        elseif actionMode == "consume" and key ~= "consumeBehavior" then
          filtered[#filtered + 1] = fields[i]
        end
      else
        filtered[#filtered + 1] = fields[i]
      end
    end
    if not isCooldownTracking(self.draft) and not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) and not self.showAdvanced then
      y = self:RenderTrackingWorkflowCard(y, tab)
    else
      y = self:RenderTrackingDetailsCard(y, "Tracking Details", "Fine-tune the selected tracking mode.", filtered)
    end
  elseif tabKey == "Appearance" then
    local allFields = tab.fields or {}
    local byKey = {}
    for i = 1, #allFields do
      if allFields[i] then
        byKey[allFields[i].key] = allFields[i]
      end
    end
    local advancedTab = Schemas and Schemas:GetTab("Advanced") or nil
    if advancedTab and type(advancedTab.fields) == "table" then
      for i = 1, #advancedTab.fields do
        local field = advancedTab.fields[i]
        if field and not byKey[field.key] then
          byKey[field.key] = field
        end
      end
    end
    if byKey.group then
      byKey.group.minimalHelp = true
    end
    if byKey.barTexture then
      byKey.barTexture.minimalHelp = true
    end
    local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")

    y = self:RenderDisplayCanvas(y)
    y = self:RenderAppearanceFineTuneCard(y, mode)
    y = self:RenderStyleStudio(y)
    y = self:RenderVisualStateStudio(y)

    y = self:RenderAppearanceCard(y, "Structure", "Shape and placement.", {
      byKey.name,
      byKey.group,
      byKey.displayMode,
      (mode ~= "icon") and byKey.barSide or nil,
    })

    if tostring(self.draft.groupID or self.draft.group or "") ~= "" then
      y = self:RenderAppearanceCard(y, "Group", "Shared layout for grouped auras.", {
        byKey.groupName,
        byKey.groupDirection,
        byKey.groupSpacing,
        byKey.groupSort,
        byKey.groupWrapAfter,
        byKey.groupOffsetX,
        byKey.groupOffsetY,
      })
    end

    if mode == "icon" or mode == "iconbar" then
      local iconFields = { byKey.iconMode }
      if tostring(self.draft.iconMode or "spell") == "custom" and byKey.customTexture then
        iconFields[#iconFields + 1] = byKey.customTexture
      end
      iconFields[#iconFields + 1] = byKey.iconWidth
      iconFields[#iconFields + 1] = byKey.iconHeight
      y = self:RenderAppearanceCard(y, "Icon", "Icon sizing.", {
        unpack(iconFields),
      })
    end

    if mode == "bar" or mode == "iconbar" then
      local lookFields = {
        byKey.barColor,
        byKey.barGradientEnabled,
      }
      if self.draft.barGradientEnabled == true and byKey.barColor2 then
        lookFields[#lookFields + 1] = byKey.barColor2
      end
      lookFields[#lookFields + 1] = byKey.barTexture
      lookFields[#lookFields + 1] = byKey.lowTime
      y = self:RenderAppearanceLookCard(y, {
        unpack(lookFields),
      })
    end

    y = self:RenderTextControlsCard(y, {
      byKey.nameTextFont,
      byKey.timerTextFont,
      byKey.customText,
      byKey.customTextFont,
    })
    y = self:RenderAppearanceSoundCard(y, {
      byKey.soundOnShow,
      byKey.soundOnLow,
      byKey.soundOnExpire,
    })
  elseif tabKey == "Advanced" then
    local intro = addInfoBox(
      self.content,
      y,
      "Advanced settings",
      "Technical tuning, conditions, load rules and notes.",
      64
    )
    self.fieldWidgets[#self.fieldWidgets + 1] = intro
    y = y - 74

    if not isDirectAuraTracking(self.draft) and not isEstimatedTargetTracking(self.draft) and Widgets.ConditionTreeWidget and Widgets.ConditionTreeWidget.Create then
      self.conditionTree = Widgets.ConditionTreeWidget:Create(self.content, function()
        if S and S.SetDirty then
          S:SetDirty(true)
        end
        self:ValidateDraft()
        self:UpdateHeader()
      end)
      self.conditionTree.frame:SetPoint("TOPLEFT", 12, y)
      self.conditionTree.frame:SetPoint("RIGHT", -14, 0)
      self.conditionTree.frame:Show()
      self.conditionTree:SetDraft(self.draft)
      y = y - self.conditionTree.frame:GetHeight() - 10
    end

    local fields = tab.fields or {}
    local byKey = {}
    for i = 1, #fields do
      if fields[i] then
        byKey[fields[i].key] = fields[i]
      end
    end

    y = self:RenderLoadConditionsCard(y, byKey)

    local filtered = {}
    for i = 1, #fields do
      local key = fields[i].key
      local include = true
      if key == "loadClassToken" or key == "loadSpecID" then
        include = false
      end
      if isDirectAuraTracking(self.draft) or isEstimatedTargetTracking(self.draft) then
        if key == "conditionLogic" or key == "talentSpellIDs" or key == "requiredAuraSpellIDs" or key == "duration" or key == "ruleName" or key == "ruleID" then
          include = false
        end
      end
      if include then
        filtered[#filtered + 1] = fields[i]
      end
    end
    y = self:RenderGenericFields(filtered, y)
  end

  self.content:SetHeight(math.max(360, -y + 76))
  self.suspendFieldChanges = false
  self:ValidateDraft()
end

function AuraEditorPanel:SelectTab(tabKey)
  self:CommitProduceTriggerWidgets()
  if not isTabAvailable(self.draft, tabKey, self.showAdvanced) then
    return
  end
  if S and S.SetActiveTab then
    S:SetActiveTab(tabKey)
  end
  self:RenderTab(tabKey)
end

function AuraEditorPanel:DeleteCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local now = GetTime and GetTime() or 0
  if not self.deleteArmedUntil or self.deleteArmedUntil < now then
    self.deleteArmedUntil = now + 4
    if self.RefreshDeleteButton then
      self:RefreshDeleteButton()
    end
    V:SetStatus("warn", "Press Delete again to permanently remove this aura.")
    return
  end

  local deleted, err = Repo and Repo.DeleteAura and Repo:DeleteAura(self.draft.id)
  if not deleted then
    V:SetStatus("error", tostring(err or "Delete failed"))
    return
  end

  self.deleteArmedUntil = nil
  self.currentAuraId = nil
  self.draft = nil
  self:UpdateHeader()
  self:ClearTabContent()
  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if ns.state then
    ns.state.selectedAura = nil
    ns.state.selectedAuraPreviewItem = nil
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  if S and S.SetSelectedAura then
    S:SetSelectedAura(nil, "delete")
  end
  V:SetStatus("ok", "Aura deleted.")
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "delete", value = true })
  end
end

function AuraEditorPanel:DuplicateCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local ok, newId, err = Repo and Repo.DuplicateAura and Repo:DuplicateAura(self.draft.id)
  if not ok then
    V:SetStatus("error", tostring(err or "Duplicate failed"))
    return
  end

  if S and S.SetSelectedAura then
    S:SetSelectedAura(newId, "duplicate")
  end
  V:SetStatus("ok", "Aura duplicated.")
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "duplicate", value = newId })
  end
end

function AuraEditorPanel:ExportCurrent()
  if not self.draft or not self.draft.id or tostring(self.draft.id) == "" then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  local text, err = Repo and Repo.ExportAura and Repo:ExportAura(self.draft.id)
  if not text then
    V:SetStatus("error", tostring(err or "Export failed"))
    return
  end

  if UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowExport then
    UI.ImportExportDialog:ShowExport(
      "Export Aura",
      text,
      "This exports only the selected aura. Linked rules are included; the imported copy gets fresh local IDs."
    )
  end
  V:SetStatus("ok", "Aura export generated.")
end

function AuraEditorPanel:DiscardCurrent()
  if not self.draft then
    return
  end

  local currentId = tostring(self.currentAuraId or self.draft.id or "")
  if currentId ~= "" then
    self:LoadAura(currentId)
  else
    self.draft = Repo:CreateDraft()
    self.currentAuraId = self.draft and self.draft.id or nil
    self:UpdateHeader()
    self:RefreshTabButtons()
    self:RenderTab((S and S.Get and S:Get().activeTab) or "Tracking")
    self:ValidateDraft()
    self:RefreshLivePreview(true)
  end

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  self.deleteArmedUntil = nil
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  V:SetStatus("ok", "Unsaved changes discarded.")
end

function AuraEditorPanel:SaveCurrent()
  if not self.draft then
    return
  end

  self:CommitProduceTriggerWidgets()

  if tostring(self.triggerEditMode or self.draft.actionMode or "produce") == "produce" then
    syncProduceTriggersToDraft(self.draft)
  elseif tostring(self.draft.castSpellIDs or "") ~= "" then
    self.draft.consumeCastSpellIDs = tostring(self.draft.castSpellIDs or "")
  end

  if (not self.draft.id or tostring(self.draft.id) == "") and self.currentAuraId and tostring(self.currentAuraId) ~= "" then
    self.draft.id = tostring(self.currentAuraId)
    self.draft._sourceKey = tostring(self.currentAuraId)
  end

  local ruleDraft = (ns.Utils and ns.Utils.DeepCopy and ns.Utils.DeepCopy(self.draft)) or nil
  if type(ruleDraft) ~= "table" then
    ruleDraft = {}
    for key, value in pairs(self.draft) do
      ruleDraft[key] = value
    end
  end

  local ok, savedId, err = Repo:SaveDraft(self.draft)
  if not ok then
    V:SetStatus("error", tostring(err or "Save failed"))
    return
  end

  if savedId and tostring(savedId) ~= "" then
    ruleDraft.id = tostring(savedId)
    ruleDraft._sourceKey = tostring(savedId)
    if ns.SettingsData and ns.SettingsData.ResolveEntry then
      local savedEntry = ns.SettingsData:ResolveEntry(savedId)
      local savedUID = savedEntry and savedEntry.item and tostring(savedEntry.item.instanceUID or "") or ""
      if savedUID ~= "" then
        ruleDraft.instanceUID = savedUID
      end
    end
  end

  ruleDraft._produceTriggersDirty = false

  if RuleRepo and RuleRepo.SaveRuleFromDraft then
    local rok, rerr = RuleRepo:SaveRuleFromDraft(ruleDraft)
    if rok ~= true and rerr then
      V:Push("warn", "rule", tostring(rerr))
    end
  end

  if savedId and tostring(savedId) ~= "" then
    self.currentAuraId = tostring(savedId)
    local refreshedDraft = Repo:GetAuraDraft(savedId)
    if type(refreshedDraft) == "table" then
      self.draft = refreshedDraft
    else
      self.draft.id = tostring(savedId)
      self.draft._sourceKey = tostring(savedId)
      if ns.SettingsData and ns.SettingsData.ResolveEntry then
        local savedEntry = ns.SettingsData:ResolveEntry(savedId)
        local savedUID = savedEntry and savedEntry.item and tostring(savedEntry.item.instanceUID or "") or ""
        if savedUID ~= "" then
          self.draft.instanceUID = savedUID
        end
      end
    end
  else
    self.draft.id = savedId or self.draft.id
  end
  self.draft._produceTriggersDirty = false

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if S and S.SetSelectedAura and savedId then
    S:SetSelectedAura(savedId, "save")
  end

  self.deleteArmedUntil = nil
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  self:ValidateDraft()
  self:RefreshLivePreview(true)
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "save", value = savedId })
  end
end

function AuraEditorPanel:Create(parent)
  local o = setmetatable({}, self)
  o.fieldWidgets = {}
  o.currentTab = "Tracking"
  o.triggerEditMode = "produce"
  o.showAdvanced = false

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetAllPoints()
  createBackdrop(o.frame)

  o.eyebrow = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.eyebrow:SetPoint("TOPLEFT", 0, -2)
  o.eyebrow:SetText("SELECTED AURA")
  o.eyebrow:SetTextColor(0.66, 0.70, 0.76)

  o.titleText = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.titleText:SetPoint("TOPLEFT", 0, -14)
  o.titleText:SetText("Inspector")
  o.titleText:SetTextColor(0.96, 0.97, 0.99)

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 0, -28)
  o.subtitle:SetPoint("RIGHT", -112, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("")

  o.previewBanner = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  createCardBackdrop(o.previewBanner)
  o.previewBanner:SetPoint("TOPLEFT", 0, -46)
  o.previewBanner:SetPoint("RIGHT", -112, 0)
  o.previewBanner:SetHeight(34)

  o.previewBannerText = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.previewBannerText:SetPoint("TOPLEFT", 10, -6)
  o.previewBannerText:SetPoint("RIGHT", -100, 0)
  o.previewBannerText:SetJustifyH("LEFT")
  o.previewBannerText:SetText("No aura selected")
  o.previewBannerText:SetTextColor(0.95, 0.96, 0.98)

  o.previewBannerHint = o.previewBanner:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.previewBannerHint:SetPoint("TOPLEFT", 10, -19)
  o.previewBannerHint:SetPoint("RIGHT", -10, 0)
  o.previewBannerHint:SetJustifyH("LEFT")
  o.previewBannerHint:SetText("")
  o.previewBannerHint:Hide()
  o.previewBannerHint:SetTextColor(0.68, 0.72, 0.78)

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 0, -94)
  o.tabStrip:SetPoint("TOPRIGHT", -112, -94)
  o.tabStrip:SetHeight(24)

  o.tabStripLine = o.tabStrip:CreateTexture(nil, "ARTWORK")
  o.tabStripLine:SetColorTexture(1.0, 0.82, 0.18, 0.04)
  o.tabStripLine:SetPoint("BOTTOMLEFT", 0, 0)
  o.tabStripLine:SetPoint("BOTTOMRIGHT", 0, 0)
  o.tabStripLine:SetHeight(1)

  o.btnMode = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnMode:SetSize(96, 22)
  o.btnMode:SetPoint("TOPRIGHT", 0, -46)
  o.btnMode:SetText("Advanced")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnMode, "ghost")
  end
  o.btnMode:SetScript("OnClick", function()
    o.showAdvanced = not o.showAdvanced
    o.btnMode:SetText(o.showAdvanced and "Guided" or "Advanced")
    o:RefreshTabButtons()
    local activeTab = o.currentTab or "Tracking"
    if not isTabAvailable(o.draft, activeTab, o.showAdvanced) then
      activeTab = "Tracking"
      if S and S.SetActiveTab then
        S:SetActiveTab(activeTab)
      end
    end
    o:RenderTab(activeTab)
  end)

  o.tabs = {}
  local x = 0
  for i = 1, #(Schemas and Schemas.EditorTabs or {}) do
    local tab = Schemas.EditorTabs[i]
    local btn = CreateFrame("Button", nil, o.tabStrip, "UIPanelButtonTemplate")
    btn:SetSize(102, 22)
    btn:SetPoint("TOPLEFT", x, 0)
    btn:SetText(tab.label or tab.key)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "tab")
    end
    btn:SetScript("OnClick", function()
      o:SelectTab(tab.key)
    end)
    o.tabs[tab.key] = btn
    x = x + 110
  end

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame)
  o.scroll:SetPoint("TOPLEFT", 18, -122)
  o.scroll:SetPoint("BOTTOMRIGHT", -8, 40)
  o.scroll:EnableMouseWheel(true)

  o.content = CreateFrame("Frame", nil, o.scroll)
  o.content:SetSize(1, 1)
  o.scroll:SetScrollChild(o.content)
  o.scroll:SetScript("OnMouseWheel", function(selfScroll, delta)
    local current = selfScroll:GetVerticalScroll() or 0
    local maxScroll = math.max(0, (o.content:GetHeight() or 0) - (selfScroll:GetHeight() or 0))
    local nextScroll = math.max(0, math.min(maxScroll, current - (delta * 36)))
    selfScroll:SetVerticalScroll(nextScroll)
  end)
  o.scroll:SetScript("OnSizeChanged", function(selfScroll, width)
    local nextWidth = math.max(1, (width or 0) - 24)
    o.content:SetWidth(nextWidth)
    o.content.width = nextWidth
    if o.draft and not o._pendingLayoutRefresh then
      o._pendingLayoutRefresh = true
      C_Timer.After(0, function()
        if not o then
          return
        end
        o._pendingLayoutRefresh = false
        if o.draft then
          o:RenderTab(o.currentTab or "Tracking")
        end
      end)
    end
  end)

  o.footerLine = o.frame:CreateTexture(nil, "ARTWORK")
  o.footerLine:SetPoint("BOTTOMLEFT", 0, 48)
  o.footerLine:SetPoint("BOTTOMRIGHT", -12, 48)
  o.footerLine:SetHeight(1)
  o.footerLine:SetColorTexture(0.72, 0.78, 0.90, 0.10)

  o.actionBar = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  o.actionBar:SetPoint("BOTTOMLEFT", 0, 0)
  o.actionBar:SetPoint("BOTTOMRIGHT", -12, 0)
  o.actionBar:SetHeight(32)
  createCardBackdrop(o.actionBar)

  o.status = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.status:SetPoint("BOTTOMRIGHT", -12, 52)
  o.status:SetWidth(250)
  o.status:SetJustifyH("RIGHT")
  o.status:SetText("Ready")

  function o:RefreshDeleteButton()
    if not self.btnDelete then
      return
    end
    local now = GetTime and GetTime() or 0
    local armed = self.deleteArmedUntil and self.deleteArmedUntil >= now
    self.btnDelete:SetText(armed and "Confirm Delete" or "Delete")
  end

  o.btnSave = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSave:SetSize(98, 20)
  o.btnSave:SetParent(o.actionBar)
  o.btnSave:SetPoint("LEFT", 8, 0)
  o.btnSave:SetText("Save Aura")
  o.btnSave:SetScript("OnClick", function()
    o:SaveCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnSave, "primary")
  end

  o.btnReset = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnReset:SetSize(82, 20)
  o.btnReset:SetParent(o.actionBar)
  o.btnReset:SetPoint("LEFT", o.btnSave, "RIGHT", 8, 0)
  o.btnReset:SetText("Discard")
  o.btnReset:SetScript("OnClick", function()
    o:DiscardCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnReset, "ghost")
  end

  o.btnDuplicate = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnDuplicate:SetSize(84, 20)
  o.btnDuplicate:SetParent(o.actionBar)
  o.btnDuplicate:SetPoint("LEFT", o.btnReset, "RIGHT", 8, 0)
  o.btnDuplicate:SetText("Duplicate")
  o.btnDuplicate:SetScript("OnClick", function()
    o:DuplicateCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnDuplicate, "ghost")
  end
  o.duplicateButton = o.btnDuplicate

  o.btnExport = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnExport:SetSize(72, 20)
  o.btnExport:SetParent(o.actionBar)
  o.btnExport:SetPoint("LEFT", o.btnDuplicate, "RIGHT", 8, 0)
  o.btnExport:SetText("Export")
  o.btnExport:SetScript("OnClick", function()
    o:ExportCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnExport, "ghost")
  end

  o.btnDelete = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnDelete:SetSize(82, 20)
  o.btnDelete:SetParent(o.actionBar)
  o.btnDelete:SetPoint("LEFT", o.btnExport, "RIGHT", 8, 0)
  o.btnDelete:SetText("Delete")
  o.btnDelete:SetScript("OnClick", function()
    o:DeleteCurrent()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnDelete, "danger")
  end
  o:RefreshDeleteButton()

  if E then
    E:On(E.Names.AURA_SELECTED, function(payload)
      o:LoadAura(payload and payload.auraId or nil)
    end)

    E:On(E.Names.NEW_AURA, function()
      local draft = Repo:CreateDraft()
      if S and S.SetSelectedAura then
        S:SetSelectedAura(draft.id, "new")
      end
      o:LoadAura(draft.id)
      if S and S.SetDirty then
        S:SetDirty(true)
      end
    end)

    E:On(E.Names.STATE_CHANGED, function(state)
      if not state or not o.status then
        return
      end
      local dirty = state.dirty == true
      if dirty then
        o.status:SetTextColor(1.0, 0.84, 0.22)
        o.status:SetText("Unsaved changes")
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
        o.status:SetText("All changes saved")
      end
      o:UpdateHeader()
    end)
  end

  if V then
    V:Subscribe(function(snapshot)
      if not o.status then
        return
      end
      local status = snapshot and snapshot.status or "ok"
      local entries = snapshot and snapshot.entries or {}
      local msg = (#entries > 0 and entries[1].message) or "Ready"
      local dirty = S and S.Get and S:Get().dirty == true
      if status == "error" then
        o.status:SetTextColor(1, 0.35, 0.35)
        o.status:SetText(msg)
      elseif status == "warn" then
        o.status:SetTextColor(1, 0.82, 0.2)
        o.status:SetText(msg)
      elseif dirty then
        o.status:SetTextColor(1.0, 0.84, 0.22)
        o.status:SetText("Unsaved changes")
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
        o.status:SetText("All changes saved")
      end
    end)
  end

  C_Timer.After(0, function()
    if not o or not o.scroll or not o.content then
      return
    end
    local nextWidth = math.max(1, (o.scroll:GetWidth() or 0) - 24)
    o.content:SetWidth(nextWidth)
    o.content.width = nextWidth
    if o.draft then
      o:RenderTab(o.currentTab or "Tracking")
    end
  end)

  o:LoadAura(nil)
  return o
end

Panels.AuraEditorPanel = AuraEditorPanel


