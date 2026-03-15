local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local Skin = ns.UISkin

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

local function isGroupCollapsed(self, groupID)
  self.collapsedGroups = self.collapsedGroups or {}
  return self.collapsedGroups[tostring(groupID or "")] == true
end

local function setGroupCollapsed(self, groupID, collapsed)
  self.collapsedGroups = self.collapsedGroups or {}
  self.collapsedGroups[tostring(groupID or "")] = collapsed == true
end

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.03, 0.08, 0.16, 0.74)
  frame:SetBackdropBorderColor(0.1, 0.44, 0.76, 0.90)
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

  table.sort(rows, function(a, b)
    local ga, gb = tostring(a.group or ""), tostring(b.group or "")
    if ga ~= gb then
      return ga < gb
    end
    return tostring(a.name or "") < tostring(b.name or "")
  end)

  local out = {}
  local currentGroup = nil
  local groupCounts = {}
  for i = 1, #rows do
    local grp = displayGroupName(rows[i].group)
    groupCounts[grp] = (groupCounts[grp] or 0) + 1
  end
  for i = 1, #rows do
    local row = rows[i]
    local grp = displayGroupName(row.group)
    local groupID = tostring(row.group or "")
    if grp ~= currentGroup then
      currentGroup = grp
      out[#out + 1] = {
        isHeader = true,
        group = grp,
        groupID = groupID,
        count = groupCounts[grp] or 0,
        collapsed = isGroupCollapsed(self, groupID),
      }
    end
    if not isGroupCollapsed(self, groupID) then
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
    btn:SetHeight(20)
    btn:EnableMouse(true)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.08, 0.2, 0.34, 0.8)

    btn.arrow = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.arrow:SetPoint("LEFT", 8, 0)
    btn.arrow:SetJustifyH("LEFT")

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", 20, 0)
    btn.text:SetJustifyH("LEFT")

    btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.count:SetPoint("RIGHT", -8, 0)

    btn.exportButton = CreateFrame("Button", nil, btn, "UIPanelButtonTemplate")
    btn.exportButton:SetSize(18, 16)
    btn.exportButton:SetPoint("RIGHT", btn.count, "LEFT", -6, 0)
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
      setGroupCollapsed(self, selfBtn.groupID or "", not isGroupCollapsed(self, selfBtn.groupID or ""))
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
        selfBtn.bg:SetColorTexture(0.16, 0.34, 0.52, 0.92)
      end
    end)
    btn:SetScript("OnLeave", function(selfBtn)
      selfBtn.bg:SetColorTexture(0.08, 0.2, 0.34, 0.8)
    end)
  else
    btn:SetHeight(30)
    btn:RegisterForDrag("LeftButton")
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.45)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("LEFT", 6, 0)
    btn.icon:SetSize(22, 22)

    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.nameText:SetPoint("RIGHT", -144, 0)
    btn.nameText:SetJustifyH("LEFT")

    btn.metaText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.metaText:SetPoint("RIGHT", -84, 0)
    btn.metaText:SetWidth(54)
    btn.metaText:SetJustifyH("RIGHT")

    btn.statusText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    btn.statusText:SetPoint("RIGHT", -8, 0)

    btn.previewText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    btn.previewText:SetPoint("RIGHT", btn.statusText, "LEFT", -8, 0)
    btn.previewText:SetText("")

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
        selfBtn.bg:SetColorTexture(0.14, 0.28, 0.44, 0.78)
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
  local width = math.max(100, (self.scroll:GetWidth() or self.scrollChild:GetWidth() or 0) - 28)
  local y = -2

  local used = {}

  for i = 1, #rows do
    local row = rows[i]
    local rowType = row.isHeader and "header" or "row"
    local btn = self:AcquireRow(i, rowType)
    used[tostring(i) .. ":" .. rowType] = true
    btn:SetPoint("TOPLEFT", 2, y)
    btn:SetWidth(width)
    btn:Show()

    if row.isHeader then
      btn.groupID = tostring(row.groupID or "")
      btn.group = tostring(row.group or "Group")
      btn.arrow:SetText(row.collapsed and ">" or "v")
      btn.text:SetText(tostring(row.group or "Group"))
      btn.count:SetText(tostring(row.count or 0))
      btn.exportButton:SetShown(btn.groupID ~= "")
      y = y - 22
    else
      btn.auraId = row.id
      btn.icon:SetTexture(row.icon or 134400)

      local auraName = tostring(row.name or "")
      if auraName == "" then
        auraName = "Aura " .. tostring(row.spellID or "?")
      end
      btn.nameText:SetText(auraName)
      local meta = (tostring(row.group or "") ~= "") and "grouped" or ""
      btn.metaText:SetText(meta)

      local status = tostring(row.status or "ok")
      local color = STATUS_COLORS[status] or STATUS_COLORS.ok
      btn.statusText:SetText(status:upper())
      btn.statusText:SetTextColor(color[1], color[2], color[3])
      local isSelected = row.id and row.id == self.selectedAuraId
      btn.previewText:SetText(isSelected and "PREVIEW" or "")
      btn.previewText:SetTextColor(0.65, 0.88, 1.0)

      if Skin and Skin.SetClickableRowState then
        Skin:SetClickableRowState(btn, isSelected and "selected" or "normal")
      elseif isSelected then
        btn.bg:SetColorTexture(0.18, 0.36, 0.56, 0.88)
      else
        btn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.45)
      end

      y = y - 32
    end
  end

  for key, btn in pairs(self.rowButtons or {}) do
    if not used[key] then
      btn:Hide()
    end
  end

  self.scrollChild:SetHeight(math.max(1, -y + 8))
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

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetAllPoints()
  createBackdrop(o.frame)
  o.collapsedGroups = {}

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame, "UIPanelScrollFrameTemplate")
  o.scroll:SetPoint("TOPLEFT", 6, -6)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 6)

  o.scrollChild = CreateFrame("Frame", nil, o.scroll)
  o.scrollChild:SetPoint("TOPLEFT")
  o.scrollChild:SetSize(math.max(1, (o.scroll:GetWidth() or 0) - 4), 1)
  o.scroll:SetScrollChild(o.scrollChild)

  o.scroll:SetScript("OnSizeChanged", function(scrollFrame, width)
    o.scrollChild:SetWidth(math.max(1, (width or 0) - 4))
    o:Render()
  end)

  if E then
    E:On(E.Names.AURA_SELECTED, function(payload)
      o.selectedAuraId = payload and payload.auraId or nil
      o:Render()
    end)

    E:On(E.Names.FILTER_CHANGED, function()
      o:Render()
    end)
  end

  o:Render()
  return o
end

Panels.AuraListPanel = AuraListPanel
