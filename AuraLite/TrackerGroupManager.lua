local _, ns = ...
local U = ns.Utils
local L = ns.Localization

ns.GroupManager = ns.GroupManager or {}
local G = ns.GroupManager

G.frames = G.frames or {}
G.activeByGroup = G.activeByGroup or {}
G.lastRestriction = false
G.stateByKey = G.stateByKey or {}
G.hasRendered = G.hasRendered or false
G.layoutSigByGroup = G.layoutSigByGroup or {}

local function getColorForUnit(unit)
  if unit == "player" then
    return 0.2, 0.8, 0.3
  end
  if unit == "target" then
    return 0.9, 0.3, 0.3
  end
  if unit == "focus" then
    return 0.9, 0.8, 0.2
  end
  if unit == "pet" then
    return 0.3, 0.7, 0.9
  end
  return 0.5, 0.5, 0.5
end

local function formatRemaining(value)
  if value <= 0 then
    return "0.0"
  end
  if value >= 10 then
    return string.format("%.0f", value)
  end
  return string.format("%.1f", value)
end

local validAnchors = {
  TOP = true,
  BOTTOM = true,
  LEFT = true,
  RIGHT = true,
  CENTER = true,
  TOPLEFT = true,
  TOPRIGHT = true,
  BOTTOMLEFT = true,
  BOTTOMRIGHT = true,
}

local function normalizeAnchor(anchor, fallback)
  anchor = tostring(anchor or ""):upper()
  if validAnchors[anchor] then
    return anchor
  end
  return fallback
end

local function normalizeOffset(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  n = math.floor(n + 0.5)
  if n > 200 then
    n = 200
  end
  if n < -200 then
    n = -200
  end
  return n
end

local function applyTextPosition(fontString, parent, anchor, x, y, fallbackAnchor, fallbackX, fallbackY)
  fontString:ClearAllPoints()
  fontString:SetPoint(
    normalizeAnchor(anchor, fallbackAnchor),
    parent,
    normalizeAnchor(anchor, fallbackAnchor),
    normalizeOffset(x, fallbackX),
    normalizeOffset(y, fallbackY)
  )
end

local function buildCustomText(row, remaining)
  local template = tostring(row and row.customText or "")
  if template == "" then
    return ""
  end

  local spellName = ""
  if row and row.spellID then
    spellName = ns.AuraAPI:GetSpellName(row.spellID) or ("Spell " .. tostring(row.spellID))
  end

  local auraName = tostring(row and row.displayName or "")
  if auraName == "" then
    auraName = spellName
  end

  local stacks = tostring((row and row.applications) or 0)
  local source = tostring((row and row.sourceLabel) or "")
  local unit = tostring((row and row.unit) or "")
  local durationText = ""
  if row and row.duration and row.duration > 0 then
    durationText = formatRemaining(row.duration)
  end

  if remaining == nil and row and row.canCompute and row.expirationTime then
    remaining = math.max(0, row.expirationTime - GetTime())
  end
  local remainingText = remaining and formatRemaining(remaining) or ""

  local text = template
  text = text:gsub("{spell}", spellName)
  text = text:gsub("{name}", auraName)
  text = text:gsub("{stacks}", stacks)
  text = text:gsub("{source}", source)
  text = text:gsub("{unit}", unit)
  text = text:gsub("{remaining}", remainingText)
  text = text:gsub("{duration}", durationText)
  return text
end

local function updateCustomText(icon, row, remaining)
  if not icon or not row then
    return
  end
  if type(row.customText) ~= "string" or row.customText == "" then
    icon.customText:SetText("")
    icon.customText:Hide()
    return
  end
  icon.customText:SetText(buildCustomText(row, remaining))
  icon.customText:SetShown(icon.customText:GetText() ~= "")
end

local function setIconBorderColor(icon, r, g, b, a)
  if not icon or not icon.borderEdges then
    return
  end
  local alpha = a or 0.9
  for i = 1, #icon.borderEdges do
    icon.borderEdges[i]:SetColorTexture(r, g, b, alpha)
  end
end

local function applyIconTexture(textureRegion, primary, fallback, row)
  local selected = ns.AuraAPI:SelectBestTexture(primary, fallback, 136243)
  textureRegion:SetTexture(selected)

  -- Some invalid paths do not throw but resolve to nil; force default icon in that case.
  if not textureRegion:GetTexture() then
    ns.Debug:Verbosef(
      "Icon texture unresolved, forcing default. spellID=%s primary=%s fallback=%s",
      tostring(row and row.spellID),
      tostring(primary),
      tostring(fallback)
    )
    textureRegion:SetTexture(136243)
  end
end

local function makeRowKey(row, fallbackGroupID)
  local unit = row.unit or "none"
  local groupID = row.groupID or fallbackGroupID or "group"
  local spellID = tonumber(row.spellID) or 0
  return unit .. "|" .. groupID .. "|" .. spellID
end

local function makeLayoutSignature(entries, iconSize, spacing, direction)
  local parts = {
    tostring(iconSize),
    tostring(spacing),
    tostring(direction),
    tostring(#entries),
  }
  for i = 1, #entries do
    local row = entries[i]
    parts[#parts + 1] = tostring(row.unit or "u")
    parts[#parts + 1] = tostring(row.groupID or "g")
    parts[#parts + 1] = tostring(tonumber(row.spellID) or 0)
    parts[#parts + 1] = tostring(row.timerVisual or "icon")
    parts[#parts + 1] = tostring(row.barTexture or "")
  end
  return table.concat(parts, ";")
end

local function createIcon(parent)
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(36, 36)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self)
    if not self.row then
      return
    end
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    if self.row.spellID then
      GameTooltip:SetSpellByID(self.row.spellID)
    end
    if self.row.displayName and self.row.displayName ~= "" then
      local prefix = (L and L.T and L:T("tooltip_aura")) or "Aura: "
      GameTooltip:AddLine(prefix .. self.row.displayName, 0.65, 0.95, 1.0)
    end
    if self.row.sourceLabel and self.row.sourceLabel ~= "" then
      local prefix = (L and L.T and L:T("tooltip_source")) or "Source: "
      GameTooltip:AddLine(prefix .. self.row.sourceLabel, 0.8, 0.8, 0.8)
    end
    GameTooltip:Show()
  end)
  f:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  f.bg = f:CreateTexture(nil, "BACKGROUND")
  f.bg:SetAllPoints()
  f.bg:SetColorTexture(0, 0, 0, 0.35)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetAllPoints()
  f.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

  f.borderEdges = {}
  f.borderEdges[1] = f:CreateTexture(nil, "OVERLAY")
  f.borderEdges[1]:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
  f.borderEdges[1]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1)
  f.borderEdges[1]:SetHeight(1)
  f.borderEdges[2] = f:CreateTexture(nil, "OVERLAY")
  f.borderEdges[2]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -1, -1)
  f.borderEdges[2]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
  f.borderEdges[2]:SetHeight(1)
  f.borderEdges[3] = f:CreateTexture(nil, "OVERLAY")
  f.borderEdges[3]:SetPoint("TOPLEFT", f, "TOPLEFT", -1, 1)
  f.borderEdges[3]:SetPoint("BOTTOMLEFT", f, "BOTTOMLEFT", -1, -1)
  f.borderEdges[3]:SetWidth(1)
  f.borderEdges[4] = f:CreateTexture(nil, "OVERLAY")
  f.borderEdges[4]:SetPoint("TOPRIGHT", f, "TOPRIGHT", 1, 1)
  f.borderEdges[4]:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", 1, -1)
  f.borderEdges[4]:SetWidth(1)
  setIconBorderColor(f, 0.2, 0.2, 0.2, 0.85)

  f.cooldown = CreateFrame("Cooldown", nil, f, "CooldownFrameTemplate")
  f.cooldown:SetAllPoints()
  f.cooldown:SetReverse(true)

  f.cdBarBG = f:CreateTexture(nil, "ARTWORK")
  f.cdBarBG:SetColorTexture(0, 0, 0, 0.55)
  f.cdBarBG:Hide()

  f.cdBar = CreateFrame("StatusBar", nil, f)
  f.cdBar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  f.cdBar:SetMinMaxValues(0, 1)
  f.cdBar:SetValue(0)
  f.cdBar:SetStatusBarColor(0.2, 0.9, 0.35, 0.95)
  f.cdBar:Hide()

    -- Dedicated text layer to keep text readable above status bars/cooldowns.
  f.textLayer = CreateFrame("Frame", nil, f)
  f.textLayer:SetAllPoints()
  f.textLayer:SetFrameLevel(f:GetFrameLevel() + 8)

  f.count = f.textLayer:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
  f.count:SetDrawLayer("OVERLAY", 7)
  f.count:SetPoint("BOTTOMRIGHT", -2, 2)

  f.timer = f.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.timer:SetDrawLayer("OVERLAY", 7)
  f.timer:SetPoint("TOP", f, "BOTTOM", 0, -1)

  f.source = f.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.source:SetDrawLayer("OVERLAY", 6)
  f.source:SetPoint("TOPLEFT", 2, -2)

  f.customText = f.textLayer:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.customText:SetDrawLayer("OVERLAY", 6)
  f.customText:SetPoint("BOTTOM", f, "TOP", 0, 2)
  f.customText:SetText("")

  f.lowGlow = f:CreateTexture(nil, "OVERLAY")
  f.lowGlow:SetAllPoints()
  f.lowGlow:SetColorTexture(1, 0.15, 0.1, 0.0)

  return f
end

local function createGroupFrame(groupID)
  local f = CreateFrame("Frame", nil, UIParent)
  f.groupID = groupID
  f.icons = {}
  f:SetSize(220, 44)

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  f.label:SetPoint("BOTTOMLEFT", 0, 2)

  f.back = f:CreateTexture(nil, "BACKGROUND")
  f.back:SetAllPoints()
  f.back:SetColorTexture(0, 0, 0, 0.12)

  ns.Dragger:MakeMovable(f, groupID)
  return f
end

function G:EnsureGroupFrame(groupID)
  if self.frames[groupID] then
    return self.frames[groupID]
  end
  local frame = createGroupFrame(groupID)
  self.frames[groupID] = frame
  return frame
end

function G:RefreshDragState()
  for _, frame in pairs(self.frames) do
    ns.Dragger:SetGroupVisualState(frame)
    if frame.back then
      if ns.db.locked then
        frame.back:Hide()
      else
        frame.back:Show()
      end
    end
  end
end

function G:SetRestrictionState(active)
  self.lastRestriction = active == true
end

function G:RenderLayout(frame, groupID, entries, groupConfig)
  local layout = (groupConfig and groupConfig.layout) or {}
  local iconSize = tonumber(layout.iconSize) or 36
  local spacing = tonumber(layout.spacing) or 4
  local direction = tostring(layout.direction or "RIGHT"):upper()

  if ns.db.options.compactMode then
    iconSize = math.max(24, iconSize - 8)
    spacing = math.max(1, spacing - 1)
  end

  local layoutSig = makeLayoutSignature(entries, iconSize, spacing, direction)
  local layoutChanged = self.layoutSigByGroup[groupID] ~= layoutSig
  if layoutChanged then
    self.layoutSigByGroup[groupID] = layoutSig
  end

  if not layoutChanged then
    return iconSize
  end

  local cursor = 0
  for idx, row in ipairs(entries) do
    local icon = frame.icons[idx]
    if not icon then
      icon = createIcon(frame)
      frame.icons[idx] = icon
    end

    local timerVisual = tostring(row.timerVisual or "icon"):lower()
    local hasSideBar = (timerVisual == "bar" or timerVisual == "iconbar")
    local barWidth = 0
    if hasSideBar then
      barWidth = math.floor(iconSize * 2.6)
      if barWidth < 90 then
        barWidth = 90
      elseif barWidth > 260 then
        barWidth = 260
      end
    end
    local slotWidth = iconSize + (hasSideBar and (6 + barWidth) or 0)
    icon._hasSideBar = hasSideBar
    icon._barWidth = barWidth
    icon._slotWidth = slotWidth
    icon._layoutDirection = direction
    icon:SetSize(iconSize, iconSize)
    icon:ClearAllPoints()

    if direction == "LEFT" then
      icon:SetPoint("RIGHT", frame, "RIGHT", -cursor, 0)
      cursor = cursor + slotWidth + spacing
    elseif direction == "UP" then
      icon:SetPoint("BOTTOM", frame, "BOTTOM", 0, cursor)
      cursor = cursor + iconSize + spacing
    elseif direction == "DOWN" then
      icon:SetPoint("TOP", frame, "TOP", 0, -cursor)
      cursor = cursor + iconSize + spacing
    else
      icon:SetPoint("LEFT", frame, "LEFT", cursor, 0)
      cursor = cursor + slotWidth + spacing
    end
  end

  for idx = #entries + 1, #frame.icons do
    local icon = frame.icons[idx]
    icon.row = nil
    icon:Hide()
  end

  local contentCount = #entries
  local width = 160
  local height = iconSize + 14
  if contentCount > 0 then
    if direction == "UP" or direction == "DOWN" then
      local maxSlotWidth = iconSize
      for idx = 1, #entries do
        local icon = frame.icons[idx]
        maxSlotWidth = math.max(maxSlotWidth, tonumber(icon and icon._slotWidth) or iconSize)
      end
      width = math.max(160, maxSlotWidth)
      height = math.max(iconSize + 14, (contentCount * (iconSize + spacing)) - spacing + 14)
    else
      width = math.max(160, cursor - spacing)
      height = iconSize + 14
    end
  end
  frame:SetSize(width, height)
  return iconSize
end

function G:Render(activeByGroup)
  self.activeByGroup = activeByGroup or {}
  local groupIDs = U.KeysSortedByNumberField(ns.db.groups, "order")
  local prevState = self.stateByKey or {}
  local nextState = {}
  local allowTransitionSound = self.hasRendered == true

  for i = 1, #groupIDs do
    local groupID = groupIDs[i]
    local groupConfig = ns.db.groups[groupID]
    local entries = self.activeByGroup[groupID] or {}
    local frame = self:EnsureGroupFrame(groupID)
    if ns.db and ns.db.locked == true then
      ns.Dragger:ApplyPosition(frame, groupID)
    elseif not frame._alPositionApplied then
      ns.Dragger:ApplyPosition(frame, groupID)
    end

    frame.label:SetText((groupConfig and groupConfig.name) or groupID)
    local iconSize = self:RenderLayout(frame, groupID, entries, groupConfig)

    for idx, row in ipairs(entries) do
      local icon = frame.icons[idx]
      if not icon then
        icon = createIcon(frame)
        frame.icons[idx] = icon
      end

      icon.row = row
      local baseLevel = icon:GetFrameLevel()
      if icon.cdBar and icon.cdBar.SetFrameLevel then
        icon.cdBar:SetFrameLevel(baseLevel + 1)
      end
      if icon.cooldown and icon.cooldown.SetFrameLevel then
        icon.cooldown:SetFrameLevel(baseLevel + 2)
      end
      if icon.textLayer and icon.textLayer.SetFrameLevel then
        icon.textLayer:SetFrameLevel(baseLevel + 8)
      end
      row.groupID = row.groupID or groupID
      row.stateKey = makeRowKey(row, groupID)
      applyIconTexture(icon.icon, row.icon, row.fallbackIcon, row)
      icon.count:SetText((row.applications and row.applications > 1) and row.applications or "")
      icon.source:SetText((ns.db.options.showSource and row.sourceLabel) or "")
      local barTexture = ns.AuraAPI and ns.AuraAPI:ResolveBarTexturePath(row.barTexture) or "Interface\\TargetingFrame\\UI-StatusBar"
      icon.cdBar:SetStatusBarTexture(barTexture)

      local timerVisual = tostring(row.timerVisual or "icon"):lower()
      local hasSideBar = (timerVisual == "bar" or timerVisual == "iconbar")
      local barWidth = tonumber(icon._barWidth) or math.max(90, math.floor(iconSize * 2.6))
      if hasSideBar then
        local barOnLeft = tostring(icon._layoutDirection or "RIGHT"):upper() == "LEFT"
        icon.cdBarBG:ClearAllPoints()
        if barOnLeft then
          icon.cdBarBG:SetPoint("TOPRIGHT", icon, "TOPLEFT", -6, -1)
        else
          icon.cdBarBG:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -1)
        end
        icon.cdBarBG:SetSize(barWidth, iconSize - 2)
        icon.cdBar:ClearAllPoints()
        icon.cdBar:SetPoint("TOPLEFT", icon.cdBarBG, "TOPLEFT", 1, -1)
        icon.cdBar:SetPoint("BOTTOMRIGHT", icon.cdBarBG, "BOTTOMRIGHT", -1, 1)
        icon.cooldown:Hide()
        icon.cdBar:Show()
        icon.cdBarBG:Show()
        icon.timer:ClearAllPoints()
        icon.timer:SetPoint("RIGHT", icon.cdBarBG, "RIGHT", -4, 0)
        icon.timer:SetJustifyH("RIGHT")
      else
        icon.cdBar:ClearAllPoints()
        icon.cdBarBG:ClearAllPoints()
        local barHeight = math.max(4, math.floor(iconSize * 0.16))
        -- Keep icon-mode anchors rooted on icon to prevent cdBar/cdBarBG circular dependency.
        icon.cdBarBG:SetPoint("BOTTOMLEFT", icon, "BOTTOMLEFT", 0, 0)
        icon.cdBarBG:SetPoint("BOTTOMRIGHT", icon, "BOTTOMRIGHT", 0, 0)
        icon.cdBarBG:SetHeight(barHeight + 2)
        icon.cdBar:SetPoint("TOPLEFT", icon.cdBarBG, "TOPLEFT", 1, -1)
        icon.cdBar:SetPoint("BOTTOMRIGHT", icon.cdBarBG, "BOTTOMRIGHT", -1, 1)
        icon.cooldown:Show()
        icon.cdBar:Hide()
        icon.cdBarBG:Hide()
        icon.timer:SetJustifyH("CENTER")
        applyTextPosition(icon.timer, icon, row.timerAnchor, row.timerOffsetX, row.timerOffsetY, "BOTTOM", 0, -1)
      end
      icon.timer:SetText("")
      icon.timer:Hide()
      applyTextPosition(icon.customText, icon, row.customTextAnchor, row.customTextOffsetX, row.customTextOffsetY, "TOP", 0, 2)
      updateCustomText(icon, row, nil)

      local previous = prevState[row.stateKey]
      nextState[row.stateKey] = {
        wasLow = previous and previous.wasLow or false,
        soundOnGain = row.soundOnGain or "default",
        soundOnLow = row.soundOnLow or "default",
        soundOnExpire = row.soundOnExpire or "default",
        isPlaceholder = row.isPlaceholder == true,
      }
      if allowTransitionSound and (not previous) and not row.isPlaceholder then
        ns.SoundManager:Play(row.soundOnGain or "default", "gain")
        ns.Debug:Verbosef("Sound trigger gain key=%s spellID=%s", tostring(row.stateKey), tostring(row.spellID))
      end

      local r, g, b = getColorForUnit(row.unit)
      setIconBorderColor(icon, r, g, b, 0.95)

      if row.canCompute and row.duration and row.duration > 0 then
        if hasSideBar then
          icon.cooldown:SetCooldown(0, 0)
        else
          icon.cooldown:SetCooldown(row.expirationTime - row.duration, row.duration)
        end
      else
        icon.cooldown:SetCooldown(0, 0)
      end

      icon.lowGlow:SetAlpha(0)
      icon:Show()
    end
    local contentCount = #entries
    frame.activeIconCount = contentCount

    if ns.state.editMode or (not ns.db.locked) or contentCount > 0 then
      frame:Show()
    else
      frame:Hide()
    end
  end

  if allowTransitionSound then
    for rowKey, prev in pairs(prevState) do
      if not nextState[rowKey] and not prev.isPlaceholder then
        ns.SoundManager:Play(prev.soundOnExpire or "default", "expire")
        ns.Debug:Verbosef("Sound trigger expire key=%s", tostring(rowKey))
      end
    end
  end

  self.stateByKey = nextState
  self.hasRendered = true
  self:RefreshDragState()
  self:UpdateVisuals()
end

function G:UpdateVisuals()
  local now = GetTime()
  local defaultThreshold = tonumber(ns.db.options.lowTimeThreshold) or 3

  for _, frame in pairs(self.frames) do
    local activeCount = tonumber(frame.activeIconCount) or #frame.icons
    for idx = 1, activeCount do
      local icon = frame.icons[idx]
      local row = icon and icon.row
      if row then
        local state = self.stateByKey[row.stateKey]
        local timerVisual = tostring(row.timerVisual or "icon"):lower()
        local hasSideBar = (timerVisual == "bar" or timerVisual == "iconbar")
        if row.canCompute and row.duration and row.duration > 0 then
          local remaining = math.max(0, row.expirationTime - now)
          if hasSideBar then
            icon.timer:SetText(formatRemaining(remaining))
            icon.timer:Show()
          else
            icon.timer:SetText("")
            icon.timer:Hide()
          end
          updateCustomText(icon, row, remaining)
          if hasSideBar then
            local ratio = remaining / row.duration
            if ratio < 0 then
              ratio = 0
            end
            if ratio > 1 then
              ratio = 1
            end
            icon.cdBar:SetValue(ratio)
            local r = 1 - ratio
            local g = ratio
            icon.cdBar:SetStatusBarColor(r, g, 0.15, 0.95)
            icon.cdBar:Show()
            icon.cdBarBG:Show()
          else
            icon.cdBar:Hide()
            icon.cdBarBG:Hide()
          end

          local threshold = tonumber(row.lowTimeThreshold) or 0
          if threshold <= 0 then
            threshold = defaultThreshold
          end
          local thresholdReached = row.alert and remaining <= threshold and remaining > 0
          local showGlow = thresholdReached and ns.db.options.lowTimeGlow
          if showGlow then
            icon._phase = (icon._phase or 0) + 0.16
            icon.lowGlow:SetAlpha(0.18 + (math.abs(math.sin(icon._phase)) * 0.35))
          else
            icon.lowGlow:SetAlpha(0)
          end

          if state then
            if thresholdReached and not state.wasLow and not row.isPlaceholder then
              ns.SoundManager:Play(row.soundOnLow or "default", "low")
              ns.Debug:Verbosef("Sound trigger low key=%s spellID=%s", tostring(row.stateKey), tostring(row.spellID))
            end
            state.wasLow = thresholdReached
          end
        elseif row.canCompute and (not row.duration or row.duration == 0) then
          icon.timer:SetText("")
          icon.timer:Hide()
          updateCustomText(icon, row, nil)
          icon.cdBar:SetValue(0)
          icon.cdBar:Hide()
          icon.cdBarBG:Hide()
          icon.lowGlow:SetAlpha(0)
          if state then
            state.wasLow = false
          end
        else
          icon.timer:SetText("")
          icon.timer:Hide()
          updateCustomText(icon, row, nil)
          icon.cdBar:SetValue(0)
          icon.cdBar:Hide()
          icon.cdBarBG:Hide()
          icon.lowGlow:SetAlpha(0)
          if state then
            state.wasLow = false
          end
        end
      end
    end
  end
end

function G:EnsureTicker()
  if self.ticker then
    return
  end
  self.ticker = C_Timer.NewTicker(0.12, function()
    self:UpdateVisuals()
  end)
end

G.UpdateTimers = G.UpdateVisuals








