local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin
local Widgets = UI.Widgets or {}

local GlobalPanel = {}
GlobalPanel.__index = GlobalPanel

local function createBackdrop(frame)
  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.06, 0.14, 0.94)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.95)
end

local function applyFloatingWindowChrome(frame)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:Raise()
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)
end

local function attachDragHandle(frame, handle)
  if not frame or not handle then
    return
  end
  local dragHandle = handle
  if type(dragHandle) == "table" and dragHandle.frame and dragHandle.frame.GetObjectType then
    dragHandle = dragHandle.frame
  end
  if not (dragHandle and dragHandle.EnableMouse and dragHandle.RegisterForDrag and dragHandle.SetScript) then
    local proxy = CreateFrame("Frame", nil, frame)
    proxy:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, 0)
    proxy:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 0, 0)
    dragHandle = proxy
  end
  dragHandle:EnableMouse(true)
  dragHandle:RegisterForDrag("LeftButton")
  dragHandle:SetScript("OnDragStart", function()
    frame:Raise()
    frame:StartMoving()
  end)
  dragHandle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
end

local function makeButton(parent, text, w, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w or 150, 18)
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

  o.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  o.frame:SetSize(396, 278)
  applyFloatingWindowChrome(o.frame)
  createBackdrop(o.frame)
  o.frame:Hide()

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  o.title:SetPoint("TOPLEFT", 14, -16)
  o.title:SetText("Global Studio")
  o.title:SetTextColor(0.98, 0.88, 0.34)

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 14, -34)
  o.subtitle:SetPoint("RIGHT", -14, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("Launch interface settings, localization, import, and diagnostics from one place.")
  attachDragHandle(o.frame, o.title)
  attachDragHandle(o.frame, o.subtitle)

  if Widgets.SectionHeaderWidget and Widgets.SectionHeaderWidget.Create then
    o.header = Widgets.SectionHeaderWidget:Create(o.frame, {
      title = "Command Shelf",
      helpTitle = "Global Studio",
      helpBody = "Open the global AuraLite tools, interface settings, import flow, and debug toggles.",
      compact = true,
      lineWidth = 62,
    })
    o.header:SetPoint("TOPLEFT", 14, -58)
    o.header:SetPoint("TOPRIGHT", -14, -58)
    attachDragHandle(o.frame, o.header)
  end

  local body = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  if Skin and Skin.ApplyInsetPanel then
    Skin:ApplyInsetPanel(body)
  end
  body:SetPoint("TOPLEFT", 14, -86)
  body:SetPoint("TOPRIGHT", -14, -86)
  body:SetPoint("BOTTOMRIGHT", -14, 52)
  body:SetPoint("BOTTOMLEFT", 14, 52)

  local bodyText = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  bodyText:SetPoint("TOPLEFT", 12, -10)
  bodyText:SetPoint("RIGHT", -12, 0)
  bodyText:SetJustifyH("LEFT")
  bodyText:SetText("Quick launch tools for settings, localization, import, and diagnostics.")

  o.btnSettings = makeButton(body, "Interface Settings", 224, function()
    if ns.OptionsIntegration and ns.OptionsIntegration.OpenBlizzardCategory then
      ns.OptionsIntegration:OpenBlizzardCategory()
    elseif ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
      ns.UIV2.ConfigFrame:Open()
    end
    o.frame:Hide()
  end)
  o.btnSettings:SetSize(336, 28)
  o.btnSettings:SetPoint("TOPLEFT", 12, -38)

  o.btnLocalization = makeButton(body, "Localization", 224, function()
    if ns.SettingsUI and ns.SettingsUI.OpenLocalizationPanel then
      ns.SettingsUI:OpenLocalizationPanel()
    elseif ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
      ns.UIV2.ConfigFrame:Open()
    end
    o.frame:Hide()
  end)
  o.btnLocalization:SetSize(336, 28)
  o.btnLocalization:SetPoint("TOPLEFT", 12, -74)

  o.btnDebug = makeButton(body, "Toggle Debug", 224, function()
    if ns.Debug and ns.Debug.Toggle then
      ns.Debug:Toggle()
    end
  end)
  o.btnDebug:SetSize(336, 28)
  o.btnDebug:SetPoint("TOPLEFT", 12, -110)

  o.btnImport = makeButton(body, "Import String", 224, function()
    if E then
      E:Emit(E.Names.OPEN_IMPORT_PANEL, { anchor = o.btnImport })
    end
    o.frame:Hide()
  end)
  o.btnImport:SetSize(336, 28)
  o.btnImport:SetPoint("TOPLEFT", 12, -146)

  o.footer = CreateFrame("Frame", nil, o.frame)
  o.footer:SetPoint("BOTTOMLEFT", 14, 12)
  o.footer:SetPoint("BOTTOMRIGHT", -14, 12)
  o.footer:SetHeight(24)

  o.footerLine = o.footer:CreateTexture(nil, "ARTWORK")
  o.footerLine:SetPoint("TOPLEFT", 0, 0)
  o.footerLine:SetPoint("TOPRIGHT", 0, 0)
  o.footerLine:SetHeight(1)
  o.footerLine:SetColorTexture(1.0, 0.82, 0.18, 0.18)

  o.footerHint = o.footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.footerHint:SetPoint("LEFT", 0, -6)
  o.footerHint:SetText("Quick launch panel for tools that sit outside the main inspector.")

  o.btnClose = makeButton(o.footer, "Close", 88, function()
    o.frame:Hide()
  end)
  o.btnClose:SetPoint("RIGHT", 0, -6)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.btnClose, "ghost")
  end

  if E then
    E:On(E.Names.OPEN_GLOBAL_PANEL, function(payload)
      o.frame:ClearAllPoints()
      o.frame:SetPoint("CENTER", UIParent, "CENTER", -120, 52)
      o.frame:Raise()
      o.frame:SetShown(not o.frame:IsShown())
    end)
  end

  return o
end

Panels.GlobalPanel = GlobalPanel
UI.GlobalPanel = GlobalPanel
