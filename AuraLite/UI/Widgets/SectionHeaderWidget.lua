local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local Widgets = ns.UIV2.Widgets
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local WIDGET_TYPE = "AuraLiteSectionHeader"
local WIDGET_VERSION = 1

local function getClassAccent()
  local _, classToken = UnitClass and UnitClass("player") or nil
  local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil
  if color then
    return color.r or 1.0, color.g or 0.82, color.b or 0.18
  end
  return 1.0, 0.82, 0.18
end

local function applyOptions(widget, options)
  options = type(options) == "table" and options or {}
  local frame = widget.frame
  local cr, cg, cb = getClassAccent()
  local compact = options.compact == true

  frame:SetHeight(compact and 24 or 38)
  frame.bg:SetColorTexture(0.10, 0.11, 0.13, compact and 0.22 or 0.30)
  frame.bottomLine:SetColorTexture(cr, cg, cb, compact and 0.10 or 0.16)

  widget.title:SetFontObject(compact and "GameFontNormalSmall" or "GameFontNormal")
  widget.title:SetPoint("TOPLEFT", 12, compact and -5 or -6)
  widget.title:SetPoint("RIGHT", -34, 0)
  widget.title:SetText(tostring(options.title or "Section"))
  widget.title:SetTextColor(compact and 0.90 or 0.94, compact and 0.93 or 0.95, compact and 0.98 or 0.99)

  if compact then
    widget.subtitle:Hide()
    widget.subtitle:SetText("")
  else
    widget.subtitle:SetPoint("TOPLEFT", widget.title, "BOTTOMLEFT", 0, -3)
    widget.subtitle:SetPoint("RIGHT", frame, "RIGHT", -34, 0)
    widget.subtitle:SetJustifyH("LEFT")
    widget.subtitle:SetText(tostring(options.subtitle or ""))
    widget.subtitle:Show()
  end

  widget._options = options
  widget._collapsed = options.collapsed == true

  if widget.help then
    widget.help:SetShown((options.helpTitle or options.helpBody) and true or false)
    if widget.help.tooltipTitle ~= nil then
      widget.help.tooltipTitle = tostring(options.helpTitle or "")
      widget.help.tooltipBody = tostring(options.helpBody or "")
    end
  end

  if options.collapsible then
    widget.toggle:Show()
    widget.toggle.text:SetText(widget._collapsed and "+" or "-")
    widget.toggle:SetPoint("RIGHT", widget.help or frame, (options.helpTitle or options.helpBody) and "LEFT" or "RIGHT", (options.helpTitle or options.helpBody) and -6 or -8, 0)
  else
    widget.toggle:Hide()
  end
end

if AceGUI and (AceGUI:GetWidgetVersion(WIDGET_TYPE) or 0) < WIDGET_VERSION then
  local methods = {
    OnAcquire = function(self)
      applyOptions(self, {})
      self.frame:Show()
    end,

    OnRelease = function(self)
      self._options = nil
      self._collapsed = false
      self.frame:ClearAllPoints()
      self.frame:SetParent(UIParent)
    end,

    SetOptions = function(self, options)
      applyOptions(self, options)
    end,

    SetCollapsed = function(self, collapsed)
      self._collapsed = collapsed == true
      if self.toggle then
        self.toggle.text:SetText(self._collapsed and "+" or "-")
      end
    end,
  }

  local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(20)

    frame.bg = frame:CreateTexture(nil, "BACKGROUND")
    frame.bg:SetAllPoints()
    frame.bg:SetTexture("Interface\\Buttons\\WHITE8x8")

    frame.bottomLine = frame:CreateTexture(nil, "ARTWORK")
    frame.bottomLine:SetPoint("BOTTOMLEFT", 0, 0)
    frame.bottomLine:SetPoint("BOTTOMRIGHT", 0, 0)
    frame.bottomLine:SetHeight(1)

    local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    title:SetJustifyH("LEFT")

    local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    subtitle:SetJustifyH("LEFT")

    local help = nil
    if Widgets.HelpIconWidget and Widgets.HelpIconWidget.Create then
      help = Widgets.HelpIconWidget:Create(frame, {})
      help:SetPoint("RIGHT", -2, 0)
      help:Hide()
    end

    local toggle = CreateFrame("Button", nil, frame)
    toggle:SetSize(18, 18)
    toggle.bg = toggle:CreateTexture(nil, "BACKGROUND")
    toggle.bg:SetAllPoints()
    toggle.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    toggle.bg:SetColorTexture(0.16, 0.17, 0.20, 0.72)
    toggle.text = toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    toggle.text:SetPoint("CENTER", 0, 0)
    toggle.text:SetTextColor(1.0, 0.82, 0.18)
    toggle:SetScript("OnEnter", function(selfBtn)
      selfBtn.bg:SetColorTexture(0.20, 0.22, 0.26, 0.84)
      selfBtn.text:SetTextColor(1.0, 0.90, 0.40)
    end)
    toggle:SetScript("OnLeave", function(selfBtn)
      selfBtn.bg:SetColorTexture(0.16, 0.17, 0.20, 0.72)
      selfBtn.text:SetTextColor(1.0, 0.82, 0.18)
    end)

    local widget = {
      type = WIDGET_TYPE,
      frame = frame,
      title = title,
      subtitle = subtitle,
      help = help,
      toggle = toggle,
      _options = {},
      _collapsed = false,
    }

    toggle:SetScript("OnClick", function()
      widget._collapsed = not widget._collapsed
      widget.toggle.text:SetText(widget._collapsed and "+" or "-")
      if widget._options and type(widget._options.onToggle) == "function" then
        widget._options.onToggle(not widget._collapsed)
      end
    end)

    for method, func in pairs(methods) do
      widget[method] = func
    end

    frame.obj = widget
    return AceGUI:RegisterAsWidget(widget)
  end

  AceGUI:RegisterWidgetType(WIDGET_TYPE, Constructor, WIDGET_VERSION)
end

local SectionHeaderWidget = {}
SectionHeaderWidget.__index = SectionHeaderWidget

function SectionHeaderWidget:Create(parent, options)
  options = type(options) == "table" and options or {}

  if AceGUI then
    local widget = AceGUI:Create(WIDGET_TYPE)
    widget:SetOptions(options)
    widget.frame:SetParent(parent)
    widget.frame._aceWidget = widget
    widget.frame.title = widget.title
    widget.frame.subtitle = widget.subtitle
    widget.frame.help = widget.help
    widget.frame.toggle = widget.toggle
    widget.frame.SetCollapsed = function(frame, collapsed)
      if frame._aceWidget then
        frame._aceWidget:SetCollapsed(collapsed)
      end
    end
    return widget.frame
  end

  local frame = CreateFrame("Frame", nil, parent)
  frame:SetHeight(options.compact and 24 or 38)
  local cr, cg, cb = getClassAccent()

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetAllPoints()
  frame.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
  frame.bg:SetColorTexture(0.10, 0.11, 0.13, options.compact and 0.22 or 0.30)

  frame.bottomLine = frame:CreateTexture(nil, "ARTWORK")
  frame.bottomLine:SetColorTexture(cr, cg, cb, options.compact and 0.10 or 0.16)
  frame.bottomLine:SetPoint("BOTTOMLEFT", 0, 0)
  frame.bottomLine:SetPoint("BOTTOMRIGHT", 0, 0)
  frame.bottomLine:SetHeight(1)

  frame.title = frame:CreateFontString(nil, "OVERLAY", options.compact and "GameFontNormalSmall" or "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 12, options.compact and -5 or -6)
  frame.title:SetPoint("RIGHT", -34, 0)
  frame.title:SetJustifyH("LEFT")
  frame.title:SetText(tostring(options.title or "Section"))
  frame.title:SetTextColor(options.compact and 0.90 or 0.94, options.compact and 0.93 or 0.95, options.compact and 0.98 or 0.99)

  if not options.compact then
    frame.subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    frame.subtitle:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -3)
    frame.subtitle:SetPoint("RIGHT", frame, "RIGHT", -34, 0)
    frame.subtitle:SetJustifyH("LEFT")
    frame.subtitle:SetText(tostring(options.subtitle or ""))
  end

  if options.helpTitle or options.helpBody then
    local helpFactory = Widgets.HelpIconWidget
    if helpFactory and helpFactory.Create then
      frame.help = helpFactory:Create(frame, {
        title = options.helpTitle,
        body = options.helpBody,
      })
      frame.help:SetPoint("RIGHT", -2, 0)
    end
  end

  if options.collapsible then
    frame.toggle = CreateFrame("Button", nil, frame)
    frame.toggle:SetSize(18, 18)
    frame.toggle:SetPoint("RIGHT", frame.help or frame, options.helpBody and "LEFT" or "RIGHT", options.helpBody and -6 or -8, 0)
    frame.toggle.bg = frame.toggle:CreateTexture(nil, "BACKGROUND")
    frame.toggle.bg:SetAllPoints()
    frame.toggle.bg:SetTexture("Interface\\Buttons\\WHITE8x8")
    frame.toggle.bg:SetColorTexture(0.16, 0.17, 0.20, 0.72)
    frame.toggle.text = frame.toggle:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.toggle.text:SetPoint("CENTER", 0, 0)
    frame.toggle.text:SetText(options.collapsed and "+" or "-")
    frame.toggle.text:SetTextColor(1.0, 0.82, 0.18)
    frame.toggle:SetScript("OnClick", function()
      if type(options.onToggle) == "function" then
        options.onToggle(not options.collapsed)
      end
    end)
    frame.toggle:SetScript("OnEnter", function(selfBtn)
      if selfBtn.bg then
        selfBtn.bg:SetColorTexture(0.20, 0.22, 0.26, 0.84)
      end
      if selfBtn.text then
        selfBtn.text:SetTextColor(1.0, 0.90, 0.40)
      end
    end)
    frame.toggle:SetScript("OnLeave", function(selfBtn)
      if selfBtn.bg then
        selfBtn.bg:SetColorTexture(0.16, 0.17, 0.20, 0.72)
      end
      if selfBtn.text then
        selfBtn.text:SetTextColor(1.0, 0.82, 0.18)
      end
    end)
  end

  function frame:SetCollapsed(collapsed)
    options.collapsed = collapsed == true
    if self.toggle then
      self.toggle.text:SetText(options.collapsed and "+" or "-")
    end
  end

  return frame
end

Widgets.SectionHeaderWidget = SectionHeaderWidget
