local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local Skin = ns.UISkin
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local AuraListPanel = {}
AuraListPanel.__index = AuraListPanel

local STATUS_COLORS = {
  ok = { 0.2, 0.95, 0.3 },
  warn = { 1.0, 0.82, 0.1 },
  error = { 1.0, 0.3, 0.3 },
}

local function lowerSafe(text)
  return tostring(text or ""):lower()
end

local function displayGroupName(groupID)
  groupID = tostring(groupID or "")
  if groupID == "" then
    return "Ungrouped"
  end
  return groupID
end

local function makeCollapseKey(section, groupID)
  return tostring(section or "loaded") .. "::" .. tostring(groupID or "")
end

local function isGroupCollapsed(self, section, groupID)
  self.collapsedGroups = self.collapsedGroups or {}
  local key = makeCollapseKey(section, groupID)
  local value = self.collapsedGroups[key]
  if value == nil then
    return tostring(section or "") == "not_loaded"
  end
  return value == true
end

local function setGroupCollapsed(self, section, groupID, collapsed)
  self.collapsedGroups = self.collapsedGroups or {}
  self.collapsedGroups[makeCollapseKey(section, groupID)] = collapsed == true
end

local function matchesScope(scope, row)
  scope = tostring(scope or "all")
  row = row or {}
  if scope == "loaded" then
    return row.isLoaded ~= false
  end
  if scope == "not_loaded" then
    return row.isLoaded == false
  end
  if scope == "groups" then
    return tostring(row.group or "") ~= ""
  end
  if scope == "drafts" then
    return row.isDraft == true
  end
  return true
end

function AuraListPanel:ExportGroup(groupID)
  groupID = tostring(groupID or "")
  if groupID == "" or not ns.ImportExport or not ns.ImportExport.ExportGroupString then
    return
  end

  local text, err = ns.ImportExport:ExportGroupString(groupID)
  if not text then
    return
  end

  if UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowExport then
    UI.ImportExportDialog:ShowExport(
      "Export Group",
      text,
      "This exports the selected group, its layout, and all contained auras with their linked rules."
    )
  end
end

function AuraListPanel:RefreshDragAssignmentHint()
  if not self.dragHint then
    return
  end
  local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
  if draggingAuraId then
    self.dragHint:SetText("Drop the dragged aura onto a group in the left column to assign it.")
    self.dragHint:SetTextColor(0.96, 0.82, 0.22)
  else
    self.dragHint:SetText("Tip: drag an aura from this list into a group on the left to assign it.")
    self.dragHint:SetTextColor(0.62, 0.68, 0.74)
  end
end

function AuraListPanel:BuildRows()
  local rows = nil
  if UI.AuraRepository and UI.AuraRepository.ListAuras then
    rows = UI.AuraRepository:ListAuras(S and S:Get() or nil)
  end
  if type(rows) ~= "table" then
    rows = {}
  end

  local state = S and S.Get and S:Get() or {}
  local search = lowerSafe(state.filters and state.filters.search or "")
  local scope = tostring(state.filters and state.filters.listScope or "all")
  local groupFilter = tostring(state.filters and state.filters.group or "all")

  if search ~= "" then
    local filtered = {}
    for i = 1, #rows do
      local row = rows[i]
      local hay = lowerSafe(row.name) .. " " .. lowerSafe(row.group) .. " " .. lowerSafe(row.unit) .. " " .. lowerSafe(row.trigger) .. " " .. tostring(row.spellID or "")
      if hay:find(search, 1, true) then
        filtered[#filtered + 1] = row
      end
    end
    rows = filtered
  end

  if scope ~= "all" then
    local filtered = {}
    for i = 1, #rows do
      if matchesScope(scope, rows[i]) then
        filtered[#filtered + 1] = rows[i]
      end
    end
    rows = filtered
  end

  if groupFilter ~= "all" then
    local filtered = {}
    for i = 1, #rows do
      local rowGroup = tostring(rows[i].group or "")
      if groupFilter == "__ungrouped__" then
        if rowGroup == "" then
          filtered[#filtered + 1] = rows[i]
        end
      elseif rowGroup == groupFilter then
        filtered[#filtered + 1] = rows[i]
      end
    end
    rows = filtered
  end

  table.sort(rows, function(a, b)
    if (a.isLoaded ~= false) ~= (b.isLoaded ~= false) then
      return a.isLoaded ~= false
    end
    local ga, gb = tostring(a.group or ""), tostring(b.group or "")
    if ga ~= gb then
      return ga < gb
    end
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  local out = {}
  local currentGroup = nil
  local currentSection = nil
  local groupCounts = {}
  for i = 1, #rows do
    local section = (rows[i].isLoaded == false) and "not_loaded" or "loaded"
    local grp = section .. "::" .. displayGroupName(rows[i].group)
    groupCounts[grp] = (groupCounts[grp] or 0) + 1
  end
  for i = 1, #rows do
    local row = rows[i]
    local section = (row.isLoaded == false) and "not_loaded" or "loaded"
    if section ~= currentSection then
      currentSection = section
      currentGroup = nil
      if section == "not_loaded" then
        out[#out + 1] = {
          isSection = true,
          label = "Not Loaded",
          reason = "These auras do not match your current class/spec.",
        }
      end
    end
    local grpLabel = displayGroupName(row.group)
    local grp = section .. "::" .. grpLabel
    local groupID = tostring(row.group or "")
    if grpLabel ~= currentGroup then
      currentGroup = grpLabel
      out[#out + 1] = {
        isHeader = true,
        group = grpLabel,
        groupID = groupID,
        section = section,
        count = groupCounts[grp] or 0,
        collapsed = isGroupCollapsed(self, section, groupID),
        isLoaded = section == "loaded",
      }
    end
    if not isGroupCollapsed(self, section, groupID) then
      out[#out + 1] = row
    end
  end
  return out
end

function AuraListPanel:AcquireRow(index, rowType)
  self.rowButtons = self.rowButtons or {}
  local key = tostring(index) .. ":" .. tostring(rowType or "row")
  local btn = self.rowButtons[key]
  if btn then
    return btn
  end

  btn = CreateFrame("Button", nil, self.scrollChild)

  if rowType == "header" then
    btn:SetHeight(22)
    btn:EnableMouse(true)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.10, 0.11, 0.13, 0.62)

    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.arrow:SetPoint("LEFT", 6, 0)
    btn.arrow:SetJustifyH("LEFT")

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", 20, 0)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetTextColor(0.88, 0.91, 0.96)

    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.count:SetPoint("RIGHT", -6, 0)
    btn.count:SetTextColor(0.62, 0.70, 0.80)

    btn.exportButton = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
    btn.exportButton:SetSize(18, 14)
    btn.exportButton:SetPoint("RIGHT", btn.count, "LEFT", -4, 0)
    btn.exportButton:SetText("E")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn.exportButton, "ghost")
    end
    btn.exportButton:SetScript("OnClick", function(exportBtn)
      local parentBtn = exportBtn:GetParent()
      self:ExportGroup(parentBtn and parentBtn.groupID or "")
    end)
    btn.exportButton:SetScript("OnEnter", function(exportBtn)
      if GameTooltip then
        local parentBtn = exportBtn:GetParent()
        GameTooltip:SetOwner(exportBtn, "ANCHOR_RIGHT")
        GameTooltip:SetText("Export Group", 1, 0.82, 0.1)
        GameTooltip:AddLine("Copy this group's export string.", 0.85, 0.85, 0.85, true)
        GameTooltip:AddLine(tostring(parentBtn and parentBtn.group or "Group"), 0.65, 0.88, 1.0)
        GameTooltip:Show()
      end
    end)
    btn.exportButton:SetScript("OnLeave", function()
      if GameTooltip then
        GameTooltip:Hide()
      end
    end)

    if Skin and Skin.ApplyClickableRow then
      Skin:ApplyClickableRow(btn, "header")
    end
    btn:SetScript("OnClick", function(selfBtn)
      setGroupCollapsed(self, selfBtn.section or "loaded", selfBtn.groupID or "", not isGroupCollapsed(self, selfBtn.section or "loaded", selfBtn.groupID or ""))
      self:Render()
    end)
    btn:SetScript("OnReceiveDrag", function(selfBtn)
      local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
      if draggingAuraId and ns.SettingsData and ns.SettingsData.SetEntryGroup then
        ns.SettingsData:SetEntryGroup(draggingAuraId, selfBtn.groupID or "")
        if S and S.ClearDraggingAura then
          S:ClearDraggingAura()
        end
        if E then
          E:Emit(E.Names.FILTER_CHANGED, { key = "drag_group_assign", value = selfBtn.groupID or "" })
        end
      end
    end)
    btn:SetScript("OnEnter", function(selfBtn)
      local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
      if draggingAuraId then
        selfBtn.bg:SetColorTexture(0.18, 0.24, 0.30, 0.92)
      end
    end)
    btn:SetScript("OnLeave", function(selfBtn)
      selfBtn.bg:SetColorTexture(0.10, 0.11, 0.13, 0.62)
    end)
  elseif rowType == "section" then
    btn:SetHeight(42)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.09, 0.10, 0.12, 0.34)

    btn.topLine = btn:CreateTexture(nil, "BORDER")
    btn.topLine:SetColorTexture(0.60, 0.70, 0.86, 0.14)
    btn.topLine:SetPoint("TOPLEFT", 6, -1)
    btn.topLine:SetPoint("TOPRIGHT", -6, -1)
    btn.topLine:SetHeight(1)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.text:SetPoint("TOPLEFT", 10, -6)
    btn.text:SetJustifyH("LEFT")
    btn.text:SetTextColor(0.88, 0.92, 0.97)

    btn.reason = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.reason:SetPoint("TOPLEFT", 10, -22)
    btn.reason:SetPoint("RIGHT", -10, 0)
    btn.reason:SetJustifyH("LEFT")
    btn.reason:SetJustifyV("TOP")
    btn.reason:SetWordWrap(true)
  else
    btn:SetHeight(46)
    btn:RegisterForDrag("LeftButton")
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.11, 0.13, 0.16, 0.48)

    btn.accent = btn:CreateTexture(nil, "ARTWORK")
    btn.accent:SetPoint("TOPLEFT", 0, 0)
    btn.accent:SetPoint("BOTTOMLEFT", 0, 0)
    btn.accent:SetWidth(0)
    btn.accent:SetColorTexture(1.0, 0.82, 0.18, 0.00)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("LEFT", 10, 0)
    btn.icon:SetSize(20, 20)

    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.nameText:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 8, -4)
    btn.nameText:SetPoint("RIGHT", -80, 0)
    btn.nameText:SetJustifyH("LEFT")
    btn.nameText:SetJustifyV("TOP")
    btn.nameText:SetWordWrap(false)
    btn.nameText:SetTextColor(0.95, 0.96, 0.98)

    btn.metaText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.metaText:SetPoint("TOPLEFT", btn.icon, "BOTTOMRIGHT", 8, 3)
    btn.metaText:SetPoint("RIGHT", -80, 0)
    btn.metaText:SetJustifyH("LEFT")
    btn.metaText:SetJustifyV("TOP")
    btn.metaText:SetWordWrap(false)
    btn.metaText:SetTextColor(0.64, 0.68, 0.74)

    btn.statusText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.statusText:SetPoint("RIGHT", -8, 0)
    btn.statusText:SetJustifyH("RIGHT")
    btn.statusText:SetTextColor(0.70, 0.74, 0.80)

    btn:SetScript("OnClick", function(selfBtn)
      if S and S.SetSelectedAura then
        S:SetSelectedAura(selfBtn.auraId, "list")
      end
    end)
    btn:SetScript("OnDragStart", function(selfBtn)
      if S and S.SetSelectedAura then
        S:SetSelectedAura(selfBtn.auraId, "drag")
      end
      if S and S.SetDraggingAura then
        S:SetDraggingAura(selfBtn.auraId)
      end
      if Skin and Skin.SetClickableRowState then
        Skin:SetClickableRowState(selfBtn, "selected")
      end
    end)
    btn:SetScript("OnDragStop", function()
      if C_Timer and C_Timer.After and S and S.ClearDraggingAura then
        C_Timer.After(0, function()
          S:ClearDraggingAura()
        end)
      elseif S and S.ClearDraggingAura then
        S:ClearDraggingAura()
      end
    end)

    if Skin and Skin.ApplyClickableRow then
      Skin:ApplyClickableRow(btn, "row")
    end

    btn:SetScript("OnEnter", function(selfBtn)
      if Skin and Skin.SetClickableRowState then
        Skin:SetClickableRowState(selfBtn, "hover")
      else
        selfBtn.bg:SetColorTexture(0.14, 0.12, 0.07, 0.78)
      end
    end)

    btn:SetScript("OnLeave", function(selfBtn)
      if Skin and Skin.SetClickableRowState then
        Skin:SetClickableRowState(selfBtn, (selfBtn.auraId and selfBtn.auraId == self.selectedAuraId) and "selected" or "normal")
      elseif selfBtn.auraId and selfBtn.auraId == self.selectedAuraId then
        selfBtn.bg:SetColorTexture(0.18, 0.36, 0.56, 0.88)
      else
        selfBtn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.45)
      end
    end)
  end

  self.rowButtons[key] = btn
  return btn
end

function AuraListPanel:Render()
  local rows = self:BuildRows()
  local width = math.max(100, (self.scroll:GetWidth() or self.scrollChild:GetWidth() or 0) - 2)
  local y = -2

  local used = {}

  if #rows == 0 then
    if not self.emptyStateCard then
      local card = CreateFrame("Frame", nil, self.scrollChild, "BackdropTemplate")
      if Skin and Skin.ApplySection then
        Skin:ApplySection(card)
      end
      card:SetPoint("TOPLEFT", 4, -10)
      card:SetPoint("RIGHT", -4, 0)
      card:SetHeight(168)
      self.emptyStateCard = card

      self.emptyState = card:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      self.emptyState:SetPoint("TOPLEFT", 12, -12)
      self.emptyState:SetPoint("RIGHT", -12, 0)
      self.emptyState:SetJustifyH("LEFT")
      self.emptyState:SetJustifyV("TOP")

      self.emptyStateHint = card:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      self.emptyStateHint:SetPoint("TOPLEFT", 12, -36)
      self.emptyStateHint:SetPoint("RIGHT", -12, 0)
      self.emptyStateHint:SetJustifyH("LEFT")
      self.emptyStateHint:SetJustifyV("TOP")
      self.emptyStateHint:SetText("Start by creating an aura, importing one, or dragging future auras into a group on the left.")

      self.emptyNewButton = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
      self.emptyNewButton:SetSize(92, 22)
      self.emptyNewButton:SetPoint("TOPLEFT", 12, -72)
      self.emptyNewButton:SetText("New Aura")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(self.emptyNewButton, "primary")
      end
      self.emptyNewButton:SetScript("OnClick", function()
        if E then
          E:Emit(E.Names.NEW_AURA, { source = "empty_state" })
        end
      end)

      self.emptyImportButton = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
      self.emptyImportButton:SetSize(82, 22)
      self.emptyImportButton:SetPoint("LEFT", self.emptyNewButton, "RIGHT", 8, 0)
      self.emptyImportButton:SetText("Import")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(self.emptyImportButton, "ghost")
      end
      self.emptyImportButton:SetScript("OnClick", function()
        if E then
          E:Emit(E.Names.OPEN_IMPORT_PANEL, { source = "empty_state" })
        end
      end)

      self.emptyGroupsButton = CreateFrame("Button", nil, card, "UIPanelButtonTemplate")
      self.emptyGroupsButton:SetSize(82, 22)
      self.emptyGroupsButton:SetPoint("LEFT", self.emptyImportButton, "RIGHT", 8, 0)
      self.emptyGroupsButton:SetText("Groups")
      if Skin and Skin.ApplyButton then
        Skin:SetButtonVariant(self.emptyGroupsButton, "ghost")
      end
      self.emptyGroupsButton:SetScript("OnClick", function()
        if E then
          E:Emit(E.Names.OPEN_GROUPS_PANEL, { source = "empty_state" })
        end
      end)
    end

    local state = S and S.Get and S:Get() or {}
    local scope = tostring(state.filters and state.filters.listScope or "all")
    local search = tostring(state.filters and state.filters.search or "")
    local groupFilter = tostring(state.filters and state.filters.group or "all")
    local message = "No auras to show yet."
    if search ~= "" then
      message = string.format("No auras match \"%s\". Try a different search or clear the filter.", search)
    elseif groupFilter == "__ungrouped__" then
      message = "No standalone auras match the current filters."
    elseif groupFilter ~= "all" then
      message = "No auras in this group match the current filters."
    elseif scope == "loaded" then
      message = "No loaded auras match the current filters."
    elseif scope == "not_loaded" then
      message = "No hidden load-restricted auras right now."
    elseif scope == "groups" then
      message = "No grouped auras match the current filters."
    elseif scope == "drafts" then
      message = "No unsaved drafts right now."
    end
    self.emptyState:SetText(message)
    self.emptyStateCard:Show()
  elseif self.emptyStateCard then
    self.emptyStateCard:Hide()
  end

  for i = 1, #rows do
    local row = rows[i]
    local rowType = row.isSection and "section" or (row.isHeader and "header" or "row")
    local btn = self:AcquireRow(i, rowType)
    used[tostring(i) .. ":" .. rowType] = true
    btn:SetPoint("TOPLEFT", 0, y)
    btn:SetWidth(width)
    btn:Show()

    if row.isSection then
      btn.text:SetText(tostring(row.label or "Section"))
      btn.reason:SetText(tostring(row.reason or ""))
      btn.text:SetWidth(math.max(1, width - 16))
      btn.reason:SetWidth(math.max(1, width - 16))

      local titleHeight = btn.text:GetStringHeight() or 14
      local reasonHeight = btn.reason:GetStringHeight() or 12
      local sectionHeight = math.max(32, math.floor(titleHeight + reasonHeight + 10))
      btn:SetHeight(sectionHeight)
      y = y - sectionHeight - 4
    elseif row.isHeader then
      btn.groupID = tostring(row.groupID or "")
      btn.section = tostring(row.section or "loaded")
      btn.group = tostring(row.group or "Group")
      btn.arrow:SetText(row.collapsed and ">" or "v")
      btn.text:SetText(tostring(row.group or "Group"))
      btn.count:SetText(tostring(row.count or 0))
      btn.exportButton:SetShown(btn.groupID ~= "")
      y = y - 24
    else
      btn.auraId = row.id
      btn.icon:SetTexture(row.icon or 134400)

      local auraName = tostring(row.name or "")
      if auraName == "" then
        auraName = "Aura " .. tostring(row.spellID or "?")
      end
      btn.nameText:SetText(auraName)
      local meta = (row.isLoaded == false) and tostring(row.loadReason or "Not Loaded") or ((tostring(row.group or "") ~= "") and ("Group: " .. tostring(row.group or "")) or tostring(row.unit or "player"))
      btn.metaText:SetText(meta)

      local status = tostring(row.status or "ok")
      local color = STATUS_COLORS[status] or STATUS_COLORS.ok
      btn.statusText:SetText(status:upper())
      btn.statusText:SetTextColor(color[1], color[2], color[3])
      local isSelected = row.id and row.id == self.selectedAuraId
      if Skin and Skin.SetClickableRowState then
        Skin:SetClickableRowState(btn, isSelected and "selected" or "normal")
      elseif isSelected then
        btn.bg:SetColorTexture(0.20, 0.16, 0.08, 0.88)
      else
        btn.bg:SetColorTexture(0.08, 0.07, 0.05, 0.44)
      end

      y = y - 50
    end
  end

  for key, btn in pairs(self.rowButtons or {}) do
    if not used[key] then
      btn:Hide()
    end
  end

  if self.emptyStateCard and self.emptyStateCard:IsShown() then
    self.scrollChild:SetHeight(math.max(176, -y + 8))
  else
    self.scrollChild:SetHeight(math.max(1, -y + 8))
  end
end

function AuraListPanel:BindSearchBox(editBox)
  if not editBox then
    return
  end
  editBox:SetScript("OnTextChanged", function(box)
    if S and S.SetFilter then
      S:SetFilter("search", tostring(box:GetText() or ""))
    end
  end)
end

function AuraListPanel:Create(parent)
  local o = setmetatable({}, self)

  o.frame = CreateFrame("Frame", nil, parent)
  o.frame:SetAllPoints()
  o.collapsedGroups = {}

  local function makeFilterButton(text, scope, x, width)
    local btn = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
    btn:SetSize(width or 56, 20)
    btn:SetPoint("TOPLEFT", x, -2)
    btn:SetText(text)
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(btn, "segment")
    end
    btn:SetScript("OnClick", function()
      if S and S.SetFilter then
        S:SetFilter("listScope", scope)
      end
    end)
    return btn
  end

  o.scopeButtons = {
    makeFilterButton("All", "all", 0, 44),
    makeFilterButton("Loaded", "loaded", 48, 62),
    makeFilterButton("Not Loaded", "not_loaded", 114, 90),
    makeFilterButton("Groups", "groups", 208, 62),
    makeFilterButton("Drafts", "drafts", 274, 62),
  }

  local function refreshScopeButtons()
    local current = S and S.Get and S:Get().filters and S:Get().filters.listScope or "all"
    for i = 1, #(o.scopeButtons or {}) do
      local btn = o.scopeButtons[i]
      if btn and Skin and Skin.SetButtonSelected then
        Skin:SetButtonSelected(btn, current == ({ "all", "loaded", "not_loaded", "groups", "drafts" })[i])
      end
    end
  end

  o.footerLine = o.frame:CreateTexture(nil, "BORDER")
  o.footerLine:SetPoint("TOPLEFT", 0, -48)
  o.footerLine:SetPoint("TOPRIGHT", 0, -48)
  o.footerLine:SetHeight(1)
  o.footerLine:SetColorTexture(1.0, 0.82, 0.18, 0.16)

  o.dragHint = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.dragHint:SetPoint("TOPLEFT", 0, -28)
  o.dragHint:SetPoint("RIGHT", 0, 0)
  o.dragHint:SetJustifyH("LEFT")
  o.dragHint:SetWordWrap(false)
  o.dragHint:SetText("Tip: drag an aura onto a group header to move it into that group.")

  if AceGUI then
    o.scrollWidget = AceGUI:Create("ScrollFrame")
    o.scrollWidget:SetLayout("Manual")
    o.scrollWidget.frame:SetParent(o.frame)
    o.scrollWidget.frame:ClearAllPoints()
    o.scrollWidget.frame:SetPoint("TOPLEFT", 0, -52)
    o.scrollWidget.frame:SetPoint("BOTTOMRIGHT", 0, 0)
    o.scrollWidget.content:SetWidth(1)
    o.scroll = o.scrollWidget.scrollframe or o.scrollWidget.frame
    o.scrollChild = o.scrollWidget.content
    o.scroll:SetScript("OnSizeChanged", function(scrollFrame, width)
      o.scrollChild:SetWidth(math.max(1, (width or 0) - 6))
      o:Render()
    end)
    C_Timer.After(0, function()
      if o and o.scrollChild and o.scroll then
        o.scrollChild:SetWidth(math.max(1, (o.scroll:GetWidth() or 0) - 6))
        o:Render()
      end
    end)
  else
    o.scroll = CreateFrame("ScrollFrame", nil, o.frame)
    o.scroll:SetPoint("TOPLEFT", 0, -52)
    o.scroll:SetPoint("BOTTOMRIGHT", 0, 0)
    o.scroll:EnableMouseWheel(true)

    o.scrollChild = CreateFrame("Frame", nil, o.scroll)
    o.scrollChild:SetPoint("TOPLEFT")
    o.scrollChild:SetSize(math.max(1, (o.scroll:GetWidth() or 0) - 2), 1)
    o.scroll:SetScrollChild(o.scrollChild)
    o.scroll:SetScript("OnMouseWheel", function(scrollFrame, delta)
      local current = scrollFrame:GetVerticalScroll() or 0
      local maxScroll = math.max(0, (o.scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
      scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta * 32))))
    end)

    o.scroll:SetScript("OnSizeChanged", function(scrollFrame, width)
      o.scrollChild:SetWidth(math.max(1, (width or 0) - 2))
      o:Render()
    end)
  end

  if E then
    E:On(E.Names.STATE_CHANGED, function()
      o:RefreshDragAssignmentHint()
    end)
  end

  o:RefreshDragAssignmentHint()

  if E then
    E:On(E.Names.AURA_SELECTED, function(payload)
      o.selectedAuraId = payload and payload.auraId or nil
      o:Render()
    end)

    E:On(E.Names.FILTER_CHANGED, function()
      refreshScopeButtons()
      o:Render()
    end)
  end

  refreshScopeButtons()
  o:Render()
  return o
end

Panels.AuraListPanel = AuraListPanel
