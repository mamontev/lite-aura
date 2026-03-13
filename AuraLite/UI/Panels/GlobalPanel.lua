local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin

local GlobalPanel = {}
GlobalPanel.__index = GlobalPanel

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.06, 0.14, 0.94)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.95)
end

local function makeButton(parent, text, w, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w or 150, 22)
  btn:SetText(text)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, "default")
  end
  btn:SetScript("OnClick", function()
    if onClick then
      onClick()
    end
  end)
  return btn
end

function GlobalPanel:Create(parent)
  local o = setmetatable({}, self)

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetSize(240, 150)
  o.frame:SetFrameStrata("DIALOG")
  o.frame:SetToplevel(true)
  createBackdrop(o.frame)
  o.frame:Hide()

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("Global")

  o.btnSettings = makeButton(o.frame, "Open Interface Options", 210, function()
    if ns.OptionsIntegration and ns.OptionsIntegration.OpenBlizzardCategory then
      ns.OptionsIntegration:OpenBlizzardCategory()
    elseif ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
      ns.UIV2.ConfigFrame:Open()
    end
    o.frame:Hide()
  end)
  o.btnSettings:SetPoint("TOPLEFT", 14, -30)

  o.btnLocalization = makeButton(o.frame, "Localization", 210, function()
    if ns.SettingsUI and ns.SettingsUI.OpenLocalizationPanel then
      ns.SettingsUI:OpenLocalizationPanel()
    elseif ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
      ns.UIV2.ConfigFrame:Open()
    end
    o.frame:Hide()
  end)
  o.btnLocalization:SetPoint("TOPLEFT", 14, -58)

  o.btnDebug = makeButton(o.frame, "Toggle Debug", 210, function()
    if ns.Debug and ns.Debug.Toggle then
      ns.Debug:Toggle()
    end
  end)
  o.btnDebug:SetPoint("TOPLEFT", 14, -86)

  o.btnClose = makeButton(o.frame, "Close", 210, function()
    o.frame:Hide()
  end)
  o.btnClose:SetPoint("TOPLEFT", 14, -114)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnClose, "ghost")
  end

  if E then
    E:On(E.Names.OPEN_GLOBAL_PANEL, function(payload)
      local anchor = payload and payload.anchor
      if anchor then
        o.frame:ClearAllPoints()
        o.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
      end
      o.frame:SetShown(not o.frame:IsShown())
    end)
  end

  return o
end

Panels.GlobalPanel = GlobalPanel
UI.GlobalPanel = GlobalPanel
