local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local E = UI.Events
local Skin = ns.UISkin

local Preview = {}
Preview.__index = Preview

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.01, 0.04, 0.1, 0.72)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.9)
end

local function getSpellTexture(spellID)
  local sid = tonumber(spellID)
  if sid and ns.AuraAPI and ns.AuraAPI.GetSpellTexture then
    local tex = ns.AuraAPI:GetSpellTexture(sid)
    if tex then
      return tex
    end
  end
  return 134400
end

local function parseColorCSV(text)
  text = tostring(text or "")
  local out = {}
  for token in text:gmatch("[^,%s;]+") do
    local n = tonumber(token)
    if not n then
      return nil
    end
    if n < 0 then
      n = 0
    elseif n > 1 then
      n = 1
    end
    out[#out + 1] = n
    if #out == 3 then
      break
    end
  end
  if #out ~= 3 then
    return nil
  end
  return out[1], out[2], out[3]
end

function Preview:SetDraft(draft)
  self.draft = draft or {}
  local displayName = tostring(self.draft.name or self.draft.displayName or "Aura Preview")
  self.name:SetText(displayName)
  local resolvedIcon = (ns.AuraAPI and ns.AuraAPI.GetDisplayTextureForItem and ns.AuraAPI:GetDisplayTextureForItem(self.draft, nil)) or getSpellTexture(self.draft.spellID)
  self.icon:SetTexture(resolvedIcon)
  if not self.icon:GetTexture() then
    self.icon:SetTexture(getSpellTexture(self.draft.spellID))
  end
  local trackingLabel = "Confirmed"
  if tostring(self.draft.trackingMode or "") == "estimated" and tostring(self.draft.unit or "") == "target" then
    trackingLabel = "Estimated"
  end
  local mode = tostring(self.draft.displayMode or self.draft.timerVisual or "icon")
  self.mode:SetText(string.format("Mode: %s | Tracking: %s", mode, trackingLabel))
  if self.status then
    local dirty = UI and UI.State and UI.State.Get and UI.State:Get().dirty == true
    self.status:SetText(dirty and "Live draft preview | Unsaved changes" or "Live draft preview | Saved")
  end

  local iconWidth = tonumber(self.draft.iconWidth) or 36
  local iconHeight = tonumber(self.draft.iconHeight) or 36
  local barWidth = tonumber(self.draft.barWidth) or 94
  local barHeight = tonumber(self.draft.barHeight) or 16
  local barSide = tostring(self.draft.barSide or "right"):lower()
  local timerAnchor = tostring(self.draft.timerAnchor or "BOTTOM"):upper()
  local customAnchor = tostring(self.draft.customTextAnchor or "TOP"):upper()
  local customText = tostring(self.draft.customText or "")
  local showTimerText = self.draft.showTimerText ~= false
  local panelWidth = math.max(140, (self.frame and self.frame:GetWidth()) or 240)
  local contentTopY = -74
  local contentLeft = 10
  local contentRight = -12
  local contentCenterX = math.floor((panelWidth - 22) / 2)

  self.iconFrame:ClearAllPoints()
  self.bar:ClearAllPoints()
  self.name:ClearAllPoints()
  self.timer:ClearAllPoints()
  self.customText:ClearAllPoints()

  self.iconFrame:SetSize(iconWidth, iconHeight)
  self.bar:SetSize(barWidth, barHeight)
  if ns.AuraAPI and ns.AuraAPI.ResolveBarTexturePath then
    self.bar:SetStatusBarTexture(ns.AuraAPI:ResolveBarTexturePath(self.draft.barTexture))
  else
    self.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  end

  local r, g, b = parseColorCSV(self.draft.barColor or "")
  if r and g and b then
    self.bar:SetStatusBarColor(r, g, b, 0.95)
  else
    self.bar:SetStatusBarColor(0.16, 0.64, 1.0, 0.95)
  end

  if mode == "bar" then
    self.iconFrame:Show()
    self.bar:Show()
    local totalWidth = iconWidth + 8 + barWidth
    local startX = math.max(contentLeft, contentCenterX - math.floor(totalWidth / 2))
    self.iconFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", startX, contentTopY + 2)
    self.bar:SetPoint("LEFT", self.iconFrame, "RIGHT", 8, 0)
    self.name:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", 0, 2)
  elseif mode == "iconbar" then
    self.iconFrame:Show()
    self.bar:Show()
    local totalWidth = iconWidth + 8 + barWidth
    local startX = math.max(contentLeft, contentCenterX - math.floor(totalWidth / 2))
    if barSide == "left" then
      self.bar:SetPoint("TOPLEFT", self.frame, "TOPLEFT", startX, contentTopY)
      self.iconFrame:SetPoint("LEFT", self.bar, "RIGHT", 8, 0)
    else
      self.iconFrame:SetPoint("TOPLEFT", self.frame, "TOPLEFT", startX, contentTopY + 2)
      self.bar:SetPoint("LEFT", self.iconFrame, "RIGHT", 8, 0)
    end
    self.name:SetPoint("BOTTOMLEFT", self.bar, "TOPLEFT", 0, 2)
  else
    self.iconFrame:Show()
    self.bar:Hide()
    self.iconFrame:SetPoint("TOP", self.frame, "TOP", 0, contentTopY + 2)
    self.name:SetPoint("TOP", self.iconFrame, "BOTTOM", 0, -2)
  end

  if showTimerText then
    self.timer:Show()
    if mode == "bar" or mode == "iconbar" then
      self.timer:SetPoint("RIGHT", self.bar, "RIGHT", -4, 0)
    elseif timerAnchor == "TOP" then
      self.timer:SetPoint("BOTTOM", self.iconFrame, "TOP", 0, 2)
    else
      self.timer:SetPoint("TOP", self.iconFrame, "BOTTOM", 0, -16)
    end
  else
    self.timer:Hide()
  end

  if customText ~= "" then
    self.customText:SetText(customText)
    self.customText:Show()
    if customAnchor == "BOTTOM" then
      self.customText:SetPoint("TOPLEFT", self.frame, "TOPLEFT", contentLeft, -146)
    else
      self.customText:SetPoint("TOPLEFT", self.frame, "TOPLEFT", contentLeft, -146)
    end
  else
    self.customText:SetText("")
    self.customText:Hide()
  end
end

function Preview:Play(duration)
  self.active = true
  self.duration = math.max(0.1, tonumber(duration) or tonumber(self.draft and self.draft.duration) or 8)
  self.endsAt = (GetTime() or 0) + self.duration
  self.timer:SetText(string.format("%.1f", self.duration))
  self.bar:SetMinMaxValues(0, self.duration)
  self.bar:SetValue(self.duration)
  self.frame:Show()
end

function Preview:Stop()
  self.active = false
  self.timer:SetText("0.0")
  self.bar:SetValue(0)
end

function Preview:Create(parent)
  local o = setmetatable({}, self)
  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetAllPoints()
  createBackdrop(o.frame)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(o.frame)
  end

  o.mode = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.mode:SetPoint("TOPLEFT", 10, -12)
  o.mode:SetText("Mode: iconbar")

  o.status = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.status:SetPoint("TOPLEFT", 10, -28)
  o.status:SetPoint("RIGHT", -10, 0)
  o.status:SetJustifyH("LEFT")
  o.status:SetText("Selected aura live draft preview")

  o.divider = o.frame:CreateTexture(nil, "ARTWORK")
  o.divider:SetPoint("TOPLEFT", 10, -54)
  o.divider:SetPoint("TOPRIGHT", -10, -54)
  o.divider:SetHeight(1)
  o.divider:SetColorTexture(0.34, 0.56, 0.74, 0.55)

  o.iconFrame = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  createBackdrop(o.iconFrame)
  o.iconFrame:SetSize(44, 44)
  if Skin and Skin.ApplySection then
    Skin:ApplySection(o.iconFrame)
  end
  o.iconFrame:SetPoint("TOPLEFT", 10, -70)

  o.icon = o.iconFrame:CreateTexture(nil, "ARTWORK")
  o.icon:SetAllPoints()
  o.icon:SetTexture(134400)

  o.name = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  o.name:SetPoint("TOPLEFT", o.iconFrame, "TOPRIGHT", 8, -2)
  o.name:SetText("Aura Preview")

  o.bar = CreateFrame("StatusBar", nil, o.frame)
  o.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  o.bar:SetStatusBarColor(0.16, 0.64, 1.0, 0.95)
  o.bar:SetMinMaxValues(0, 1)
  o.bar:SetValue(1)
  o.bar:SetPoint("TOPLEFT", o.iconFrame, "TOPRIGHT", 8, -22)
  o.bar:SetPoint("RIGHT", -12, 0)
  o.bar:SetHeight(16)

  o.barBg = o.bar:CreateTexture(nil, "BACKGROUND")
  o.barBg:SetAllPoints()
  o.barBg:SetColorTexture(0, 0, 0, 0.5)

  o.timer = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.timer:SetPoint("RIGHT", o.bar, "RIGHT", -4, 0)
  o.timer:SetText("0.0")

  o.customText = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.customText:SetPoint("TOPLEFT", 10, -132)
  o.customText:SetPoint("RIGHT", -10, 0)
  o.customText:SetJustifyH("LEFT")
  o.customText:SetText("")
  o.customText:Hide()

  o.hint = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.hint:SetPoint("TOPLEFT", 10, -162)
  o.hint:SetPoint("RIGHT", -10, 0)
  o.hint:SetJustifyH("LEFT")
  o.hint:SetText("You are looking at a live draft preview of the selected aura. Appearance changes update here before you save. If Tracking is Estimated, the preview represents a local timer started from your cast, not a confirmed target aura.")

  o.frame:SetScript("OnUpdate", function()
    if not o.active then
      return
    end
    local now = GetTime() or 0
    local remaining = o.endsAt - now
    if remaining <= 0 then
      o:Stop()
      return
    end
    o.timer:SetText(string.format("%.1f", remaining))
    o.bar:SetValue(remaining)
  end)

  if E then
    E:On(E.Names.SIMULATE_TRIGGER, function(payload)
      payload = payload or {}
      if payload.draft then
        o:SetDraft(payload.draft)
      end
      if payload.kind == "consume" then
        o:Stop()
      else
        o:Play(payload.duration)
      end
    end)

    E:On(E.Names.AURA_SELECTED, function(payload)
      local auraId = payload and payload.auraId
      if not auraId or not UI.AuraRepository or not UI.AuraRepository.GetAuraDraft then
        return
      end
      local draft = UI.AuraRepository:GetAuraDraft(auraId)
      if draft then
        o:SetDraft(draft)
      end
    end)

    E:On(E.Names.STATE_CHANGED, function()
      if o.draft then
        o:SetDraft(o.draft)
      end
    end)
  end

  return o
end

W.PreviewPanelWidget = Preview
