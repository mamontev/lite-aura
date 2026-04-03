local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local Widgets = ns.UIV2.Widgets
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local WIDGET_TYPE = "AuraLiteDropTarget"
local WIDGET_VERSION = 1

local function getCursorPayload()
  local cursorType, cursorID, _, cursorSpellID = GetCursorInfo()
  if cursorType == "spell" and cursorSpellID then
    return "spell", tonumber(cursorSpellID)
  end
  if cursorType == "petaction" and cursorID then
    return "spell", tonumber(cursorID)
  end
  if cursorType == "item" and cursorID then
    return "item", tonumber(cursorID)
  end
  return nil, nil
end

local function setTooltip(frame)
  if not frame or not GameTooltip then
    return
  end
  local kind, id = getCursorPayload()
  if not kind or not id then
    return
  end

  GameTooltip:SetOwner(frame, "ANCHOR_CURSOR")
  if kind == "spell" then
    local spellName = GetSpellInfo and GetSpellInfo(id) or nil
    GameTooltip:AddLine("Track spell", 1.0, 0.82, 0.18)
    GameTooltip:AddLine(spellName or ("Spell " .. tostring(id)), 0.94, 0.96, 0.98)
    GameTooltip:AddLine("Drop to build a new aura draft from this spell.", 0.70, 0.74, 0.80, true)
  elseif kind == "item" then
    local itemName = C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(id) or nil
    GameTooltip:AddLine("Track item spell", 1.0, 0.82, 0.18)
    GameTooltip:AddLine(itemName or ("Item " .. tostring(id)), 0.94, 0.96, 0.98)
    GameTooltip:AddLine("Drop to build a new aura draft from this item.", 0.70, 0.74, 0.80, true)
  end
  GameTooltip:Show()
end

local function hideTooltip()
  if GameTooltip then
    GameTooltip:Hide()
  end
end

local function setState(widget, state)
  local frame = widget and widget.frame
  if not frame or not frame.bg then
    return
  end
  if state == "armed" then
    frame.bg:SetColorTexture(0.10, 0.18, 0.26, 0.96)
    frame.border:SetColorTexture(0.38, 0.78, 1.0, 0.98)
    frame.accent:SetColorTexture(1.0, 0.82, 0.18, 0.85)
  elseif state == "hover" then
    frame.bg:SetColorTexture(0.08, 0.14, 0.22, 0.88)
    frame.border:SetColorTexture(0.28, 0.60, 0.86, 0.90)
    frame.accent:SetColorTexture(1.0, 0.82, 0.18, 0.65)
  else
    frame.bg:SetColorTexture(0.05, 0.09, 0.16, 0.78)
    frame.border:SetColorTexture(0.18, 0.40, 0.66, 0.74)
    frame.accent:SetColorTexture(1.0, 0.82, 0.18, 0.40)
  end
end

if AceGUI and (AceGUI:GetWidgetVersion(WIDGET_TYPE) or 0) < WIDGET_VERSION then
  local function Button_OnEnter(frame)
    local kind = getCursorPayload()
    setState(frame.obj, kind and "armed" or "hover")
    setTooltip(frame)
  end

  local function Button_OnLeave(frame)
    setState(frame.obj, "normal")
    hideTooltip()
  end

  local function Button_Receive(frame)
    local widget = frame.obj
    local kind, id = getCursorPayload()
    if kind and id and type(widget.onPayload) == "function" then
      widget.onPayload(kind, id)
      ClearCursor()
    end
    setState(widget, "normal")
    hideTooltip()
  end

  local methods = {
    OnAcquire = function(self)
      self:SetHeight(54)
      self:SetTitle("Drop a spell here")
      self:SetSubtitle("AuraLite will build a starting draft from the game data.")
      self:SetOnPayload(nil)
      setState(self, "normal")
      self.frame:Show()
    end,

    OnRelease = function(self)
      self.onPayload = nil
      self.frame:ClearAllPoints()
      self.frame:SetParent(UIParent)
      setState(self, "normal")
    end,

    SetTitle = function(self, text)
      self.title:SetText(tostring(text or ""))
    end,

    SetSubtitle = function(self, text)
      self.subtitle:SetText(tostring(text or ""))
    end,

    SetOnPayload = function(self, fn)
      self.onPayload = fn
    end,
  }

  local function Constructor()
    local frame = CreateFrame("Button", nil, UIParent)
    frame:SetHeight(54)
    frame:RegisterForDrag("LeftButton")
    frame:EnableMouse(true)
    frame:SetScript("OnEnter", Button_OnEnter)
    frame:SetScript("OnLeave", Button_OnLeave)
    frame:SetScript("OnReceiveDrag", Button_Receive)
    frame:SetScript("OnMouseUp", Button_Receive)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()

    frame.border = frame:CreateTexture(nil, "BORDER")
    frame.border:SetPoint("TOPLEFT", 0, 0)
    frame.border:SetPoint("BOTTOMRIGHT", 0, 0)

    frame.accent = frame:CreateTexture(nil, "ARTWORK")
    frame.accent:SetPoint("TOPLEFT", 1, -1)
    frame.accent:SetPoint("TOPRIGHT", -1, -1)
    frame.accent:SetHeight(1)

    local icon = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    icon:SetPoint("LEFT", 10, 0)
    icon:SetText("+")
    icon:SetTextColor(1.0, 0.82, 0.18)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    title:SetPoint("TOPLEFT", 28, -7)
    title:SetPoint("RIGHT", -12, 0)
    title:SetJustifyH("LEFT")
    title:SetWordWrap(false)

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -2)
    subtitle:SetPoint("RIGHT", -12, 0)
    subtitle:SetJustifyH("LEFT")
    subtitle:SetJustifyV("TOP")
    subtitle:SetWordWrap(true)

    local widget = {
      type = WIDGET_TYPE,
      frame = frame,
      icon = icon,
      title = title,
      subtitle = subtitle,
      onPayload = nil,
    }

    for method, func in pairs(methods) do
      widget[method] = func
    end

    frame.obj = widget
    return AceGUI:RegisterAsWidget(widget)
  end

  AceGUI:RegisterWidgetType(WIDGET_TYPE, Constructor, WIDGET_VERSION)
end

local DropTargetWidget = {}
DropTargetWidget.__index = DropTargetWidget

function DropTargetWidget:Create(parent, options)
  options = type(options) == "table" and options or {}
  local subtitleText = tostring(options.subtitle or "")

  if AceGUI then
    local widget = AceGUI:Create(WIDGET_TYPE)
    widget.frame:SetParent(parent)
    widget:SetHeight(options.height or 42)
    widget:SetTitle(options.title or "Drop a spell here")
    widget:SetSubtitle(subtitleText)
    widget:SetOnPayload(options.onPayload)
    widget.frame._aceWidget = widget
    widget.frame.SetTitle = function(frame, text)
      if frame._aceWidget then
        frame._aceWidget:SetTitle(text)
      end
    end
    widget.frame.SetSubtitle = function(frame, text)
      if frame._aceWidget then
        frame._aceWidget:SetSubtitle(text)
      end
    end
    widget.frame.SetOnPayload = function(frame, fn)
      if frame._aceWidget then
        frame._aceWidget:SetOnPayload(fn)
      end
    end
    return widget.frame
  end

  local frame = CreateFrame("Button", nil, parent, "BackdropTemplate")
  frame:SetHeight(options.height or 54)
  frame:RegisterForDrag("LeftButton")
  frame:EnableMouse(true)

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()

  frame.border = frame:CreateTexture(nil, "BORDER")
  frame.border:SetPoint("TOPLEFT", 0, 0)
  frame.border:SetPoint("BOTTOMRIGHT", 0, 0)

  frame.accent = frame:CreateTexture(nil, "ARTWORK")
  frame.accent:SetPoint("TOPLEFT", 1, -1)
  frame.accent:SetPoint("TOPRIGHT", -1, -1)
  frame.accent:SetHeight(1)

  frame.icon = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.icon:SetPoint("LEFT", 10, 0)
  frame.icon:SetText("+")
  frame.icon:SetTextColor(1.0, 0.82, 0.18)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.title:SetPoint("TOPLEFT", 28, -7)
  frame.title:SetPoint("RIGHT", -12, 0)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetWordWrap(false)
  frame.title:SetText(tostring(options.title or "Drop a spell here"))

  frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  if subtitleText ~= "" then
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -2)
    frame.subtitle:SetPoint("RIGHT", -12, 0)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetJustifyV("TOP")
    frame.subtitle:SetWordWrap(true)
    frame.subtitle:SetText(subtitleText)
    frame.subtitle:Show()
  else
    frame.subtitle:SetText("")
    frame.subtitle:Hide()
  end

  frame._alOnPayload = options.onPayload
  frame:SetScript("OnEnter", function(self)
    local kind = getCursorPayload()
    setState({ frame = self }, kind and "armed" or "hover")
    setTooltip(self)
  end)
  frame:SetScript("OnLeave", function(self)
    setState({ frame = self }, "normal")
    hideTooltip()
  end)
  frame:SetScript("OnReceiveDrag", function(self)
    local kind, id = getCursorPayload()
    if kind and id and type(self._alOnPayload) == "function" then
      self._alOnPayload(kind, id)
      ClearCursor()
    end
    setState({ frame = self }, "normal")
    hideTooltip()
  end)
  frame:SetScript("OnMouseUp", frame:GetScript("OnReceiveDrag"))
  setState({ frame = frame }, "normal")

  function frame:SetTitle(text)
    self.title:SetText(tostring(text or ""))
  end

  function frame:SetSubtitle(text)
    self.subtitle:SetText(tostring(text or ""))
  end

  function frame:SetOnPayload(fn)
    self._alOnPayload = fn
  end

  return frame
end

Widgets.DropTargetWidget = DropTargetWidget
