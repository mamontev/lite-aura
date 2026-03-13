local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin

local ConfigFrame = {}
ConfigFrame.__index = ConfigFrame

local function refreshMoverButton(button)
  if not button then
    return
  end
  local moversOn = ns.db and ns.db.locked == false
  button:SetText(moversOn and "Movers: On" or "Movers: Off")
end

local function toggleMovers()
  if not ns.db then
    return
  end
  ns.db.locked = not (ns.db.locked == true)
  if ns.Dragger and ns.Dragger.SetLocked then
    ns.Dragger:SetLocked(ns.db.locked == true)
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
end

local function disableMovers()
  if not ns.db then
    return
  end
  if ns.db.locked ~= true then
    ns.db.locked = true
    if ns.Dragger and ns.Dragger.SetLocked then
      ns.Dragger:SetLocked(true)
    end
    if ns.EventRouter and ns.EventRouter.RefreshAll then
      ns.EventRouter:RefreshAll()
    end
  end
end

local function createPanelBackdrop(frame, r, g, b, a)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(r or 0.03, g or 0.09, b or 0.18, a or 0.90)
  frame:SetBackdropBorderColor(0.12, 0.50, 0.82, 0.95)
end

function ConfigFrame:BuildFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteConfigFrameV2", UIParent, "BackdropTemplate")
  frame:SetSize(1360, 760)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  createPanelBackdrop(frame, 0.02, 0.08, 0.17, 0.95)
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("AuraLite - Editor")
  title:SetTextColor(0.98, 0.86, 0.22)

  local sub = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  sub:SetPoint("TOPLEFT", 16, -30)
  sub:SetPoint("RIGHT", -220, 0)
  sub:SetJustifyH("LEFT")
  sub:SetText("Pick an aura on the left, use the simple guided setup in the center, and open more options only when you really need them.")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  if Skin and Skin.ApplyCloseButton then
    Skin:ApplyCloseButton(close)
  end

  local btnGlobal = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btnGlobal:SetSize(84, 22)
  btnGlobal:SetPoint("TOPRIGHT", -44, -30)
  btnGlobal:SetText("Global")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btnGlobal, "ghost")
  end

  local btnNew = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btnNew:SetSize(140, 22)
  btnNew:SetPoint("RIGHT", btnGlobal, "LEFT", -8, 0)
  btnNew:SetText("Quick New Aura")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btnNew, "primary")
  end

  local btnMovers = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btnMovers:SetSize(104, 22)
  btnMovers:SetPoint("RIGHT", btnNew, "LEFT", -8, 0)
  btnMovers:SetScript("OnClick", function(selfBtn)
    toggleMovers()
    refreshMoverButton(selfBtn)
  end)
  refreshMoverButton(btnMovers)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btnMovers, "default")
  end

  local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(260, 24)
  search:SetPoint("TOPLEFT", 16, -60)
  search:SetTextInsets(6, 6, 0, 0)
  search:SetText("")
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(search)
  end

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 2, 3)
  searchLabel:SetText("Search Auras")
  searchLabel:SetTextColor(0.92, 0.96, 1.0)

  local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  left:SetPoint("TOPLEFT", 12, -92)
  left:SetPoint("BOTTOMLEFT", 12, 12)
  left:SetWidth(350)
  createPanelBackdrop(left, 0.03, 0.10, 0.20, 0.75)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(left)
  end

  local center = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  center:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  center:SetPoint("BOTTOMLEFT", left, "BOTTOMRIGHT", 10, 0)
  center:SetWidth(700)
  createPanelBackdrop(center, 0.03, 0.11, 0.22, 0.75)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(center)
  end

  local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  right:SetPoint("TOPLEFT", center, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT", -12, 12)
  createPanelBackdrop(right, 0.02, 0.09, 0.18, 0.75)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(right)
  end

  local leftTitle = left:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  leftTitle:SetPoint("TOPLEFT", 10, -8)
  leftTitle:SetText("Aura Library")
  leftTitle:SetTextColor(0.94, 0.95, 1.0)

  local centerTitle = center:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  centerTitle:SetPoint("TOPLEFT", 10, -8)
  centerTitle:SetText("Configuration")
  centerTitle:SetTextColor(0.94, 0.95, 1.0)

  local rightTitle = right:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  rightTitle:SetPoint("TOPLEFT", 10, -8)
  rightTitle:SetText("Live Preview")
  rightTitle:SetTextColor(0.94, 0.95, 1.0)

  local listPanel = nil
  if Panels.AuraListPanel and Panels.AuraListPanel.Create then
    listPanel = Panels.AuraListPanel:Create(left)
    if listPanel and listPanel.frame then
      listPanel.frame:ClearAllPoints()
      listPanel.frame:SetPoint("TOPLEFT", left, "TOPLEFT", 6, -28)
      listPanel.frame:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -6, 6)
    end
    listPanel:BindSearchBox(search)
  end

  local editorPanel = nil
  if Panels.AuraEditorPanel and Panels.AuraEditorPanel.Create then
    editorPanel = Panels.AuraEditorPanel:Create(center)
    if editorPanel and editorPanel.frame then
      editorPanel.frame:ClearAllPoints()
      editorPanel.frame:SetPoint("TOPLEFT", center, "TOPLEFT", 6, -28)
      editorPanel.frame:SetPoint("BOTTOMRIGHT", center, "BOTTOMRIGHT", -6, 6)
    end
  end

  local previewPanel = nil
  if UI.Widgets and UI.Widgets.PreviewPanelWidget and UI.Widgets.PreviewPanelWidget.Create then
    previewPanel = UI.Widgets.PreviewPanelWidget:Create(right)
    if previewPanel and previewPanel.frame then
      previewPanel.frame:ClearAllPoints()
      previewPanel.frame:SetPoint("TOPLEFT", right, "TOPLEFT", 6, -28)
      previewPanel.frame:SetPoint("BOTTOMRIGHT", right, "BOTTOMRIGHT", -6, 6)
    end
  end

  local wizardPanel = nil
  if Panels.AuraWizard and Panels.AuraWizard.Create then
    wizardPanel = Panels.AuraWizard:Create(frame)
  end

  local globalPanel = nil
  if Panels.GlobalPanel and Panels.GlobalPanel.Create then
    globalPanel = Panels.GlobalPanel:Create(frame)
  end

  btnGlobal:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.OPEN_GLOBAL_PANEL, { anchor = btnGlobal })
    elseif globalPanel and globalPanel.frame then
      globalPanel.frame:SetShown(not globalPanel.frame:IsShown())
    end
  end)

  btnNew:SetScript("OnClick", function()
    if wizardPanel and wizardPanel.Open then
      wizardPanel:Open(btnNew)
      return
    end
    if E then
      E:Emit(E.Names.NEW_AURA, { source = "header_button" })
    end
  end)

  frame:SetScript("OnShow", function()
    refreshMoverButton(btnMovers)
  end)
  frame:SetScript("OnHide", function()
    disableMovers()
    refreshMoverButton(btnMovers)
  end)

  self.frame = frame
  self.title = title
  self.btnGlobal = btnGlobal
  self.btnNew = btnNew
  self.btnMovers = btnMovers
  self.searchBox = search
  self.leftPanel = left
  self.centerPanel = center
  self.rightPanel = right
  self.listPanel = listPanel
  self.editorPanel = editorPanel
  self.previewPanel = previewPanel
  self.globalPanel = globalPanel
  self.wizardPanel = wizardPanel
end

function ConfigFrame:Open()
  self:BuildFrame()
  self.frame:Show()
  self.frame:Raise()
end

function ConfigFrame:Close()
  if self.frame then
    self.frame:Hide()
  end
end

function ConfigFrame:Toggle()
  self:BuildFrame()
  self.frame:SetShown(not self.frame:IsShown())
  if self.frame:IsShown() then
    self.frame:Raise()
  end
end

function ConfigFrame:IsShown()
  return self.frame and self.frame:IsShown() or false
end

Panels.ConfigFrame = ConfigFrame
UI.ConfigFrame = ConfigFrame
