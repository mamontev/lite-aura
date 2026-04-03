local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin
local Widgets = UI.Widgets or {}
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local ConfigFrame = {}
ConfigFrame.__index = ConfigFrame

local function getClassAccent()
  local _, classToken = UnitClass and UnitClass("player") or nil
  local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil
  if color then
    return color.r or 0.94, color.g or 0.78, color.b or 0.18
  end
  return 0.94, 0.78, 0.18
end

local function refreshMoverButton(button)
  if not button then
    return
  end
  local moversOn = ns.db and ns.db.locked == false
  button:SetText(moversOn and "Movers On" or "Movers Off")
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

local function areMoversEnabled()
  return ns.db and ns.db.locked == false
end

local function buildDraftFromSpell(spellID, sourceKind, sourceID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return false
  end

  local repo = UI and UI.AuraRepository
  if not repo or not repo.CreateDraft or not repo.SaveDraft then
    return false
  end

  local spellName = (ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID)) or ("Spell " .. tostring(spellID))
  local draft = repo:CreateDraft()
  draft.name = tostring(spellName or "New Aura")
  draft.displayName = tostring(spellName or "New Aura")
  draft.spellID = spellID
  draft.spellInput = tostring(spellID)
  draft.unit = "player"
  draft.trackingMode = "confirmed"
  draft.triggerType = "cast"
  draft.actionMode = "produce"
  draft.castSpellIDs = tostring(spellID)
  draft.stackAmount = tonumber(draft.stackAmount) or 1
  draft.produceTriggers = {
    {
      spellID = spellID,
      stackAmount = draft.stackAmount,
    },
  }
  draft.timerVisual = "icon"
  draft.stylePreset = draft.stylePreset ~= "" and draft.stylePreset or "compact_tracker"
  draft.group = ""
  draft.groupID = ""
  draft.customText = (sourceKind == "item" and sourceID and C_Item and C_Item.GetItemNameByID) and tostring(C_Item.GetItemNameByID(sourceID) or "") or tostring(draft.customText or "")

  local ok, savedId = repo:SaveDraft(draft)
  if not ok or not savedId then
    return false
  end

  if UI and UI.State and UI.State.SetSelectedAura then
    UI.State:SetSelectedAura(savedId, "drop_create")
  end
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "drop_create", value = savedId })
  end
  return true
end

local function handleCursorPayload(kind, id)
  if kind == "spell" then
    return buildDraftFromSpell(id, kind, id)
  end

  if kind == "item" and C_Item and C_Item.GetItemSpell then
    local _, itemSpellID = C_Item.GetItemSpell(id)
    if itemSpellID then
      return buildDraftFromSpell(itemSpellID, kind, id)
    end
  end

  if ns and ns.Print then
    ns:Print("AuraLite: this drag payload is not trackable yet.")
  else
    print("AuraLite: this drag payload is not trackable yet.")
  end
  return false
end

local function applyPanelBackdrop(frame, bgAlpha)
  if not frame then
    return
  end

  local target = frame
  if type(frame.SetBackdrop) ~= "function" then
    if not frame._alBackdropHost then
      local host = CreateFrame("Frame", nil, frame, "BackdropTemplate")
      host:SetPoint("TOPLEFT", 0, 0)
      host:SetPoint("BOTTOMRIGHT", 0, 0)
      host:SetFrameLevel(math.max(0, (frame:GetFrameLevel() or 1) - 1))
      frame._alBackdropHost = host
    end
    target = frame._alBackdropHost
  end

  target:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  target:SetBackdropColor(0.070, 0.074, 0.082, bgAlpha or 0.56)
  target:SetBackdropBorderColor(0.13, 0.14, 0.16, 0.52)

  if not target._alFill then
    target._alFill = target:CreateTexture(nil, "BACKGROUND")
    target._alFill:SetPoint("TOPLEFT", 1, -1)
    target._alFill:SetPoint("BOTTOMRIGHT", -1, 1)
    target._alFill:SetTexture("Interface\\Buttons\\WHITE8x8")
    target._alFill:SetVertexColor(1, 1, 1, 0.02)
  end

  if not target._alAccent then
    target._alAccent = target:CreateTexture(nil, "ARTWORK")
    target._alAccent:SetPoint("TOPLEFT", 10, -10)
    target._alAccent:SetPoint("TOPRIGHT", -10, -10)
    target._alAccent:SetHeight(1)
    target._alAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  do
    local r, g, b = getClassAccent()
    target._alAccent:SetColorTexture(r, g, b, 0.10)
  end

  if not target._alEdgeGlow then
    target._alEdgeGlow = target:CreateTexture(nil, "BACKGROUND", nil, 2)
    target._alEdgeGlow:SetPoint("TOPLEFT", 1, -1)
    target._alEdgeGlow:SetPoint("BOTTOMRIGHT", -1, 1)
    target._alEdgeGlow:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
    target._alEdgeGlow:SetVertexColor(0.01, 0.01, 0.01, 0.06)
end

local function createToolbarButton(parent, text, width, variant)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width, 20)
  btn:SetText(text)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, variant or "ghost")
  end
  return btn
end

local function createColumnCard(parent, titleText, subtitleText, width)
  local card
  if AceGUI then
    local group = AceGUI:Create("SimpleGroup")
    group:SetLayout("Manual")
    group.frame:SetParent(parent)
    group.frame:ClearAllPoints()
    card = group.frame
    card._aceWidget = group
    card:SetFrameLevel(parent:GetFrameLevel() + 1)
    card:SetScript("OnSizeChanged", function(selfFrame, nextWidth, nextHeight)
      if selfFrame._alSyncingAceSize then
        return
      end
      selfFrame._alSyncingAceSize = true
      if selfFrame._aceWidget then
        if nextWidth and nextWidth > 0 then
          selfFrame._aceWidget:SetWidth(nextWidth)
        end
        if nextHeight and nextHeight > 0 then
          selfFrame._aceWidget:SetHeight(nextHeight)
        end
      end
      selfFrame._alSyncingAceSize = false
    end)
  else
    card = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  end
  card:SetWidth(width)
  applyPanelBackdrop(card, 0.90)
  if card._aceWidget and width and width > 0 then
    card._aceWidget:SetWidth(width)
  end

  card.header = CreateFrame("Frame", nil, card)
  card.header:SetPoint("TOPLEFT", 0, 0)
  card.header:SetPoint("TOPRIGHT", 0, 0)
  local hasSubtitle = tostring(subtitleText or "") ~= ""
  card.header:SetHeight(hasSubtitle and 44 or 36)

  card.headerShade = card.header:CreateTexture(nil, "BACKGROUND")
  card.headerShade:SetAllPoints()
  card.headerShade:SetTexture("Interface\\Buttons\\WHITE8x8")
  card.headerShade:SetVertexColor(1, 1, 1, 0.004)

  card.title = card.header:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  if hasSubtitle then
    card.title:SetPoint("TOPLEFT", 14, -10)
  else
    card.title:SetPoint("TOPLEFT", 14, -2)
    card.title:SetPoint("BOTTOMRIGHT", -30, 2)
    card.title:SetJustifyV("MIDDLE")
  end
  card.title:SetText(titleText or "")
  card.title:SetTextColor(0.90, 0.93, 0.97)

  card.subtitle = card.header:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  if hasSubtitle then
    card.subtitle:SetPoint("TOPLEFT", card.title, "BOTTOMLEFT", 0, -2)
    card.subtitle:SetPoint("RIGHT", -28, 0)
    card.subtitle:SetJustifyH("LEFT")
    card.subtitle:SetText(subtitleText or "")
    card.subtitle:Show()
  else
    card.subtitle:SetText("")
    card.subtitle:Hide()
  end

  if Widgets.HelpIconWidget and Widgets.HelpIconWidget.Create then
    card.help = Widgets.HelpIconWidget:Create(card.header, {
      title = titleText or "",
      body = subtitleText or "",
    })
    if hasSubtitle then
      card.help:SetPoint("TOPRIGHT", -12, -10)
    else
      card.help:SetPoint("RIGHT", -12, 0)
    end
  end

  card.headerLine = card.header:CreateTexture(nil, "ARTWORK")
  card.headerLine:SetPoint("BOTTOMLEFT", 12, 0)
  card.headerLine:SetPoint("BOTTOMRIGHT", -12, 0)
  card.headerLine:SetHeight(1)
  do
    local r, g, b = getClassAccent()
    card.headerLine:SetColorTexture(r, g, b, 0.08)
  end

  local contentHost = (card._aceWidget and card._aceWidget.content) or card
  card.content = CreateFrame("Frame", nil, contentHost)
  card.content:SetPoint("TOPLEFT", 10, hasSubtitle and -48 or -42)
  card.content:SetPoint("BOTTOMRIGHT", -10, 10)

  return card
end

local function buildWarningSummary()
  local repo = UI and UI.AuraRepository
  if not (repo and repo.ListAuras) then
    return "No warnings detected.", 0
  end

  local rows = repo:ListAuras((UI.State and UI.State.Get and UI.State:Get()) or nil) or {}
  local warns = 0
  for i = 1, #rows do
    local row = rows[i]
    if row.isLoaded ~= false and tostring(row.status or "ok") ~= "ok" then
      warns = warns + 1
    end
  end

  if warns == 0 then
    return "No warnings detected. Your tracked auras look healthy.", 0
  end

  return tostring(warns) .. " need attention", warns
end

local function buildWarningsReport()
  local sections = {}
  local total = 0

  local validation = UI and UI.ValidationBus and UI.ValidationBus.GetSnapshot and UI.ValidationBus:GetSnapshot() or { entries = {} }
  if validation and type(validation.entries) == "table" and #validation.entries > 0 then
    sections[#sections + 1] = "Selected aura"
    for i = 1, #validation.entries do
      local entry = validation.entries[i]
      sections[#sections + 1] = string.format("- [%s] %s", tostring(entry.severity or "warn"):upper(), tostring(entry.message or ""))
      total = total + 1
    end
  end

  local repo = UI and UI.AuraRepository
  if repo and repo.ListAuras then
    local rows = repo:ListAuras((UI.State and UI.State.Get and UI.State:Get()) or nil) or {}
    local runtimeIssues = {}
    for i = 1, #rows do
      local row = rows[i]
      if row.isLoaded ~= false and tostring(row.status or "ok") ~= "ok" then
        runtimeIssues[#runtimeIssues + 1] = string.format("- [CHECK] %s needs attention.", tostring(row.name or "Aura"))
      end
    end
    if #runtimeIssues > 0 then
      if #sections > 0 then
        sections[#sections + 1] = ""
      end
      sections[#sections + 1] = "Repository"
      for i = 1, #runtimeIssues do
        sections[#sections + 1] = runtimeIssues[i]
        total = total + 1
      end
    end
  end

  if total == 0 then
    return "No warnings right now.\n\nYour selected aura and repository look healthy.", 0
  end
  return table.concat(sections, "\n"), total
end

function ConfigFrame:BuildFrame()
  if self.frame then
    return
  end

  local frameWidget = nil
  local frame = nil
  if AceGUI then
    frameWidget = AceGUI:Create("Frame")
    frameWidget:SetTitle("")
    frameWidget:SetStatusText("")
    frameWidget:EnableResize(false)
    frame = frameWidget.frame
    frame:SetSize(1640, 880)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    if frameWidget.titlebg then
      frameWidget.titlebg:Hide()
    end
    if frameWidget.titletext then
      frameWidget.titletext:Hide()
    end
    if frameWidget.statustext and frameWidget.statustext.GetParent then
      frameWidget.statustext:GetParent():Hide()
    end
    for _, child in ipairs({ frame:GetChildren() }) do
      if child:GetObjectType() == "Button" and child:GetText() == CLOSE then
        child:Hide()
        child:SetScript("OnShow", child.Hide)
      end
    end
  else
    frame = CreateFrame("Frame", "AuraLiteConfigFrameV2", UIParent, "BackdropTemplate")
    frame:SetSize(1640, 880)
    frame:SetPoint("CENTER", 0, 10)
    frame:SetFrameStrata("DIALOG")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  end
  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
  else
    applyPanelBackdrop(frame, 0.96)
  end
  frame:Hide()

  frame._alVignette = frame:CreateTexture(nil, "BACKGROUND")
  frame._alVignette:SetAllPoints()
  frame._alVignette:SetTexture("Interface\\Buttons\\WHITE8x8")
  frame._alVignette:SetVertexColor(0.02, 0.018, 0.014, 0.10)

  local topBar = CreateFrame("Frame", nil, frame, "BackdropTemplate")
  topBar:SetPoint("TOPLEFT", 0, 0)
  topBar:SetPoint("TOPRIGHT", 0, 0)
  topBar:SetHeight(52)
  topBar:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  topBar:SetBackdropColor(0.05, 0.055, 0.062, 0.16)
  topBar:SetBackdropBorderColor(0, 0, 0, 0)

  local topLine = topBar:CreateTexture(nil, "ARTWORK")
  topLine:SetPoint("BOTTOMLEFT", 12, 0)
  topLine:SetPoint("BOTTOMRIGHT", -12, 0)
  topLine:SetHeight(1)
  do
    local r, g, b = getClassAccent()
    topLine:SetColorTexture(r, g, b, 0.10)
  end

  local studioTag = topBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  studioTag:SetPoint("LEFT", 18, 0)
  studioTag:SetText("AURALITE STUDIO")
  studioTag:SetTextColor(0.72, 0.77, 0.84)

  local title = topBar:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("CENTER", 0, 0)
  title:SetText("AuraLite")
  title:SetTextColor(0.96, 0.97, 0.99)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -8)
  if Skin and Skin.ApplyCloseButton then
    Skin:ApplyCloseButton(close)
  end
  close:SetScript("OnClick", function()
    if self:ShouldUseCompactMoverFrame() then
      self:EnterMoverMode()
      return
    end
    self:Close()
  end)

  local btnGlobal = createToolbarButton(topBar, "Global", 70, "ghost")
  btnGlobal:SetPoint("RIGHT", topBar, "RIGHT", -46, 0)

  local btnWarnings = createToolbarButton(topBar, "Warnings", 108, "ghost")
  btnWarnings:SetPoint("RIGHT", btnGlobal, "LEFT", -8, 0)

  local btnExport = createToolbarButton(topBar, "Export", 76, "ghost")
  btnExport:SetPoint("RIGHT", btnWarnings, "LEFT", -8, 0)

  local btnImport = createToolbarButton(topBar, "Import", 76, "ghost")
  btnImport:SetPoint("RIGHT", btnExport, "LEFT", -8, 0)

  local btnGroups = createToolbarButton(topBar, "Groups", 72, "ghost")
  btnGroups:SetPoint("RIGHT", btnImport, "LEFT", -8, 0)

  local btnNew = createToolbarButton(topBar, "New Aura", 108, "primary")
  btnNew:SetPoint("RIGHT", btnGroups, "LEFT", -8, 0)

  local btnMovers = createToolbarButton(topBar, "Movers Off", 92, "default")
  btnMovers:SetPoint("RIGHT", btnNew, "LEFT", -8, 0)
  btnMovers:SetScript("OnClick", function(selfBtn)
    if areMoversEnabled() then
      self:EnterMoverMode()
    else
      self:EnableMoversFromStudio()
    end
    refreshMoverButton(selfBtn)
  end)
  refreshMoverButton(btnMovers)

  local content = CreateFrame("Frame", nil, frame)
  content:SetPoint("TOPLEFT", 12, -58)
  content:SetPoint("BOTTOMRIGHT", -12, 12)

  local groupsColumn = createColumnCard(content, "Groups", "", 252)
  groupsColumn:SetPoint("TOPLEFT", 0, 0)
  groupsColumn:SetPoint("BOTTOMLEFT", 0, 0)

  local listColumn = createColumnCard(content, "Spells / Auras", "", 340)
  listColumn:SetPoint("TOPLEFT", groupsColumn, "TOPRIGHT", 10, 0)
  listColumn:SetPoint("BOTTOMLEFT", groupsColumn, "BOTTOMRIGHT", 10, 0)

  local center = createColumnCard(content, "Configuration", "", 676)
  center:SetPoint("TOPLEFT", listColumn, "TOPRIGHT", 10, 0)
  center:SetPoint("BOTTOMLEFT", listColumn, "BOTTOMRIGHT", 10, 0)

  local right = createColumnCard(content, "Live Preview", "", 0)
  right:SetPoint("TOPLEFT", center, "TOPRIGHT", 10, 0)
  right:SetPoint("BOTTOMRIGHT", 0, 0)
  right:SetPoint("BOTTOMLEFT", center, "BOTTOMRIGHT", 10, 0)

  local warningsText = topBar:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  warningsText:SetPoint("LEFT", studioTag, "RIGHT", 14, 0)
  warningsText:SetPoint("RIGHT", btnMovers, "LEFT", -10, 0)
  warningsText:SetJustifyH("LEFT")
  warningsText:SetWordWrap(false)

  local warningsHint = "Tip: drag auras into groups, or use Export to share the selected aura."

  local search = CreateFrame("EditBox", nil, listColumn.content, "InputBoxTemplate")
  search:SetAutoFocus(false)
  search:SetHeight(22)
  search:SetPoint("TOPLEFT", 0, 0)
  search:SetPoint("TOPRIGHT", 0, 0)
  search:SetTextInsets(8, 8, 0, 0)
  search:SetText("")
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(search)
  end

  local dropTarget = nil
  if Widgets.DropTargetWidget and Widgets.DropTargetWidget.Create then
    dropTarget = Widgets.DropTargetWidget:Create(listColumn.content, {
      title = "Drop a spell or item here",
      subtitle = "",
      height = 54,
      onPayload = function(kind, id)
        handleCursorPayload(kind, id)
      end,
    })
    dropTarget:SetPoint("TOPLEFT", 0, -30)
    dropTarget:SetPoint("RIGHT", 0, 0)
  end

  local groupBrowser = nil
  if UI.Widgets and UI.Widgets.GroupBrowserWidget and UI.Widgets.GroupBrowserWidget.Create then
    groupBrowser = UI.Widgets.GroupBrowserWidget:Create(groupsColumn.content)
    if groupBrowser and groupBrowser.frame then
      groupBrowser.frame:ClearAllPoints()
      groupBrowser.frame:SetPoint("TOPLEFT", 0, 0)
      groupBrowser.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    end
  end

  local listPanel = nil
  if Panels.AuraListPanel and Panels.AuraListPanel.Create then
    listPanel = Panels.AuraListPanel:Create(listColumn.content)
    if listPanel and listPanel.frame then
      listPanel.frame:ClearAllPoints()
      listPanel.frame:SetPoint("TOPLEFT", 0, -84)
      listPanel.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    end
    listPanel:BindSearchBox(search)
  end

  local editorPanel = nil
  if Panels.AuraEditorPanel and Panels.AuraEditorPanel.Create then
    editorPanel = Panels.AuraEditorPanel:Create(center.content)
    if editorPanel and editorPanel.frame then
      editorPanel.frame:ClearAllPoints()
      editorPanel.frame:SetPoint("TOPLEFT", 0, 0)
      editorPanel.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    end
  end

  local previewPanel = nil
  if UI.Widgets and UI.Widgets.PreviewPanelWidget and UI.Widgets.PreviewPanelWidget.Create then
    previewPanel = UI.Widgets.PreviewPanelWidget:Create(right.content)
    if previewPanel and previewPanel.frame then
      previewPanel.frame:ClearAllPoints()
      previewPanel.frame:SetPoint("TOPLEFT", 0, 0)
      previewPanel.frame:SetPoint("BOTTOMRIGHT", 0, 0)
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

  local importPanel = nil
  if Panels.ImportPanel and Panels.ImportPanel.Create then
    importPanel = Panels.ImportPanel:Create(frame)
  end

  local groupsPanel = nil
  if Panels.GroupsPanel and Panels.GroupsPanel.Create then
    groupsPanel = Panels.GroupsPanel:Create(frame)
  end

  btnGlobal:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.OPEN_GLOBAL_PANEL, { anchor = btnGlobal })
    elseif globalPanel and globalPanel.frame then
      globalPanel.frame:SetShown(not globalPanel.frame:IsShown())
    end
  end)

  btnWarnings:SetScript("OnClick", function()
    self:ToggleWarningsPanel()
  end)

  btnImport:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.OPEN_IMPORT_PANEL, { anchor = btnImport })
    elseif importPanel and importPanel.OpenImport then
      importPanel:OpenImport()
    end
  end)

  btnGroups:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.OPEN_GROUPS_PANEL, { anchor = btnGroups })
    elseif groupsPanel and groupsPanel.frame then
      groupsPanel.frame:SetShown(not groupsPanel.frame:IsShown())
    end
  end)

  btnExport:SetScript("OnClick", function()
    self:OpenQuickExport()
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
    self:RefreshWarningsSummary()
    if self.compactMoverFrame then
      self.compactMoverFrame:Hide()
    end
  end)
  frame:SetScript("OnHide", function()
    if self._suspendDisableMoversOnHide then
      self._suspendDisableMoversOnHide = nil
    else
      disableMovers()
      if self.compactMoverFrame then
        self.compactMoverFrame:Hide()
      end
    end
    if ns and ns.state then
      ns.state.selectedAuraPreviewItem = nil
    end
    refreshMoverButton(btnMovers)
  end)

  self.frame = frame
  self.frameWidget = frameWidget
  self.title = title
  self.btnGlobal = btnGlobal
  self.btnWarnings = btnWarnings
  self.btnImport = btnImport
  self.btnExport = btnExport
  self.btnGroups = btnGroups
  self.btnNew = btnNew
  self.btnMovers = btnMovers
  self.searchBox = search
  self.dropTarget = dropTarget
  self.groupsColumn = groupsColumn
  self.listColumn = listColumn
  self.centerPanel = center
  self.rightPanel = right
  self.groupsPanelEmbedded = groupBrowser
  self.listPanel = listPanel
  self.editorPanel = editorPanel
  self.previewPanel = previewPanel
  self.warningsText = warningsText
  self.warningsHint = warningsHint
  self.globalPanel = globalPanel
  self.importPanel = importPanel
  self.groupsPanel = groupsPanel
  self.wizardPanel = wizardPanel

  if E and E.On then
    E:On(E.Names.STATE_CHANGED, function()
      if self.frame and self.frame:IsShown() then
        self:RefreshWarningsSummary()
      end
    end)
    E:On(E.Names.FILTER_CHANGED, function()
      if self.frame and self.frame:IsShown() then
        self:RefreshWarningsSummary()
      end
    end)
    E:On(E.Names.VALIDATION_CHANGED, function()
      if self.frame and self.frame:IsShown() then
        self:RefreshWarningsSummary()
      end
    end)
  end
end

function ConfigFrame:RefreshWarningsSummary()
  if not self.warningsText then
    return
  end
  local text, count = buildWarningSummary()
  self.warningsText:SetText(text)
  if self.warningsHint then
    if tonumber(count) > 0 then
      self.warningsText:SetText(text .. " | Open Group Studio or export the selected item for review.")
    else
      self.warningsText:SetText("No warnings detected. " .. tostring(self.warningsHint))
    end
  end
  if self.btnWarnings then
    local _, count = buildWarningSummary()
    self.btnWarnings:SetText((tonumber(count) or 0) > 0 and ("Warnings (" .. tostring(count) .. ")") or "Warnings")
  end
  if self.warningsPanel and self.warningsPanel:IsShown() then
    self:RefreshWarningsPanel()
  end
end

function ConfigFrame:BuildWarningsPanel()
  if self.warningsPanel then
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteWarningsPanel", UIParent, "BackdropTemplate")
  frame:SetSize(420, 280)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
  else
    applyPanelBackdrop(frame, 0.94)
  end
  frame:Hide()

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Warnings")
  title:SetTextColor(0.96, 0.97, 0.99)

  local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetPoint("TOPRIGHT", -34, 0)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Review validation issues for the selected aura and repository-wide load problems.")

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -6)
  if Skin and Skin.ApplyCloseButton then
    Skin:ApplyCloseButton(close)
  end
  close:SetScript("OnClick", function()
    frame:Hide()
  end)

  local scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 14, -54)
  scroll:SetPoint("BOTTOMRIGHT", -30, 14)

  local child = CreateFrame("Frame", nil, scroll)
  child:SetSize(360, 1)
  scroll:SetScrollChild(child)

  local text = child:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  text:SetPoint("TOPLEFT", 0, 0)
  text:SetPoint("RIGHT", 0, 0)
  text:SetJustifyH("LEFT")
  text:SetJustifyV("TOP")
  text:SetWordWrap(true)
  text:SetTextColor(0.84, 0.87, 0.92)

  scroll:SetScript("OnSizeChanged", function(selfScroll, width)
    local nextWidth = math.max(120, (tonumber(width) or 0) - 24)
    child:SetWidth(nextWidth)
    text:SetWidth(nextWidth)
  end)

  self.warningsPanel = frame
  self.warningsPanelText = text
  self.warningsPanelChild = child
  self.warningsPanelScroll = scroll
end

function ConfigFrame:RefreshWarningsPanel()
  self:BuildWarningsPanel()
  local text, count = buildWarningsReport()
  local panelWidth = self.warningsPanelScroll and self.warningsPanelScroll:GetWidth() or 360
  local contentWidth = math.max(120, panelWidth - 24)
  self.warningsPanelChild:SetWidth(contentWidth)
  self.warningsPanelText:SetWidth(contentWidth)
  self.warningsPanelText:SetText(text)
  local height = math.max(220, math.ceil(self.warningsPanelText:GetStringHeight() or 0) + 8)
  self.warningsPanelChild:SetHeight(height)
  if self.btnWarnings then
    self.btnWarnings:SetText((tonumber(count) or 0) > 0 and ("Warnings (" .. tostring(count) .. ")") or "Warnings")
  end
end

function ConfigFrame:ToggleWarningsPanel()
  self:BuildWarningsPanel()
  self:RefreshWarningsPanel()
  if self.warningsPanel:IsShown() then
    self.warningsPanel:Hide()
    return
  end
  self.warningsPanel:ClearAllPoints()
  if self.frame and self.frame:IsShown() then
    self.warningsPanel:SetPoint("TOPLEFT", self.frame, "TOPRIGHT", 8, -8)
  else
    self.warningsPanel:SetPoint("CENTER", UIParent, "CENTER", 320, 40)
  end
  self.warningsPanel:Show()
  self.warningsPanel:Raise()
end

function ConfigFrame:OpenQuickExport()
  local auraId = UI and UI.State and UI.State.Get and UI.State:Get().selectedAuraId or nil
  if auraId and auraId ~= "" and UI and UI.AuraRepository and UI.AuraRepository.ExportAura then
    local text = UI.AuraRepository:ExportAura(auraId)
    if text and UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowExport then
      UI.ImportExportDialog:ShowExport(
        "Export Aura",
        text,
        "This exports only the currently selected aura."
      )
      return
    end
  end

  local groupID = self.groupsPanel and self.groupsPanel.selectedGroupID or nil
  if groupID and groupID ~= "" and ns.ImportExport and ns.ImportExport.ExportGroupString then
    local text = ns.ImportExport:ExportGroupString(groupID)
    if text and UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowExport then
      UI.ImportExportDialog:ShowExport(
        "Export Group",
        text,
        "This exports the selected group and all of its member auras."
      )
      return
    end
  end

  if ns and ns.Print then
    ns:Print("AuraLite: select an aura to export it, or open Group Studio and select a group.")
  end
end

function ConfigFrame:BuildCompactMoverFrame()
  if self.compactMoverFrame then
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteMoversCompactFrame", UIParent, "BackdropTemplate")
  frame:SetSize(268, 122)
  frame:SetPoint("TOP", UIParent, "TOP", 0, -120)
  frame:SetFrameStrata("DIALOG")
  frame:SetMovable(true)
  frame:SetClampedToScreen(false)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
  else
    applyPanelBackdrop(frame, 0.94)
  end

  local title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 14, -12)
  title:SetText("Movers Active")
  title:SetTextColor(0.96, 0.97, 0.99)

  local subtitle = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -4)
  subtitle:SetPoint("TOPRIGHT", -14, 0)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Move your auras, then lock them or reopen the studio.")

  local btnSnap = createToolbarButton(frame, "Snap: Off", 74, "ghost")
  btnSnap:SetPoint("BOTTOMLEFT", 14, 44)
  btnSnap:SetScript("OnClick", function(selfBtn)
    self:CycleMoverSnap()
    selfBtn:SetText(self:GetMoverSnapButtonText())
  end)

  local btnReset = createToolbarButton(frame, "Reset Visible", 92, "ghost")
  btnReset:SetPoint("LEFT", btnSnap, "RIGHT", 8, 0)
  btnReset:SetScript("OnClick", function()
    self:ResetVisibleMoverPositions()
  end)

  local btnLock = createToolbarButton(frame, "Lock and Close", 116, "primary")
  btnLock:SetPoint("BOTTOMLEFT", 14, 14)
  btnLock:SetScript("OnClick", function()
    self:DisableMoversAndHideCompact()
  end)

  local btnReopen = createToolbarButton(frame, "Reopen Studio", 116, "ghost")
  btnReopen:SetPoint("LEFT", btnLock, "RIGHT", 8, 0)
  btnReopen:SetScript("OnClick", function()
    self:ReopenStudioWhileMoving()
  end)

  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -6)
  if Skin and Skin.ApplyCloseButton then
    Skin:ApplyCloseButton(close)
  end
  close:SetScript("OnClick", function()
    self:DisableMoversAndHideCompact()
  end)

  self.compactMoverFrame = frame
  self.compactMoverTitle = title
  self.compactMoverSubtitle = subtitle
  self.compactMoverSnapButton = btnSnap
  self.compactMoverResetButton = btnReset
  self.compactMoverLockButton = btnLock
  self.compactMoverReopenButton = btnReopen
end

function ConfigFrame:ShouldUseCompactMoverFrame()
  return areMoversEnabled() and self.frame and self.frame:IsShown()
end

function ConfigFrame:GetMoverSnapButtonText()
  local snap = (ns.Dragger and ns.Dragger.GetMoverSnapSize and ns.Dragger:GetMoverSnapSize()) or 0
  if snap <= 0 then
    return "Snap: Off"
  end
  return "Snap: " .. tostring(snap)
end

function ConfigFrame:CycleMoverSnap()
  if ns.Dragger and ns.Dragger.CycleMoverSnap then
    ns.Dragger:CycleMoverSnap()
  end
  if self.compactMoverSnapButton then
    self.compactMoverSnapButton:SetText(self:GetMoverSnapButtonText())
  end
end

function ConfigFrame:ResetVisibleMoverPositions()
  if ns.Dragger and ns.Dragger.ResetAllVisiblePositions then
    ns.Dragger:ResetAllVisiblePositions()
  end
end

function ConfigFrame:EnableMoversFromStudio()
  toggleMovers()
  if areMoversEnabled() then
    self:EnterMoverMode()
  end
end

function ConfigFrame:EnterMoverMode()
  self:BuildFrame()
  self:BuildCompactMoverFrame()

  if not areMoversEnabled() then
    toggleMovers()
  end

  if self.frame and self.frame:IsShown() then
    self._suspendDisableMoversOnHide = true
    self.frame:Hide()
  end

  if self.compactMoverFrame then
    if self.compactMoverSnapButton then
      self.compactMoverSnapButton:SetText(self:GetMoverSnapButtonText())
    end
    self.compactMoverFrame:Show()
    self.compactMoverFrame:Raise()
  end
end

function ConfigFrame:DisableMoversAndHideCompact()
  disableMovers()
  if self.compactMoverFrame then
    self.compactMoverFrame:Hide()
  end
  if self.btnMovers then
    refreshMoverButton(self.btnMovers)
  end
end

function ConfigFrame:ReopenStudioWhileMoving()
  self:BuildFrame()
  self:BuildCompactMoverFrame()
  if self.compactMoverFrame then
    self.compactMoverFrame:Hide()
  end
  if self.frame then
    self.frame:Show()
    self.frame:Raise()
  end
end

function ConfigFrame:Open()
  self:BuildFrame()
  if self.compactMoverFrame then
    self.compactMoverFrame:Hide()
  end
  self.frame:Show()
  self.frame:Raise()
end

function ConfigFrame:Close()
  if self.frame then
    self.frame:Hide()
  end
  if self.compactMoverFrame then
    self.compactMoverFrame:Hide()
  end
end

function ConfigFrame:Toggle()
  self:BuildFrame()
  if self.compactMoverFrame and self.compactMoverFrame:IsShown() then
    self:ReopenStudioWhileMoving()
    return
  end
  self.frame:SetShown(not self.frame:IsShown())
  if self.frame:IsShown() then
    self.frame:Raise()
  end
end

function ConfigFrame:IsShown()
  return (self.frame and self.frame:IsShown()) or (self.compactMoverFrame and self.compactMoverFrame:IsShown()) or false
end

Panels.ConfigFrame = ConfigFrame
UI.ConfigFrame = ConfigFrame
