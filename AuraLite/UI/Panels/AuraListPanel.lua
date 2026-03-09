local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State

local AuraListPanel = {}
AuraListPanel.__index = AuraListPanel

local STATUS_COLORS = {
  ok = { 0.2, 0.95, 0.3 },
  warn = { 1.0, 0.82, 0.1 },
  error = { 1.0, 0.3, 0.3 },
}

local MOCK_AURAS = {
  { id = "aura_1278009", spellID = 1278009, name = "Phalanx", unit = "player", group = "Important Procs", trigger = "Cast", status = "ok", icon = 132341 },
  { id = "aura_871", spellID = 871, name = "Shield Wall", unit = "player", group = "Defensives", trigger = "Aura", status = "ok", icon = 132362 },
  { id = "aura_589", spellID = 589, name = "Shadow Word: Pain", unit = "target", group = "Target Debuffs", trigger = "Aura", status = "warn", icon = 136207 },
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
  frame:SetBackdropColor(0.03, 0.06, 0.11, 0.75)
  frame:SetBackdropBorderColor(0.1, 0.42, 0.72, 0.85)
end

function AuraListPanel:BuildRows()
  local rows = nil
  if UI.AuraRepository and UI.AuraRepository.ListAuras then
    rows = UI.AuraRepository:ListAuras(S and S:Get() or nil)
  end
  if type(rows) ~= "table" then
    rows = MOCK_AURAS
  end

  local search = ""
  if S and S.Get then
    local state = S:Get()
    search = lowerSafe(state.filters and state.filters.search or "")
  end

  if search == "" then
    return rows
  end

  local filtered = {}
  for i = 1, #rows do
    local row = rows[i]
    local hay = lowerSafe(row.name) .. " " .. lowerSafe(row.group) .. " " .. lowerSafe(row.unit) .. " " .. tostring(row.spellID or "")
    if hay:find(search, 1, true) then
      filtered[#filtered + 1] = row
    end
  end
  return filtered
end

function AuraListPanel:AcquireRow(index)
  self.rowButtons = self.rowButtons or {}
  local btn = self.rowButtons[index]
  if btn then
    return btn
  end

  btn = CreateFrame("Button", nil, self.scrollChild)
  btn:SetHeight(30)

  btn.bg = btn:CreateTexture(nil, "BACKGROUND")
  btn.bg:SetAllPoints()
  btn.bg:SetColorTexture(0.06, 0.1, 0.17, 0.4)

  btn.icon = btn:CreateTexture(nil, "ARTWORK")
  btn.icon:SetPoint("LEFT", 6, 0)
  btn.icon:SetSize(20, 20)

  btn.nameText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  btn.nameText:SetPoint("TOPLEFT", btn.icon, "TOPRIGHT", 8, 0)
  btn.nameText:SetPoint("RIGHT", -90, 0)
  btn.nameText:SetJustifyH("LEFT")

  btn.metaText = btn:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  btn.metaText:SetPoint("BOTTOMLEFT", btn.icon, "BOTTOMRIGHT", 8, 0)
  btn.metaText:SetPoint("RIGHT", -90, 0)
  btn.metaText:SetJustifyH("LEFT")

  btn.statusText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  btn.statusText:SetPoint("RIGHT", -8, 0)

  btn:SetScript("OnClick", function(selfBtn)
    if S and S.SetSelectedAura then
      S:SetSelectedAura(selfBtn.auraId, "list")
    end
  end)

  btn:SetScript("OnEnter", function(selfBtn)
    selfBtn.bg:SetColorTexture(0.1, 0.2, 0.3, 0.65)
  end)

  btn:SetScript("OnLeave", function(selfBtn)
    if selfBtn.auraId and selfBtn.auraId == self.selectedAuraId then
      selfBtn.bg:SetColorTexture(0.16, 0.3, 0.46, 0.8)
    else
      selfBtn.bg:SetColorTexture(0.06, 0.1, 0.17, 0.4)
    end
  end)

  self.rowButtons[index] = btn
  return btn
end

function AuraListPanel:Render()
  local rows = self:BuildRows()
  local width = self.scrollChild:GetWidth() - 8
  local y = -2

  for i = 1, #rows do
    local row = rows[i]
    local btn = self:AcquireRow(i)
    btn:SetPoint("TOPLEFT", 2, y)
    btn:SetWidth(width)
    btn:Show()

    btn.auraId = row.id
    btn.icon:SetTexture(row.icon or 134400)
    btn.nameText:SetText(string.format("%s (%s)", tostring(row.name or "Aura"), tostring(row.spellID or "?")))
    btn.metaText:SetText(string.format("%s | %s | %s", tostring(row.unit or "player"), tostring(row.group or "Group"), tostring(row.trigger or "Rule")))

    local status = tostring(row.status or "ok")
    local color = STATUS_COLORS[status] or STATUS_COLORS.ok
    btn.statusText:SetText(status:upper())
    btn.statusText:SetTextColor(color[1], color[2], color[3])

    if row.id and row.id == self.selectedAuraId then
      btn.bg:SetColorTexture(0.16, 0.3, 0.46, 0.8)
    else
      btn.bg:SetColorTexture(0.06, 0.1, 0.17, 0.4)
    end

    y = y - 32
  end

  for i = #rows + 1, #(self.rowButtons or {}) do
    self.rowButtons[i]:Hide()
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

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.title:SetPoint("TOPLEFT", 8, -8)
  o.title:SetText("Auras")

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame, "UIPanelScrollFrameTemplate")
  o.scroll:SetPoint("TOPLEFT", 6, -28)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  o.scrollChild = CreateFrame("Frame", nil, o.scroll)
  o.scrollChild:SetPoint("TOPLEFT")
  o.scrollChild:SetSize(1, 1)
  o.scroll:SetScrollChild(o.scrollChild)

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
