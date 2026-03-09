local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events

local ConfigFrame = {}
ConfigFrame.__index = ConfigFrame

local function createPanelBackdrop(frame, r, g, b, a)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(r or 0.03, g or 0.05, b or 0.08, a or 0.92)
  frame:SetBackdropBorderColor(0.08, 0.4, 0.7, 0.9)
end

function ConfigFrame:BuildFrame()
  if self.frame then
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteConfigFrameV2", UIParent, "BackdropTemplate")
  frame:SetSize(1120, 680)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  createPanelBackdrop(frame)
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -10)
  title:SetText("AuraLite v2")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)

  local headerLine = frame:CreateTexture(nil, "ARTWORK")
  headerLine:SetColorTexture(0.15, 0.45, 0.75, 0.7)
  headerLine:SetPoint("TOPLEFT", 10, -36)
  headerLine:SetPoint("TOPRIGHT", -10, -36)
  headerLine:SetHeight(1)

  local btnGlobal = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btnGlobal:SetSize(84, 22)
  btnGlobal:SetPoint("TOPLEFT", 14, -46)
  btnGlobal:SetText("Global")

  local btnNew = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  btnNew:SetSize(92, 22)
  btnNew:SetPoint("LEFT", btnGlobal, "RIGHT", 8, 0)
  btnNew:SetText("New Aura")

  local search = CreateFrame("EditBox", nil, frame, "InputBoxTemplate")
  search:SetAutoFocus(false)
  search:SetSize(260, 24)
  search:SetPoint("TOPRIGHT", -40, -46)
  search:SetTextInsets(6, 6, 0, 0)
  search:SetText("")

  local searchLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  searchLabel:SetPoint("BOTTOMLEFT", search, "TOPLEFT", 2, 3)
  searchLabel:SetText("Search")

  local left = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  left:SetPoint("TOPLEFT", 12, -80)
  left:SetPoint("BOTTOMLEFT", 12, 12)
  left:SetWidth(360)
  createPanelBackdrop(left, 0.02, 0.05, 0.1, 0.72)

  local right = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  right:SetPoint("TOPLEFT", left, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT", -12, 12)
  createPanelBackdrop(right, 0.03, 0.06, 0.12, 0.72)

  local globalPopup = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  globalPopup:SetSize(220, 150)
  globalPopup:SetPoint("TOPLEFT", btnGlobal, "BOTTOMLEFT", 0, -8)
  createPanelBackdrop(globalPopup, 0.02, 0.04, 0.08, 0.95)
  globalPopup:Hide()

  local gpTitle = globalPopup:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  gpTitle:SetPoint("TOPLEFT", 10, -10)
  gpTitle:SetText("Global Actions")

  local gpHint = globalPopup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  gpHint:SetPoint("TOPLEFT", 10, -36)
  gpHint:SetJustifyH("LEFT")
  gpHint:SetText("Settings, Localization, Debug,\nRefresh and Unlock Drag\nwill move here in next milestones.")

  btnGlobal:SetScript("OnClick", function()
    globalPopup:SetShown(not globalPopup:IsShown())
  end)

  btnNew:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.NEW_AURA, { source = "header_button" })
    end
  end)

  local listPanel = nil
  if Panels.AuraListPanel and Panels.AuraListPanel.Create then
    listPanel = Panels.AuraListPanel:Create(left)
    listPanel:BindSearchBox(search)
  end

  local editorPanel = nil
  if Panels.AuraEditorPanel and Panels.AuraEditorPanel.Create then
    editorPanel = Panels.AuraEditorPanel:Create(right)
  end

  self.frame = frame
  self.title = title
  self.btnGlobal = btnGlobal
  self.btnNew = btnNew
  self.searchBox = search
  self.leftPanel = left
  self.rightPanel = right
  self.globalPopup = globalPopup
  self.listPanel = listPanel
  self.editorPanel = editorPanel
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
