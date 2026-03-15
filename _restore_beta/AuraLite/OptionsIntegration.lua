local _, ns = ...

ns.OptionsIntegration = ns.OptionsIntegration or {}
local O = ns.OptionsIntegration

function O:OpenConfig()
  if ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
    ns.UIV2.ConfigFrame:Open()
    return true
  end
  return false
end

function O:OpenBlizzardCategory()
  if Settings and Settings.OpenToCategory and self.category and self.category.GetID then
    Settings.OpenToCategory(self.category:GetID())
    return true
  end

  if InterfaceOptionsFrame_OpenToCategory and self.legacyPanel then
    InterfaceOptionsFrame_OpenToCategory(self.legacyPanel)
    InterfaceOptionsFrame_OpenToCategory(self.legacyPanel)
    return true
  end

  return false
end

local function buildCategoryPanel()
  local panel = CreateFrame("Frame")
  panel.name = "AuraLite"

  local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("AuraLite")

  local subtitle = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetWidth(620)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("WeakAuras Light style tracker for selected buffs/debuffs. Use this page to open the full AuraLite configuration panel.")

  local openConfig = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  openConfig:SetSize(220, 26)
  openConfig:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -18)
  openConfig:SetText("Open AuraLite Config")
  openConfig:SetScript("OnClick", function()
    O:OpenConfig()
  end)

  local openSlash = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
  openSlash:SetPoint("TOPLEFT", openConfig, "BOTTOMLEFT", 0, -10)
  openSlash:SetText("Shortcut: /al config")

  local unlockBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  unlockBtn:SetSize(220, 24)
  unlockBtn:SetPoint("TOPLEFT", openSlash, "BOTTOMLEFT", 0, -12)
  unlockBtn:SetText("Toggle Lock/Unlock Drag")
  unlockBtn:SetScript("OnClick", function()
    if ns.db then
      ns.Dragger:SetLocked(not ns.db.locked)
      ns.EventRouter:RefreshAll()
    end
  end)

  local editBtn = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  editBtn:SetSize(220, 24)
  editBtn:SetPoint("TOPLEFT", unlockBtn, "BOTTOMLEFT", 0, -8)
  editBtn:SetText("Toggle Edit Mode")
  editBtn:SetScript("OnClick", function()
    ns.TestMode:SetEnabled(not ns.TestMode:IsEnabled())
    ns.EventRouter:RefreshAll()
  end)

  return panel
end

function O:Register()
  if self.registered then
    return
  end

  local panel = buildCategoryPanel()
  self.panel = panel

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, panel, "AuraLite")
    if ok and category then
      Settings.RegisterAddOnCategory(category)
      self.category = category
      self.registered = true
      return
    end
  end

  if InterfaceOptions_AddCategory then
    InterfaceOptions_AddCategory(panel)
    self.legacyPanel = panel
  end

  self.registered = true
end
