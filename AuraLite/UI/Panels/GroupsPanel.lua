local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local FieldFactory = UI.FieldFactory
local Skin = ns.UISkin
local Widgets = UI.Widgets or {}

local GroupsPanel = {}
GroupsPanel.__index = GroupsPanel

local GROUP_FIELDS = {
  { key = "groupName", label = "Group Name", widget = "text" },
  { key = "groupDirection", label = "Group Direction", widget = "dropdown", options = {
    { value = "RIGHT", label = "Grow Right" },
    { value = "LEFT", label = "Grow Left" },
    { value = "DOWN", label = "Grow Down" },
    { value = "UP", label = "Grow Up" },
  } },
  { key = "groupSpacing", label = "Group Spacing", widget = "spinner", min = 0, max = 64, step = 1, default = 4, help = "Default: 4" },
  { key = "groupSort", label = "Group Sort", widget = "dropdown", options = {
    { value = "manual", label = "Manual Order" },
    { value = "list", label = "Aura List Order" },
    { value = "name", label = "Aura Name" },
    { value = "spell", label = "SpellID" },
  } },
  { key = "groupWrapAfter", label = "Wrap After", widget = "spinner", min = 0, max = 20, step = 1, default = 0, help = "0 = no wrap" },
  { key = "groupOffsetX", label = "Group Offset X", widget = "spinner", min = -200, max = 200, step = 1, default = 0, help = "Default: 0" },
  { key = "groupOffsetY", label = "Group Offset Y", widget = "spinner", min = -200, max = 200, step = 1, default = 0, help = "Default: 0" },
}

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
  frame:SetBackdropColor(0.02, 0.05, 0.10, 0.96)
  frame:SetBackdropBorderColor(0.44, 0.36, 0.16, 0.82)
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

local function makeButton(parent, text, w, variant, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w or 100, 22)
  btn:SetText(text)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, variant or "default")
  end
  btn:SetScript("OnClick", function()
    if onClick then
      onClick()
    end
  end)
  return btn
end

function GroupsPanel:BuildRows()
  return (ns.SettingsData and ns.SettingsData.ListGroupsDetailed and ns.SettingsData:ListGroupsDetailed()) or {}
end

function GroupsPanel:AssignDraggedAuraToGroup(groupID)
  local draggingAuraId = UI and UI.State and UI.State.GetDraggingAura and UI.State:GetDraggingAura() or nil
  groupID = tostring(groupID or "")
  if draggingAuraId and draggingAuraId ~= "" and groupID ~= "" and ns.SettingsData and ns.SettingsData.SetEntryGroup then
    if ns.SettingsData:SetEntryGroup(draggingAuraId, groupID) then
      self.selectedGroupID = groupID
      self.selectedMemberKey = draggingAuraId
      if UI and UI.State and UI.State.ClearDraggingAura then
        UI.State:ClearDraggingAura()
      end
      self:LoadGroup(groupID)
      return true
    end
  end
  return false
end

function GroupsPanel:GetSelectedAuraContext()
  local state = UI and UI.State and UI.State.Get and UI.State:Get() or {}
  local auraId = state and state.selectedAuraId
  if not auraId or auraId == "" or not UI.AuraRepository or not UI.AuraRepository.GetAuraDraft then
    return nil
  end
  local draft = UI.AuraRepository:GetAuraDraft(auraId)
  if not draft then
    return nil
  end
  return {
    id = auraId,
    name = tostring(draft.name or draft.displayName or "Selected Aura"),
    groupID = tostring(draft.groupID or draft.group or ""),
  }
end

function GroupsPanel:LoadGroup(groupID)
  groupID = tostring(groupID or "")
  self.deleteArmedUntil = nil
  self.selectedGroupID = groupID
  if groupID == "" or not ns.SettingsData or not ns.SettingsData.GetGroupConfig then
    self.model = nil
  else
    local cfg = ns.SettingsData:GetGroupConfig(groupID)
    self.model = {
      groupName = tostring(cfg.name or ""),
      groupDirection = tostring(cfg.layout.direction or "RIGHT"),
      groupSpacing = tonumber(cfg.layout.spacing) or 4,
      groupSort = tostring(cfg.layout.sort or "list"),
      groupWrapAfter = tonumber(cfg.layout.wrapAfter) or 0,
      groupOffsetX = tonumber(cfg.layout.nudgeX) or 0,
      groupOffsetY = tonumber(cfg.layout.nudgeY) or 0,
    }
  end
  self:RenderList()
  self:RenderEditor()
  self:RenderMembers()
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
end

function GroupsPanel:RenderList()
  local rows = self:BuildRows()
  local width = math.max(120, (self.listScroll and self.listScroll:GetWidth() or 0) - 8)
  local y = -2
  self.rowButtons = self.rowButtons or {}
  local used = {}

  for i = 1, #rows do
    local row = rows[i]
    local btn = self.rowButtons[i]
    if not btn then
      btn = CreateFrame("Button", nil, self.listChild)
      btn:SetHeight(28)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      btn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.55)
      btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      btn.name:SetPoint("LEFT", 8, 0)
      btn.name:SetPoint("RIGHT", -46, 0)
      btn.name:SetJustifyH("LEFT")
      btn.count = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      btn.count:SetPoint("RIGHT", -8, 0)
      if Skin and Skin.ApplyClickableRow then
        Skin:ApplyClickableRow(btn, "row")
      end
      btn:SetScript("OnClick", function(selfBtn)
        self:LoadGroup(selfBtn.groupID)
      end)
      btn:SetScript("OnReceiveDrag", function(selfBtn)
        self:AssignDraggedAuraToGroup(selfBtn.groupID)
      end)
      btn:SetScript("OnEnter", function(selfBtn)
        local draggingAuraId = UI and UI.State and UI.State.GetDraggingAura and UI.State:GetDraggingAura() or nil
        if draggingAuraId then
          selfBtn.bg:SetColorTexture(0.18, 0.24, 0.30, 0.92)
        end
      end)
      btn:SetScript("OnLeave", function(selfBtn)
        local selected = selfBtn.groupID == self.selectedGroupID
        if Skin and Skin.SetClickableRowState then
          Skin:SetClickableRowState(selfBtn, selected and "selected" or "normal")
        else
          selfBtn.bg:SetColorTexture(selected and 0.18 or 0.06, selected and 0.36 or 0.11, selected and 0.56 or 0.20, selected and 0.88 or 0.55)
        end
      end)
      self.rowButtons[i] = btn
    end

    used[i] = true
    btn.groupID = row.id
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", 0, y)
    btn:SetWidth(width)
    btn.name:SetText(tostring(row.name or row.id))
    btn.count:SetText(tostring(row.count or 0))
    local selected = row.id == self.selectedGroupID
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, selected and "selected" or "normal")
    else
      btn.bg:SetColorTexture(selected and 0.18 or 0.06, selected and 0.36 or 0.11, selected and 0.56 or 0.20, selected and 0.88 or 0.55)
    end
    btn:Show()
    y = y - 30
  end

  for i, btn in pairs(self.rowButtons) do
    if not used[i] then
      btn:Hide()
    end
  end

  self.listChild:SetWidth(width)
  self.listChild:SetHeight(math.max(1, -y + 8))
end

function GroupsPanel:ClearEditor()
  for i = 1, #(self.fieldWidgets or {}) do
    self.fieldWidgets[i]:Hide()
    self.fieldWidgets[i]:SetParent(nil)
    self.fieldWidgets[i] = nil
  end
  self.fieldWidgets = {}
end

function GroupsPanel:BuildMemberRows()
  if not self.selectedGroupID or self.selectedGroupID == "" or not ns.SettingsData or not ns.SettingsData.ListGroupMembers then
    return {}
  end
  return ns.SettingsData:ListGroupMembers(self.selectedGroupID)
end

function GroupsPanel:RenderMembers()
  self.memberRows = self.memberRows or {}
  local rows = self:BuildMemberRows()
  local width = math.max(180, (self.membersScroll and self.membersScroll:GetWidth() or 0) - 8)
  local y = -2
  local used = {}

  for i = 1, #rows do
    local row = rows[i]
    local btn = self.memberRows[i]
    if not btn then
      btn = CreateFrame("Button", nil, self.membersChild)
      btn:SetHeight(26)
      btn.bg = btn:CreateTexture(nil, "BACKGROUND")
      btn.bg:SetAllPoints()
      btn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.45)
      btn.name = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn.name:SetPoint("LEFT", 6, 0)
      btn.name:SetPoint("RIGHT", -90, 0)
      btn.name:SetJustifyH("LEFT")
      btn.meta = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
      btn.meta:SetPoint("RIGHT", -6, 0)
      if Skin and Skin.ApplyClickableRow then
        Skin:ApplyClickableRow(btn, "row")
      end
      btn:SetScript("OnClick", function(selfBtn)
        self.selectedMemberKey = selfBtn.entryKey
        self:RenderMembers()
      end)
      self.memberRows[i] = btn
    end

    used[i] = true
    btn.entryKey = row.key
    btn:ClearAllPoints()
    btn:SetPoint("TOPLEFT", 0, y)
    btn:SetWidth(width)
    btn.name:SetText(tostring(row.name or "Aura"))
    btn.meta:SetText(string.format("%s | %s", tostring(row.unit or "player"), tostring(row.spellID or "")))
    local selected = row.key == self.selectedMemberKey
    if Skin and Skin.SetClickableRowState then
      Skin:SetClickableRowState(btn, selected and "selected" or "normal")
    end
    btn:Show()
    y = y - 28
  end

  for i, btn in pairs(self.memberRows) do
    if not used[i] then
      btn:Hide()
    end
  end

  self.membersChild:SetWidth(width)
  self.membersChild:SetHeight(math.max(1, -y + 8))
  if self.btnMoveUp then
    self.btnMoveUp:SetEnabled(self.selectedMemberKey ~= nil)
    self.btnMoveDown:SetEnabled(self.selectedMemberKey ~= nil)
    self.btnUngroupAura:SetEnabled(self.selectedMemberKey ~= nil)
  end
end

function GroupsPanel:RenderEditor()
  self:ClearEditor()
  if not self.model then
    self.emptyText:Show()
    self.btnSave:Disable()
    self.btnDelete:Disable()
    return
  end

  self.emptyText:Hide()
  self.btnSave:Enable()
  self.btnDelete:Enable()
  if self.selectedAuraHint then
    local selectedAura = self:GetSelectedAuraContext()
    if selectedAura then
      local suffix = (selectedAura.groupID ~= "") and ("Current group: " .. selectedAura.groupID) or "Currently ungrouped"
      self.selectedAuraHint:SetText("Selected aura: " .. selectedAura.name .. " | " .. suffix)
    else
      self.selectedAuraHint:SetText("Select an aura from the library to add it quickly to this group.")
    end
  end

  local y = -4
  local lastWidget = nil
  for i = 1, #GROUP_FIELDS do
    local widget = FieldFactory:CreateField(self.editorBody, GROUP_FIELDS[i], self.model, function(key, value)
      self.model[key] = value
    end)
    widget:SetPoint("TOPLEFT", 0, y)
    widget:SetPoint("RIGHT", -4, 0)
    widget:Show()
    y = y - widget:GetHeight() - 8
    lastWidget = widget
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
  end

  if self.membersLabel then
    self.membersLabel:ClearAllPoints()
    if lastWidget then
      self.membersLabel:SetPoint("TOPLEFT", lastWidget, "BOTTOMLEFT", 0, -12)
    else
      self.membersLabel:SetPoint("TOPLEFT", self.editorBody, "TOPLEFT", 0, -4)
    end
  end
  if self.selectedAuraHint then
    self.selectedAuraHint:ClearAllPoints()
    self.selectedAuraHint:SetPoint("TOPLEFT", self.membersLabel, "BOTTOMLEFT", 0, -4)
    self.selectedAuraHint:SetPoint("RIGHT", -12, 0)
  end
  if self.membersScroll then
    self.membersScroll:ClearAllPoints()
    self.membersScroll:SetPoint("TOPLEFT", self.selectedAuraHint, "BOTTOMLEFT", 0, -6)
    self.membersScroll:SetPoint("BOTTOMRIGHT", self.footerBar, "TOPRIGHT", -26, 8)
  end
end

function GroupsPanel:SaveCurrent()
  if not self.selectedGroupID or self.selectedGroupID == "" or not self.model or not ns.SettingsData or not ns.SettingsData.UpdateGroupConfig then
    return
  end
  for i = 1, #(self.fieldWidgets or {}) do
    local widget = self.fieldWidgets[i]
    local field = widget and widget.field
    local control = widget and widget.control
    if field and control and field.key then
      if field.widget == "spinner" and control.GetNumber then
        self.model[field.key] = tonumber(control:GetNumber()) or tonumber(self.model[field.key]) or tonumber(field.default) or 0
      elseif field.widget == "dropdown" and control.GetValue then
        self.model[field.key] = control:GetValue()
      elseif field.widget == "text" and control.GetText then
        self.model[field.key] = tostring(control:GetText() or "")
      end
    end
  end
  ns.SettingsData:UpdateGroupConfig(self.selectedGroupID, self.model)
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end
  self:LoadGroup(self.selectedGroupID)
  if E and E.Names and E.Names.FILTER_CHANGED then
    E:Emit(E.Names.FILTER_CHANGED, { key = "groups", value = self.selectedGroupID })
  end
end

function GroupsPanel:AddSelectedAuraToCurrentGroup()
  local state = UI and UI.State and UI.State.Get and UI.State:Get() or {}
  local auraId = state and state.selectedAuraId
  if not auraId or auraId == "" or not self.selectedGroupID or self.selectedGroupID == "" or not ns.SettingsData or not ns.SettingsData.SetEntryGroup then
    return
  end
  if ns.SettingsData:SetEntryGroup(auraId, self.selectedGroupID) then
    self.selectedMemberKey = auraId
    self:RenderList()
    self:RenderMembers()
  end
end

function GroupsPanel:UngroupSelectedAura()
  if not self.selectedMemberKey or not ns.SettingsData or not ns.SettingsData.SetEntryGroup then
    return
  end
  if ns.SettingsData:SetEntryGroup(self.selectedMemberKey, "") then
    self.selectedMemberKey = nil
    self:RenderList()
    self:RenderMembers()
  end
end

function GroupsPanel:MoveSelectedMember(direction)
  if not self.selectedGroupID or self.selectedGroupID == "" or not self.selectedMemberKey or not ns.SettingsData or not ns.SettingsData.MoveGroupMember then
    return
  end
  if ns.SettingsData:MoveGroupMember(self.selectedGroupID, self.selectedMemberKey, direction) then
    self:RenderMembers()
  end
end

function GroupsPanel:DeleteCurrent()
  if not self.selectedGroupID or self.selectedGroupID == "" or not ns.SettingsData or not ns.SettingsData.DeleteGroup then
    return
  end
  local now = GetTime and GetTime() or 0
  if not self.deleteArmedUntil or self.deleteArmedUntil < now then
    self.deleteArmedUntil = now + 4
    if self.RefreshDeleteButton then
      self:RefreshDeleteButton()
    end
    return
  end
  ns.SettingsData:DeleteGroup(self.selectedGroupID)
  self.deleteArmedUntil = nil
  self.selectedGroupID = nil
  self.model = nil
  self:RenderList()
  self:RenderEditor()
  if self.RefreshDeleteButton then
    self:RefreshDeleteButton()
  end
  if E and E.Names and E.Names.FILTER_CHANGED then
    E:Emit(E.Names.FILTER_CHANGED, { key = "groups_delete", value = true })
  end
end

function GroupsPanel:ExportCurrent()
  if not self.selectedGroupID or self.selectedGroupID == "" or not ns.ImportExport or not ns.ImportExport.ExportGroupString then
    return
  end
  local text, err = ns.ImportExport:ExportGroupString(self.selectedGroupID)
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

function GroupsPanel:Create(parent)
  local o = setmetatable({}, self)

  o.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  o.frame:SetSize(760, 654)
  applyFloatingWindowChrome(o.frame)
  createBackdrop(o.frame)
  o.frame:Hide()

  function o:RefreshDeleteButton()
    if not self.btnDelete then
      return
    end
    local now = GetTime and GetTime() or 0
    local armed = self.deleteArmedUntil and self.deleteArmedUntil >= now
    self.btnDelete:SetText(armed and "Confirm Delete" or "Delete Group")
  end

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 14, -16)
  title:SetText("Group Studio")
  title:SetTextColor(0.98, 0.88, 0.34)
  attachDragHandle(o.frame, title)

  local subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", 14, -34)
  subtitle:SetPoint("RIGHT", -14, 0)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetWordWrap(true)
  subtitle:SetText("Compose shared group layouts, then manage the auras inside them.")
  attachDragHandle(o.frame, subtitle)

  o.listPane = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  if Skin and Skin.ApplyInsetPanel then
    Skin:ApplyInsetPanel(o.listPane)
  else
    createBackdrop(o.listPane)
  end
  o.listPane:SetPoint("TOPLEFT", 14, -88)
  o.listPane:SetPoint("BOTTOMLEFT", 14, 52)
  o.listPane:SetWidth(224)

  o.editorPane = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  if Skin and Skin.ApplyInsetPanel then
    Skin:ApplyInsetPanel(o.editorPane)
  else
    createBackdrop(o.editorPane)
  end
  o.editorPane:SetPoint("TOPLEFT", o.listPane, "TOPRIGHT", 8, 0)
  o.editorPane:SetPoint("BOTTOMRIGHT", -14, 52)

  if Widgets.SectionHeaderWidget and Widgets.SectionHeaderWidget.Create then
    o.listHeader = Widgets.SectionHeaderWidget:Create(o.listPane, {
      title = "Groups",
      helpTitle = "Groups",
      helpBody = "Groups act like shared containers. Their mover, direction, spacing, and order affect every aura inside them.",
      compact = true,
      lineWidth = 42,
    })
    o.listHeader:SetPoint("TOPLEFT", 6, -4)
    o.listHeader:SetPoint("TOPRIGHT", -6, -4)
    attachDragHandle(o.frame, o.listHeader)

    o.editorHeader = Widgets.SectionHeaderWidget:Create(o.editorPane, {
      title = "Group Settings",
      helpTitle = "Group Settings",
      helpBody = "Edit layout behavior, then manage which auras belong to the selected group.",
      compact = true,
      lineWidth = 56,
    })
    o.editorHeader:SetPoint("TOPLEFT", 8, -4)
    o.editorHeader:SetPoint("TOPRIGHT", -8, -4)
    attachDragHandle(o.frame, o.editorHeader)
  end

  o.footerBar = CreateFrame("Frame", nil, o.editorPane)
  o.footerBar:SetPoint("BOTTOMLEFT", 10, 10)
  o.footerBar:SetPoint("BOTTOMRIGHT", -10, 10)
  o.footerBar:SetHeight(62)

  o.footerLine = o.footerBar:CreateTexture(nil, "ARTWORK")
  o.footerLine:SetPoint("TOPLEFT", 0, 0)
  o.footerLine:SetPoint("TOPRIGHT", 0, 0)
  o.footerLine:SetHeight(1)
  do
    local r, g, b = 0.94, 0.78, 0.18
    local _, classToken = UnitClass and UnitClass("player") or nil
    local color = classToken and RAID_CLASS_COLORS and RAID_CLASS_COLORS[classToken] or nil
    if color then
      r, g, b = color.r or r, color.g or g, color.b or b
    end
    o.footerLine:SetColorTexture(r, g, b, 0.72)
  end

  o.footerTop = CreateFrame("Frame", nil, o.footerBar)
  o.footerTop:SetPoint("TOPLEFT", 0, -6)
  o.footerTop:SetPoint("TOPRIGHT", 0, 0)
  o.footerTop:SetHeight(24)

  o.footerBottom = CreateFrame("Frame", nil, o.footerBar)
  o.footerBottom:SetPoint("BOTTOMLEFT", 0, 2)
  o.footerBottom:SetPoint("BOTTOMRIGHT", 0, 2)
  o.footerBottom:SetHeight(24)

  o.listScroll = CreateFrame("ScrollFrame", nil, o.listPane, "UIPanelScrollFrameTemplate")
  o.listScroll:SetPoint("TOPLEFT", 6, -70)
  o.listScroll:SetPoint("BOTTOMRIGHT", -12, 6)
  o.listChild = CreateFrame("Frame", nil, o.listScroll)
  o.listChild:SetSize(1, 1)
  o.listScroll:SetScrollChild(o.listChild)
  o.listScroll:SetScript("OnSizeChanged", function()
    o:RenderList()
  end)

  o.listHint = o.listPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.listHint:SetPoint("TOPLEFT", 8, -20)
  o.listHint:SetPoint("RIGHT", -24, 0)
  o.listHint:SetJustifyH("LEFT")
  o.listHint:SetJustifyV("TOP")
  o.listHint:SetWordWrap(true)
  o.listHint:SetText("Drag an aura from the library onto a group row to assign it.")

  o.editorBody = CreateFrame("Frame", nil, o.editorPane)
  o.editorBody:SetPoint("TOPLEFT", 10, -28)
  o.editorBody:SetPoint("TOPRIGHT", -10, -28)
  o.editorBody:SetHeight(350)

  o.membersLabel = o.editorPane:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.membersLabel:SetPoint("TOPLEFT", o.editorBody, "BOTTOMLEFT", 0, -12)
  o.membersLabel:SetText("Members")
  o.membersLabel:SetTextColor(0.98, 0.86, 0.22)

  o.selectedAuraHint = o.editorPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.selectedAuraHint:SetPoint("TOPLEFT", o.membersLabel, "BOTTOMLEFT", 0, -4)
  o.selectedAuraHint:SetPoint("RIGHT", -12, 0)
  o.selectedAuraHint:SetJustifyH("LEFT")
  o.selectedAuraHint:SetJustifyV("TOP")
  o.selectedAuraHint:SetText("Select an aura from the library to add it quickly to this group.")

  o.membersScroll = CreateFrame("ScrollFrame", nil, o.editorPane, "UIPanelScrollFrameTemplate")
  o.membersChild = CreateFrame("Frame", nil, o.membersScroll)
  o.membersChild:SetSize(1, 1)
  o.membersScroll:SetScrollChild(o.membersChild)
  o.membersScroll:SetScript("OnSizeChanged", function()
    o:RenderMembers()
  end)

  o.emptyText = o.editorPane:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.emptyText:SetPoint("TOPLEFT", 12, -34)
  o.emptyText:SetPoint("RIGHT", -12, 0)
  o.emptyText:SetJustifyH("LEFT")
  o.emptyText:SetText("Select a group from the browser to shape its shared layout, then manage its member stack below.")

  o.btnSave = makeButton(o.frame, "Save Group", 96, "primary", function()
    o:SaveCurrent()
  end)
  o.btnSave:SetParent(o.footerTop)
  o.btnSave:SetPoint("LEFT", o.footerTop, "LEFT", 0, 0)

  o.btnDelete = makeButton(o.frame, "Delete Group", 118, "danger", function()
    o:DeleteCurrent()
  end)
  o.btnDelete:SetParent(o.footerTop)
  o.btnDelete:SetPoint("LEFT", o.btnSave, "RIGHT", 8, 0)
  o:RefreshDeleteButton()

  o.btnAddSelected = makeButton(o.frame, "Add Selected", 122, "default", function()
    o:AddSelectedAuraToCurrentGroup()
  end)
  o.btnAddSelected:SetParent(o.footerTop)
  o.btnAddSelected:SetPoint("LEFT", o.btnDelete, "RIGHT", 8, 0)

  o.btnClose = makeButton(o.frame, "Close", 82, "ghost", function()
    o.frame:Hide()
  end)
  o.btnClose:SetParent(o.footerTop)
  o.btnClose:SetPoint("RIGHT", o.footerTop, "RIGHT", 0, 0)

  o.btnMoveUp = makeButton(o.frame, "Up", 44, "ghost", function()
    o:MoveSelectedMember("up")
  end)
  o.btnMoveUp:SetParent(o.footerBottom)
  o.btnMoveUp:SetPoint("LEFT", o.footerBottom, "LEFT", 0, 0)

  o.btnMoveDown = makeButton(o.frame, "Down", 50, "ghost", function()
    o:MoveSelectedMember("down")
  end)
  o.btnMoveDown:SetParent(o.footerBottom)
  o.btnMoveDown:SetPoint("LEFT", o.btnMoveUp, "RIGHT", 6, 0)

  o.btnUngroupAura = makeButton(o.frame, "Ungroup", 88, "ghost", function()
    o:UngroupSelectedAura()
  end)
  o.btnUngroupAura:SetParent(o.footerBottom)
  o.btnUngroupAura:SetPoint("LEFT", o.btnMoveDown, "RIGHT", 6, 0)

  o.btnExport = makeButton(o.frame, "Export", 82, "ghost", function()
    o:ExportCurrent()
  end)
  o.btnExport:SetParent(o.footerBottom)
  o.btnExport:SetPoint("LEFT", o.btnUngroupAura, "RIGHT", 8, 0)

  o.deleteHint = o.footerTop:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.deleteHint:SetPoint("LEFT", o.btnAddSelected, "RIGHT", 10, 0)
  o.deleteHint:SetPoint("RIGHT", o.btnClose, "LEFT", -10, 0)
  o.deleteHint:SetJustifyH("LEFT")
  o.deleteHint:SetJustifyV("MIDDLE")
  o.deleteHint:SetWordWrap(false)
  o.deleteHint:SetText("Deleting a group keeps its auras as standalone entries.")

  if E then
    E:On(E.Names.OPEN_GROUPS_PANEL, function(payload)
      o.frame:ClearAllPoints()
      o.frame:SetPoint("CENTER", UIParent, "CENTER", 36, 10)
      o.frame:Raise()
      o.frame:SetShown(not o.frame:IsShown())
      if o.frame:IsShown() then
        local selectedAura = o:GetSelectedAuraContext()
        local preferredGroupID = selectedAura and selectedAura.groupID or nil
        o:LoadGroup(preferredGroupID ~= "" and preferredGroupID or o.selectedGroupID or (((ns.SettingsData and ns.SettingsData.ListGroupsDetailed and ns.SettingsData:ListGroupsDetailed()) or {})[1] or {}).id)
      end
    end)
    E:On(E.Names.AURA_SELECTED, function()
      if o.frame and o.frame:IsShown() then
        o:RenderEditor()
      end
    end)
  end

  o.fieldWidgets = {}
  o:RenderList()
  o:RenderEditor()
  o:RenderMembers()
  return o
end

Panels.GroupsPanel = GroupsPanel
UI.GroupsPanel = GroupsPanel
