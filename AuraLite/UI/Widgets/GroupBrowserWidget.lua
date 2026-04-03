local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local Widgets = UI.Widgets
local S = UI.State
local E = UI.Events
local Skin = ns.UISkin
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local GroupBrowserWidget = {}
GroupBrowserWidget.__index = GroupBrowserWidget

local FILTER_ALL = "all"
local FILTER_UNGROUPED = "__ungrouped__"

local function buildRows()
  local rows = {}
  local auraRows = (UI.AuraRepository and UI.AuraRepository.ListAuras and UI.AuraRepository:ListAuras(S and S:Get() or nil)) or {}
  local totalCount = #auraRows
  local ungroupedCount = 0

  for i = 1, #auraRows do
    if tostring(auraRows[i].group or "") == "" then
      ungroupedCount = ungroupedCount + 1
    end
  end

  rows[#rows + 1] = {
    id = FILTER_ALL,
    label = "All Auras",
    count = totalCount,
    subtitle = "Everything",
  }

  rows[#rows + 1] = {
    id = FILTER_UNGROUPED,
    label = "Ungrouped",
    count = ungroupedCount,
    subtitle = "Standalone",
  }

  local groups = (ns.SettingsData and ns.SettingsData.ListGroupsDetailed and ns.SettingsData:ListGroupsDetailed()) or {}
  for i = 1, #groups do
    rows[#rows + 1] = {
      id = tostring(groups[i].id or ""),
      label = tostring(groups[i].name or groups[i].id or "Group"),
      count = tonumber(groups[i].count) or 0,
      subtitle = string.format("%s | %spx", tostring(groups[i].direction or "RIGHT"), tostring(groups[i].spacing or 4)),
    }
  end

  return rows
end

function GroupBrowserWidget:AcquireRow(index)
  self.rows = self.rows or {}
  local row = self.rows[index]
  if row then
    return row
  end

  row = CreateFrame("Button", nil, self.scrollChild)
  row:SetHeight(44)
  row.bg = row:CreateTexture(nil, "BACKGROUND")
  row.bg:SetAllPoints()
  row.bg:SetColorTexture(0.11, 0.13, 0.16, 0.46)

  row.accent = row:CreateTexture(nil, "ARTWORK")
  row.accent:SetPoint("TOPLEFT", 0, 0)
  row.accent:SetPoint("BOTTOMLEFT", 0, 0)
  row.accent:SetWidth(0)
  row.accent:SetColorTexture(1.0, 0.82, 0.18, 0.00)

  row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.label:SetPoint("TOPLEFT", 12, -6)
  row.label:SetPoint("RIGHT", -56, 0)
  row.label:SetJustifyH("LEFT")
  row.label:SetWordWrap(false)
  row.label:SetTextColor(0.95, 0.96, 0.98)

  row.meta = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  row.meta:SetPoint("TOPLEFT", 12, -22)
  row.meta:SetPoint("RIGHT", -56, 0)
  row.meta:SetJustifyH("LEFT")
  row.meta:SetWordWrap(false)
  row.meta:SetTextColor(0.64, 0.68, 0.74)

  row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  row.count:SetPoint("RIGHT", -8, 0)
  row.count:SetTextColor(0.64, 0.72, 0.82)

  if Skin and Skin.ApplyClickableRow then
    Skin:ApplyClickableRow(row, "row")
  end

  row:SetScript("OnClick", function(selfRow)
    if S and S.SetFilter then
      S:SetFilter("group", tostring(selfRow.groupFilter or FILTER_ALL))
    end
  end)
  row:SetScript("OnReceiveDrag", function(selfRow)
    local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
    local groupID = tostring(selfRow.groupID or "")
    if draggingAuraId and groupID ~= FILTER_ALL and ns.SettingsData and ns.SettingsData.SetEntryGroup then
      local targetGroup = (groupID == FILTER_UNGROUPED) and "" or groupID
      if ns.SettingsData:SetEntryGroup(draggingAuraId, targetGroup) and S and S.ClearDraggingAura then
        S:ClearDraggingAura()
      end
      if E then
        E:Emit(E.Names.FILTER_CHANGED, { key = "drag_group_browser_assign", value = targetGroup })
      end
    end
  end)

  row:SetScript("OnEnter", function(selfRow)
    local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
    if draggingAuraId and selfRow.groupID ~= FILTER_ALL then
      selfRow.bg:SetColorTexture(0.18, 0.24, 0.30, 0.92)
      selfRow.accent:SetWidth(3)
      selfRow.accent:SetColorTexture(1.0, 0.82, 0.18, 0.95)
    elseif Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(selfRow, "hover")
    end
  end)

  row:SetScript("OnLeave", function(selfRow)
    local selectedGroup = S and S.Get and (S:Get().filters or {}).group or FILTER_ALL
    selfRow.accent:SetWidth(0)
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(selfRow, selectedGroup == selfRow.groupFilter and "selected" or "normal")
    end
  end)

  self.rows[index] = row
  return row
end

function GroupBrowserWidget:Render()
  local rows = buildRows()
  local selectedGroup = S and S.Get and (S:Get().filters or {}).group or FILTER_ALL
  local width = math.max(120, (self.scroll:GetWidth() or self.scrollChild:GetWidth() or 0) - 1)
  local y = -2
  local used = {}

  for i = 1, #rows do
    local row = self:AcquireRow(i)
    used[i] = true
    row.groupFilter = rows[i].id
    row.groupID = rows[i].id
    row:ClearAllPoints()
    row:SetPoint("TOPLEFT", 0, y)
    row:SetWidth(width)
    row.label:SetText(rows[i].label)
    row.meta:SetText(rows[i].subtitle or "")
    row.count:SetText(tostring(rows[i].count or 0))
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(row, selectedGroup == rows[i].id and "selected" or "normal")
    end
    row:Show()
    y = y - 46
  end

  for i, row in pairs(self.rows or {}) do
    if not used[i] then
      row:Hide()
    end
  end

  self.scrollChild:SetWidth(width)
  self.scrollChild:SetHeight(math.max(1, -y + 8))
end

function GroupBrowserWidget:Create(parent)
  local o = setmetatable({}, self)

  o.frame = CreateFrame("Frame", nil, parent)
  o.frame:SetAllPoints()

  o.dragHint = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.dragHint:SetPoint("TOPLEFT", 0, 0)
  o.dragHint:SetPoint("RIGHT", 0, 0)
  o.dragHint:SetJustifyH("LEFT")
  o.dragHint:SetWordWrap(true)
  o.dragHint:SetText("Drag an aura from the list into a group here.")

  if AceGUI then
    o.scrollWidget = AceGUI:Create("ScrollFrame")
    o.scrollWidget:SetLayout("Manual")
    o.scrollWidget.frame:SetParent(o.frame)
    o.scrollWidget.frame:ClearAllPoints()
    o.scrollWidget.frame:SetPoint("TOPLEFT", 0, -22)
    o.scrollWidget.frame:SetPoint("BOTTOMRIGHT", 0, 32)
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
    o.scroll:SetPoint("TOPLEFT", 0, -22)
    o.scroll:SetPoint("BOTTOMRIGHT", 0, 32)
    o.scroll:EnableMouseWheel(true)

    o.scrollChild = CreateFrame("Frame", nil, o.scroll)
    o.scrollChild:SetSize(1, 1)
    o.scroll:SetScrollChild(o.scrollChild)
    o.scroll:SetScript("OnMouseWheel", function(scrollFrame, delta)
      local current = scrollFrame:GetVerticalScroll() or 0
      local maxScroll = math.max(0, (o.scrollChild:GetHeight() or 0) - (scrollFrame:GetHeight() or 0))
      scrollFrame:SetVerticalScroll(math.max(0, math.min(maxScroll, current - (delta * 32))))
    end)
    o.scroll:SetScript("OnSizeChanged", function()
      o:Render()
    end)
  end

  o.manageButton = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.manageButton:SetSize(104, 18)
  o.manageButton:SetPoint("BOTTOMLEFT", 0, 2)
  o.manageButton:SetText("Manage")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.manageButton, "ghost")
  end
  o.manageButton:SetScript("OnClick", function()
    if E then
      E:Emit(E.Names.OPEN_GROUPS_PANEL, { anchor = o.manageButton })
    end
  end)

  o.clearButton = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.clearButton:SetSize(62, 18)
  o.clearButton:SetPoint("BOTTOMRIGHT", 0, 2)
  o.clearButton:SetText("Show All")
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(o.clearButton, "segment")
  end
  o.clearButton:SetScript("OnClick", function()
    if S and S.SetFilter then
      S:SetFilter("group", FILTER_ALL)
    end
  end)

  o.footerLine = o.frame:CreateTexture(nil, "BORDER")
  o.footerLine:SetPoint("BOTTOMLEFT", 0, 24)
  o.footerLine:SetPoint("BOTTOMRIGHT", 0, 24)
  o.footerLine:SetHeight(1)
  o.footerLine:SetColorTexture(1.0, 0.82, 0.18, 0.08)

  if E then
    E:On(E.Names.STATE_CHANGED, function()
      local draggingAuraId = S and S.GetDraggingAura and S:GetDraggingAura() or nil
      if o.dragHint then
        if draggingAuraId then
          o.dragHint:SetText("Drop the dragged aura onto the destination group.")
          o.dragHint:SetTextColor(0.96, 0.82, 0.22)
        else
          o.dragHint:SetText("Drag an aura from the list into a group here.")
          o.dragHint:SetTextColor(0.62, 0.68, 0.74)
        end
      end
    end)
    E:On(E.Names.FILTER_CHANGED, function()
      o:Render()
    end)
  end

  o:Render()
  return o
end

Widgets.GroupBrowserWidget = GroupBrowserWidget
