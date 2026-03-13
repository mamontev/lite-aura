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
  for i = 1, #rows do
    local row = rows[i]
    local grp = tostring(row.group or "Ungrouped")
    if grp ~= currentGroup then
      currentGroup = grp
      out[#out + 1] = { isHeader = true, group = grp }
    end
    out[#out + 1] = row
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
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.08, 0.2, 0.34, 0.8)

    btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    btn.text:SetPoint("LEFT", 8, 0)
    btn.text:SetJustifyH("LEFT")
    if Skin and Skin.ApplyClickableRow then
      Skin:ApplyClickableRow(btn, "header")
    end
  else
    btn:SetHeight(30)
    btn.bg = btn:CreateTexture(nil, "BACKGROUND")
    btn.bg:SetAllPoints()
    btn.bg:SetColorTexture(0.06, 0.11, 0.20, 0.45)

    btn.icon = btn:CreateTexture(nil, "ARTWORK")
    btn.icon:SetPoint("LEFT", 6, 0)
    btn.icon:SetSize(22, 22)

    btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    btn.nameText:SetPoint("LEFT", btn.icon, "RIGHT", 8, 0)
    btn.nameText:SetPoint("RIGHT", -84, 0)
    btn.nameText:SetJustifyH("LEFT")

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
      btn.text:SetText(tostring(row.group or "Group"))
      y = y - 22
    else
      btn.auraId = row.id
      btn.icon:SetTexture(row.icon or 134400)

      local auraName = tostring(row.name or "")
      if auraName == "" then
        auraName = "Aura " .. tostring(row.spellID or "?")
      end
      btn.nameText:SetText(auraName)

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
