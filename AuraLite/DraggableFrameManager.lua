local _, ns = ...

ns.Dragger = ns.Dragger or {}
local D = ns.Dragger

D.pendingPositions = D.pendingPositions or {}

function D:ApplyPosition(frame, key)
  if not ns.db or not ns.db.positions then
    return
  end
  local p = ns.db.positions[key]
  if type(p) ~= "table" then
    return
  end
  if InCombatLockdown() then
    self.pendingPositions[key] = true
    return
  end
  frame:ClearAllPoints()
  frame:SetPoint(p.point or "CENTER", UIParent, p.relativePoint or "CENTER", tonumber(p.x) or 0, tonumber(p.y) or 0)
  self.pendingPositions[key] = nil
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
  ns.db.positions[key] = {
    point = point,
    relativePoint = relativePoint,
    x = x,
    y = y,
  }
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
  if unlocked then
    frame.dragHandle:Show()
  else
    frame.dragHandle:Hide()
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
    handle:SetColorTexture(0.1, 0.6, 1.0, 0.12)
    frame.dragHandle = handle
  end

  frame:SetScript("OnDragStart", function(f)
    if ns.db.locked then
      return
    end

    if InCombatLockdown() then
      DEFAULT_CHAT_FRAME:AddMessage("|cffff5555AuraLite|r: Can't move trackers in combat.")
      return
    end

    f:StartMoving()
  end)

  frame:SetScript("OnDragStop", function(f)
    f:StopMovingOrSizing()
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
