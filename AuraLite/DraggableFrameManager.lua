local _, ns = ...

ns.Dragger = ns.Dragger or {}
local D = ns.Dragger

D.pendingPositions = D.pendingPositions or {}

function D:ApplyPosition(frame, key)
  if not ns.db or not ns.db.positions then
    return
  end
  if frame and frame._alDragging then
    return
  end
  local p = ns.db.positions[key]
  if type(p) ~= "table" and ns.SettingsData and ns.SettingsData.ResolveEntry and type(frame) == "table" and type(frame._alEntryKeys) == "table" then
    for entryKey in pairs(frame._alEntryKeys) do
      local entry = ns.SettingsData:ResolveEntry(entryKey)
      local savedPos = entry and entry.item and entry.item.savedPosition
      if type(savedPos) == "table" then
        p = {
          point = savedPos.point,
          relativePoint = savedPos.relativePoint,
          x = savedPos.x,
          y = savedPos.y,
        }
        ns.db.positions[key] = p
        break
      end
    end
  end
  if type(p) ~= "table" then
    return
  end

  local function applyNow()
    frame:ClearAllPoints()
    frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", tonumber(p.x) or 0, tonumber(p.y) or 0)
    frame._alPositionApplied = true
    self.pendingPositions[key] = nil
  end

  if InCombatLockdown() then
    if frame and frame.GetNumPoints and frame:GetNumPoints() == 0 then
      applyNow()
      return
    end
    self.pendingPositions[key] = true
    return
  end
  applyNow()
end

function D:ApplyPendingPositions()
  if InCombatLockdown() then
    return
  end
  if not ns.GroupManager or not ns.GroupManager.frames then
    return
  end
  for key in pairs(self.pendingPositions) do
    local frame = ns.GroupManager.frames[key]
    if frame then
      self:ApplyPosition(frame, key)
    else
      self.pendingPositions[key] = nil
    end
  end
end

function D:SavePosition(frame, key)
  if not ns.db or not ns.db.positions then
    return
  end
  local point, _, relativePoint, x, y = frame:GetPoint(1)
  local pos = {
    point = point,
    relativePoint = relativePoint,
    x = x,
    y = y,
  }
  ns.db.positions[key] = pos
  if type(frame) == "table" and type(frame._alMirrorPositionKeys) == "table" then
    for mirrorKey in pairs(frame._alMirrorPositionKeys) do
      if type(mirrorKey) == "string" and mirrorKey ~= "" then
        ns.db.positions[mirrorKey] = {
          point = pos.point,
          relativePoint = pos.relativePoint,
          x = pos.x,
          y = pos.y,
        }
      end
    end
  end
  if ns.SettingsData and ns.SettingsData.ResolveEntry and type(frame) == "table" and type(frame._alEntryKeys) == "table" then
    for entryKey in pairs(frame._alEntryKeys) do
      local entry = ns.SettingsData:ResolveEntry(entryKey)
      if entry and entry.item then
        entry.item.savedPosition = {
          point = pos.point,
          relativePoint = pos.relativePoint,
          x = pos.x,
          y = pos.y,
        }
      end
    end
  end
  frame._alPositionApplied = true
end

function D:CanMove()
  if not ns.db then
    return false
  end
  if ns.db.locked then
    return false
  end
  if InCombatLockdown() then
    return false
  end
  return true
end

function D:SetGroupVisualState(frame)
  if not frame or not frame.dragHandle then
    return
  end
  if InCombatLockdown() then
    return
  end

  local unlocked = ns.db and ns.db.locked == false
  frame.dragHandle:SetShown(unlocked)
  if frame.dragOutline then
    for i = 1, #frame.dragOutline do
      frame.dragOutline[i]:SetShown(unlocked and frame._alDragging == true)
    end
  end
  if frame.icons then
    for i = 1, #frame.icons do
      local icon = frame.icons[i]
      if icon and icon.EnableMouse then
        icon:EnableMouse(not unlocked)
      end
    end
  end
end

function D:MakeMovable(frame, key)
  frame:SetMovable(true)
  frame:SetClampedToScreen(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")

  if not frame.dragHandle then
    local handle = frame:CreateTexture(nil, "BACKGROUND")
    handle:SetAllPoints()
    handle:SetColorTexture(0, 0, 0, 0)
    frame.dragHandle = handle

    frame.dragOutline = {}
    frame.dragOutline[1] = frame:CreateTexture(nil, "OVERLAY")
    frame.dragOutline[1]:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    frame.dragOutline[1]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    frame.dragOutline[1]:SetHeight(1)
    frame.dragOutline[1]:SetColorTexture(0.95, 0.78, 0.22, 0.45)
    frame.dragOutline[1]:Hide()

    frame.dragOutline[2] = frame:CreateTexture(nil, "OVERLAY")
    frame.dragOutline[2]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -2, -2)
    frame.dragOutline[2]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    frame.dragOutline[2]:SetHeight(1)
    frame.dragOutline[2]:SetColorTexture(0.95, 0.78, 0.22, 0.45)
    frame.dragOutline[2]:Hide()

    frame.dragOutline[3] = frame:CreateTexture(nil, "OVERLAY")
    frame.dragOutline[3]:SetPoint("TOPLEFT", frame, "TOPLEFT", -2, 2)
    frame.dragOutline[3]:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", -2, -2)
    frame.dragOutline[3]:SetWidth(1)
    frame.dragOutline[3]:SetColorTexture(0.95, 0.78, 0.22, 0.45)
    frame.dragOutline[3]:Hide()

    frame.dragOutline[4] = frame:CreateTexture(nil, "OVERLAY")
    frame.dragOutline[4]:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 2, 2)
    frame.dragOutline[4]:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", 2, -2)
    frame.dragOutline[4]:SetWidth(1)
    frame.dragOutline[4]:SetColorTexture(0.95, 0.78, 0.22, 0.45)
    frame.dragOutline[4]:Hide()
  end

  frame:SetScript("OnDragStart", function(f)
    if ns.db.locked then
      return
    end

    if InCombatLockdown() then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff5555AuraLite|r: Can't move trackers in combat.")
      return
    end

    f._alDragging = true
    self:SetGroupVisualState(f)
    f:StartMoving()
  end)

  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
    f._alDragging = false
    self:SetGroupVisualState(f)
    self:SavePosition(f, key)
  end)

  self:ApplyPosition(frame, key)
  self:SetGroupVisualState(frame)
end

function D:SetLocked(locked)
  ns.db.locked = locked == true
  if ns.GroupManager then
    ns.GroupManager:RefreshDragState()
  end
end
