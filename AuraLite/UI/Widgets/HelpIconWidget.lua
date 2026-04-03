local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local Widgets = ns.UIV2.Widgets

local HelpIconWidget = {}
HelpIconWidget.__index = HelpIconWidget

function HelpIconWidget:Create(parent, options)
  options = type(options) == "table" and options or {}

  local button = CreateFrame("Button", nil, parent)
  button:SetSize(14, 14)

  button.bg = button:CreateTexture(nil, "BACKGROUND")
  button.bg:SetAllPoints()
  button.bg:SetColorTexture(0.12, 0.11, 0.09, 0.92)

  button.border = button:CreateTexture(nil, "BORDER")
  button.border:SetPoint("TOPLEFT", 0, 0)
  button.border:SetPoint("BOTTOMRIGHT", 0, 0)
  button.border:SetColorTexture(0.72, 0.60, 0.24, 0.82)

  button.text = button:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  button.text:SetPoint("CENTER", 0, -1)
  button.text:SetText("?")
  button.text:SetTextColor(0.98, 0.88, 0.34)

  button.tooltipTitle = tostring(options.title or "")
  button.tooltipBody = tostring(options.body or "")

  button:SetScript("OnEnter", function(self)
    self.bg:SetColorTexture(0.18, 0.15, 0.10, 0.98)
    if GameTooltip then
      GameTooltip:SetOwner(self, options.anchor or "ANCHOR_RIGHT")
      if self.tooltipTitle ~= "" then
        GameTooltip:SetText(self.tooltipTitle, 1.0, 0.86, 0.30)
      end
      if self.tooltipBody ~= "" then
        GameTooltip:AddLine(self.tooltipBody, 0.92, 0.94, 0.96, true)
      end
      GameTooltip:Show()
    end
  end)

  button:SetScript("OnLeave", function(self)
    self.bg:SetColorTexture(0.12, 0.11, 0.09, 0.92)
    if GameTooltip then
      GameTooltip:Hide()
    end
  end)

  return button
end

Widgets.HelpIconWidget = HelpIconWidget
