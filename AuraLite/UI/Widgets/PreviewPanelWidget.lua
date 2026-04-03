local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Widgets = ns.UIV2.Widgets or {}

local UI = ns.UIV2
local W = UI.Widgets
local E = UI.Events
local Skin = ns.UISkin
local AceGUI = LibStub and LibStub("AceGUI-3.0", true)

local WIDGET_TYPE = "AuraLitePreviewCard"
local WIDGET_VERSION = 1

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

local function resolveCustomFontPath(token)
  token = tostring(token or "friz")
  local lowered = token:lower()
  if lowered:match("^lsm:") and ns.Media and ns.Media.Fetch then
    local resolved = ns.Media:Fetch("font", token:sub(5))
    if type(resolved) == "string" and resolved ~= "" then
      return resolved
    end
  end
  token = lowered
  if token == "arial" then
    return "Fonts\\ARIALN.TTF"
  elseif token == "blei" then
    return "Fonts\\BLEI00D.TTF"
  elseif token == "font2002" then
    return "Fonts\\2002.TTF"
  elseif token == "arhei" then
    return "Fonts\\ARHei.ttf"
  elseif token == "morpheus" then
    return "Fonts\\MORPHEUS.TTF"
  elseif token == "skurri" then
    return "Fonts\\skurri.ttf"
  end
  return "Fonts\\FRIZQT__.TTF"
end

local function applyStatusBarGradient(bar, draft, r1, g1, b1)
  if not bar then
    return
  end
  local texture = bar.GetStatusBarTexture and bar:GetStatusBarTexture() or nil
  local r2, g2, b2 = parseColorCSV(draft and draft.barColor2 or "")
  local orientation = "HORIZONTAL"
  if texture and draft and draft.barGradientEnabled == true and r2 and g2 and b2 then
    texture:SetVertexColor(1, 1, 1, 1)
    if bar.SetStatusBarColor then
      bar:SetStatusBarColor(1, 1, 1, 0.95)
    end
    if texture.SetGradientAlpha then
      texture:SetGradientAlpha(orientation, r1, g1, b1, 0.95, r2, g2, b2, 0.95)
      return
    end
  end
  if texture and texture.SetGradientAlpha then
    texture:SetGradientAlpha(orientation, r1, g1, b1, 0.95, r1, g1, b1, 0.95)
  elseif texture then
    texture:SetVertexColor(r1, g1, b1, 0.95)
  end
  if bar.SetStatusBarColor then
    bar:SetStatusBarColor(r1, g1, b1, 0.95)
  end
end

local function applyTextAnchor(region, relativeTo, anchor, offsetX, offsetY, defaultAnchor, defaultX, defaultY)
  if not region or not relativeTo then
    return
  end
  local resolvedAnchor = tostring(anchor or defaultAnchor or "TOP")
  local x = tonumber(offsetX)
  if x == nil then
    x = tonumber(defaultX) or 0
  end
  local y = tonumber(offsetY)
  if y == nil then
    y = tonumber(defaultY) or 0
  end
  region:ClearAllPoints()
  region:SetPoint(resolvedAnchor, relativeTo, resolvedAnchor, x, y)
end

local function getPreviewDuration(draft)
  local value = tonumber(draft and draft.duration)
  if not value or value <= 0 then
    value = tonumber(draft and draft.estimatedDuration)
  end
  if not value or value <= 0 then
    value = 8
  end
  return math.max(0.1, value)
end

local function getPreviewDraftFromState()
  local state = ns and ns.state
  if state and type(state.selectedAuraPreviewItem) == "table" then
    return state.selectedAuraPreviewItem
  end
  local selectedAura = state and state.selectedAura
  local auraKey = selectedAura and tostring(selectedAura.key or "")
  if auraKey ~= "" and UI and UI.AuraRepository and UI.AuraRepository.GetAuraDraft then
    return UI.AuraRepository:GetAuraDraft(auraKey)
  end
  return nil
end

local function ensurePreviewChrome(widget)
  local frame = widget.frame

  if not widget.mode then
    widget.mode = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    widget.mode:SetPoint("TOPLEFT", 0, -20)
    widget.mode:SetPoint("RIGHT", 0, 0)
    widget.mode:SetJustifyH("LEFT")
    widget.mode:SetTextColor(1.0, 0.86, 0.18)
  end

  if not widget.status then
    widget.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.status:SetPoint("TOPLEFT", 0, -2)
    widget.status:SetPoint("RIGHT", 0, 0)
    widget.status:SetJustifyH("LEFT")
    widget.status:SetWordWrap(false)
  end

  if not widget.divider then
    widget.divider = frame:CreateTexture(nil, "ARTWORK")
    widget.divider:SetPoint("TOPLEFT", 0, -40)
    widget.divider:SetPoint("TOPRIGHT", 0, -40)
    widget.divider:SetHeight(1)
    widget.divider:SetColorTexture(1.0, 0.82, 0.18, 0.28)
  end

  if not widget.previewCard then
    widget.previewCard = CreateFrame("Frame", nil, frame, "BackdropTemplate")
    widget.previewCard:SetPoint("TOPLEFT", 0, -50)
    widget.previewCard:SetPoint("TOPRIGHT", 0, -50)
    widget.previewCard:SetHeight(96)
    if Skin and Skin.ApplySection then
      Skin:ApplySection(widget.previewCard)
    end
  end

  if not widget.iconFrame then
    widget.iconFrame = CreateFrame("Frame", nil, widget.previewCard, "BackdropTemplate")
    widget.iconFrame:SetSize(46, 46)
    widget.iconFrame:SetPoint("LEFT", 8, 0)
    if Skin and Skin.ApplySection then
      Skin:ApplySection(widget.iconFrame)
    end
  end

  if not widget.icon then
    widget.icon = widget.iconFrame:CreateTexture(nil, "ARTWORK")
    widget.icon:SetAllPoints()
  end

  if not widget.cooldown then
    widget.cooldown = CreateFrame("Cooldown", nil, widget.iconFrame, "CooldownFrameTemplate")
    widget.cooldown:SetAllPoints()
    widget.cooldown:SetDrawEdge(false)
    widget.cooldown:SetSwipeColor(0, 0, 0, 0.72)
    widget.cooldown:SetHideCountdownNumbers(true)
  end

  if not widget.iconGlow then
    widget.iconGlow = widget.iconFrame:CreateTexture(nil, "OVERLAY")
    widget.iconGlow:SetPoint("TOPLEFT", -5, 5)
    widget.iconGlow:SetPoint("BOTTOMRIGHT", 5, -5)
    widget.iconGlow:SetTexture("Interface\\Cooldown\\star4")
    widget.iconGlow:SetBlendMode("ADD")
    widget.iconGlow:SetAlpha(0)
  end

  if not widget.procGlow then
    widget.procGlow = widget.iconFrame:CreateTexture(nil, "OVERLAY")
    widget.procGlow:SetPoint("TOPLEFT", -18, 18)
    widget.procGlow:SetPoint("BOTTOMRIGHT", 18, -18)
    widget.procGlow:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    widget.procGlow:SetBlendMode("ADD")
    widget.procGlow:SetAlpha(0)
  end

  if not widget.name then
    widget.name = widget.previewCard:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  end

  if not widget.bar then
    widget.bar = CreateFrame("StatusBar", nil, widget.previewCard)
    widget.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
    widget.bar:SetStatusBarColor(0.16, 0.64, 1.0, 0.95)
    widget.bar:SetMinMaxValues(0, 1)
    widget.bar:SetValue(1)
    widget.bar:SetHeight(16)

    widget.barBg = widget.bar:CreateTexture(nil, "BACKGROUND")
    widget.barBg:SetAllPoints()
    widget.barBg:SetColorTexture(0, 0, 0, 0.5)
  end

  if not widget.timer then
    widget.timer = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    widget.timer:SetJustifyH("RIGHT")
  end

  if not widget.customText then
    widget.customText = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.customText:SetPoint("TOPLEFT", 0, -134)
    widget.customText:SetPoint("RIGHT", 0, 0)
    widget.customText:SetJustifyH("LEFT")
  end

  if not widget.hint then
    widget.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    widget.hint:SetPoint("TOPLEFT", 0, -134)
    widget.hint:SetPoint("RIGHT", 0, 0)
    widget.hint:SetJustifyH("LEFT")
    widget.hint:SetText("Live preview updates before save.")
  end
end

local function applyDraftToWidget(widget, draft)
  widget.draft = draft or {}
  ensurePreviewChrome(widget)

  local displayName = tostring(widget.draft.name or widget.draft.displayName or "Aura Preview")
  widget.name:SetText(displayName)
  local resolvedIcon = (ns.AuraAPI and ns.AuraAPI.GetDisplayTextureForItem and ns.AuraAPI:GetDisplayTextureForItem(widget.draft, nil)) or getSpellTexture(widget.draft.spellID)
  widget.icon:SetTexture(resolvedIcon or getSpellTexture(widget.draft.spellID))

  local trackingLabel = "Confirmed"
  if tostring(widget.draft.trackingMode or "") == "estimated" and tostring(widget.draft.unit or "") == "target" then
    trackingLabel = "Estimated"
  end
  local mode = tostring(widget.draft.displayMode or widget.draft.timerVisual or "icon")
  widget.mode:SetText(string.format("Mode: %s | Tracking: %s", mode, trackingLabel))

  local dirty = UI and UI.State and UI.State.Get and UI.State:Get().dirty == true
  widget.status:SetText(dirty and "Live draft preview | Unsaved changes" or "Live draft preview | Saved")

  local iconWidth = tonumber(widget.draft.iconWidth) or 36
  local iconHeight = tonumber(widget.draft.iconHeight) or 36
  local barWidth = tonumber(widget.draft.barWidth) or 94
  local barHeight = tonumber(widget.draft.barHeight) or 16
  local customText = tostring(widget.draft.customText or "")
  local showCustomText = widget.draft.showCustomText ~= false
  local customTextSize = math.max(8, tonumber(widget.draft.customTextSize) or 12)
  local showNameText = widget.draft.showNameText ~= false
  local nameTextSize = math.max(8, tonumber(widget.draft.nameTextSize) or 12)
  local showTimerText = widget.draft.showTimerText ~= false
  local timerTextSize = math.max(8, tonumber(widget.draft.timerTextSize) or 12)
  local panelWidth = math.max(180, (widget.previewCard and widget.previewCard:GetWidth()) or (widget.frame and widget.frame:GetWidth()) or 240)
  local contentLeft = 14
  local iconTop = -18
  local textLeft = contentLeft + math.max(32, iconWidth) + 12
  local timerWidth = showTimerText and 38 or 0
  local barRightInset = 18 + timerWidth + ((showTimerText and 12) or 0)
  local barAvailable = math.max(72, panelWidth - textLeft - barRightInset)
  local timerVisual = tostring(widget.draft.timerVisual or widget.draft.displayMode or "icon"):lower()
  local hasSideBar = (timerVisual == "bar" or timerVisual == "iconbar")
  local customTextAnchor = tostring(widget.draft.customTextAnchor or "TOP")
  local timerAnchor = tostring(widget.draft.timerAnchor or "BOTTOM")

  widget.iconFrame:ClearAllPoints()
  widget.bar:ClearAllPoints()
  widget.name:ClearAllPoints()
  widget.timer:ClearAllPoints()
  widget.customText:ClearAllPoints()
  widget.customText:SetFont(resolveCustomFontPath(widget.draft.customTextFont), customTextSize, "OUTLINE")
  widget.timer:SetFont(resolveCustomFontPath(widget.draft.timerTextFont), timerTextSize, "OUTLINE")

  widget.iconFrame:SetSize(iconWidth, iconHeight)
  widget.bar:SetSize(math.min(barWidth, barAvailable), barHeight)
  if ns.AuraAPI and ns.AuraAPI.ResolveBarTexturePath then
    widget.bar:SetStatusBarTexture(ns.AuraAPI:ResolveBarTexturePath(widget.draft.barTexture))
  else
    widget.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
  end

  local r, g, b = parseColorCSV(widget.draft.barColor or "")
  if r and g and b then
    applyStatusBarGradient(widget.bar, widget.draft, r, g, b)
  else
    applyStatusBarGradient(widget.bar, widget.draft, 0.22, 0.58, 0.94)
  end

  widget.iconFrame:Show()
  widget.iconFrame:SetPoint("TOPLEFT", widget.previewCard, "TOPLEFT", contentLeft, iconTop)

  widget.name:SetPoint("TOPLEFT", widget.previewCard, "TOPLEFT", textLeft, iconTop + 2)
  widget.name:SetPoint("RIGHT", widget.previewCard, "RIGHT", -(barRightInset + 6), 0)
  widget.name:SetJustifyH("LEFT")
  widget.name:SetFont(resolveCustomFontPath(widget.draft.nameTextFont), nameTextSize, "OUTLINE")
  widget.name:SetShown(showNameText)

  if hasSideBar then
    widget.bar:Show()
    widget.bar:SetHeight(barHeight)
    widget.bar:SetPoint("TOPLEFT", widget.name, "BOTTOMLEFT", 0, -8)
    widget.bar:SetPoint("RIGHT", widget.previewCard, "RIGHT", -barRightInset, 0)
    widget.cooldown:Hide()
  else
    widget.bar:Hide()
    widget.cooldown:Show()
  end

  if showTimerText then
    widget.timer:Show()
    widget.timer:SetWidth(timerWidth)
    if hasSideBar then
      widget.timer:SetPoint("LEFT", widget.bar, "RIGHT", 10, 0)
      widget.timer:SetPoint("RIGHT", widget.previewCard, "RIGHT", -12, 0)
    else
      applyTextAnchor(widget.timer, widget.iconFrame, timerAnchor, tonumber(widget.draft.timerOffsetX) or 0, tonumber(widget.draft.timerOffsetY) or -1, "BOTTOM", 0, -1)
      widget.timer:SetJustifyH("CENTER")
    end
  else
    widget.timer:Hide()
  end

  if showCustomText and customText ~= "" then
    widget.customText:SetText(customText)
    widget.customText:Show()
    if hasSideBar then
      widget.customText:SetPoint("TOPLEFT", widget.bar, "BOTTOMLEFT", 0, -8)
      widget.customText:SetPoint("RIGHT", widget.previewCard, "RIGHT", -14, 0)
      widget.customText:SetJustifyH("LEFT")
    else
      applyTextAnchor(widget.customText, widget.iconFrame, customTextAnchor, tonumber(widget.draft.customTextOffsetX) or 0, tonumber(widget.draft.customTextOffsetY) or 2, "TOP", 0, 2)
      widget.customText:SetJustifyH("CENTER")
    end
  else
    widget.customText:SetText("")
    widget.customText:Hide()
  end

  widget.hint:ClearAllPoints()
  widget.hint:SetPoint("TOPLEFT", widget.previewCard, "BOTTOMLEFT", 0, -10)
  widget.hint:SetPoint("RIGHT", 0, 0)

  widget.previewCard:SetHeight((showCustomText and customText ~= "" and hasSideBar) and 116 or ((showCustomText and customText ~= "") and 104 or 86))
end

local function playWidget(widget, duration)
  widget.active = true
  widget.duration = math.max(0.1, tonumber(duration) or getPreviewDuration(widget.draft))
  widget.endsAt = (GetTime() or 0) + widget.duration
  widget.timer:SetText(string.format("%.1f", widget.duration))
  widget.bar:SetMinMaxValues(0, widget.duration)
  widget.bar:SetValue(widget.duration)
  widget.frame:Show()
  if widget.cooldown and widget.cooldown:IsShown() then
    if ns.AuraAPI and ns.AuraAPI.ApplyCooldownToFrame then
      ns.AuraAPI:ApplyCooldownToFrame(widget.cooldown, {
        startTime = (GetTime() or 0),
        duration = widget.duration,
        expirationTime = (GetTime() or 0) + widget.duration,
        isActive = true,
      })
    else
      widget.cooldown:SetCooldown((GetTime() or 0), widget.duration)
    end
  end
end

local function stopWidget(widget)
  widget.active = false
  if widget.timer then
    widget.timer:SetText("0.0")
  end
  if widget.bar then
    widget.bar:SetValue(0)
  end
  if widget.cooldown then
    if ns.AuraAPI and ns.AuraAPI.ClearCooldownFrame then
      ns.AuraAPI:ClearCooldownFrame(widget.cooldown)
    else
      widget.cooldown:SetCooldown(0, 0)
    end
  end
end

if AceGUI and (AceGUI:GetWidgetVersion(WIDGET_TYPE) or 0) < WIDGET_VERSION then
  local methods = {
    OnAcquire = function(self)
      self:SetFullWidth(true)
      self:SetHeight(190)
      self.active = false
      self.draft = {}
      ensurePreviewChrome(self)
      applyDraftToWidget(self, {})
      stopWidget(self)
    end,

    OnRelease = function(self)
      self.active = false
      self.draft = nil
      self.frame:ClearAllPoints()
      self.frame:SetParent(UIParent)
    end,

    SetDraft = function(self, draft)
      applyDraftToWidget(self, draft)
      if draft then
        playWidget(self, getPreviewDuration(draft))
      else
        stopWidget(self)
      end
    end,

    Play = function(self, duration)
      playWidget(self, duration)
    end,

    Stop = function(self)
      stopWidget(self)
    end,
  }

  local function Constructor()
    local frame = CreateFrame("Frame", nil, UIParent)
    frame:SetHeight(190)

    local widget = {
      type = WIDGET_TYPE,
      frame = frame,
      active = false,
      draft = {},
    }

    for method, func in pairs(methods) do
      widget[method] = func
    end

    frame.obj = widget
    frame:SetScript("OnSizeChanged", function(selfFrame)
      local selfWidget = selfFrame.obj
      if selfWidget and selfWidget.draft then
        applyDraftToWidget(selfWidget, selfWidget.draft)
      end
    end)
    frame:SetScript("OnUpdate", function(selfFrame)
      local selfWidget = selfFrame.obj
      if not selfWidget or not selfWidget.active then
        return
      end
      local now = GetTime() or 0
      local remaining = (selfWidget.endsAt or 0) - now
      if remaining <= 0 then
        selfWidget:Play(selfWidget.duration or getPreviewDuration(selfWidget.draft))
        return
      end
      if selfWidget.timer and selfWidget.timer:IsShown() then
        selfWidget.timer:SetText(string.format("%.1f", remaining))
      end
      if selfWidget.bar and selfWidget.bar:IsShown() then
        selfWidget.bar:SetValue(remaining)
      end
      if selfWidget.iconGlow then
        local glowMode = tostring((((selfWidget.draft or {}).visualStates or {}).onGain) or "off")
        local glowSpeed = math.max(0.25, math.min(3.0, tonumber((((selfWidget.draft or {}).visualStates or {}).glowSpeed)) or 1.0))
        if glowMode == "burst" or glowMode == "shine" then
          selfWidget.iconGlow:SetAlpha(0.28 + (math.sin(now * 7.2 * glowSpeed) * 0.18))
        elseif glowMode == "soft" then
          selfWidget.iconGlow:SetAlpha(0.10 + (math.sin(now * 4.8 * glowSpeed) * 0.06))
        elseif glowMode == "button" then
          selfWidget.iconGlow:SetAlpha(0)
        else
          selfWidget.iconGlow:SetAlpha(0)
        end
      end
      if selfWidget.procGlow then
        local glowMode = tostring((((selfWidget.draft or {}).visualStates or {}).onGain) or "off")
        local glowSpeed = math.max(0.25, math.min(3.0, tonumber((((selfWidget.draft or {}).visualStates or {}).glowSpeed)) or 1.0))
        if glowMode == "burst" or glowMode == "button" then
          selfWidget.procGlow:SetAlpha(0.20 + (math.sin(now * 6.0 * glowSpeed) * 0.10))
        else
          selfWidget.procGlow:SetAlpha(0)
        end
      end
    end)

    return AceGUI:RegisterAsWidget(widget)
  end

  AceGUI:RegisterWidgetType(WIDGET_TYPE, Constructor, WIDGET_VERSION)
end

local Preview = {}
Preview.__index = Preview

function Preview:SetDraft(draft)
  applyDraftToWidget(self, draft)
  if draft then
    playWidget(self, getPreviewDuration(draft))
  else
    stopWidget(self)
  end
end

function Preview:Play(duration)
  playWidget(self, duration)
end

function Preview:Stop()
  stopWidget(self)
end

function Preview:Create(parent)
  local o
  if AceGUI then
    o = AceGUI:Create(WIDGET_TYPE)
    o.frame:SetParent(parent)
  else
    o = setmetatable({}, self)
    o.frame = CreateFrame("Frame", nil, parent)
    o.frame:SetAllPoints()
    ensurePreviewChrome(o)
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
      if o.procGlow then
        local glowMode = tostring((((o.draft or {}).visualStates or {}).onGain) or "off")
        local glowSpeed = math.max(0.25, math.min(3.0, tonumber((((o.draft or {}).visualStates or {}).glowSpeed)) or 1.0))
        if glowMode == "burst" or glowMode == "button" then
          o.procGlow:SetAlpha(0.20 + (math.sin(now * 6.0 * glowSpeed) * 0.10))
        else
          o.procGlow:SetAlpha(0)
        end
      end
    end)
  end

  if E and not o._alEventBound then
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
      local previewDraft = getPreviewDraftFromState()
      if previewDraft then
        o:SetDraft(previewDraft)
        return
      end
      if not auraId or not UI.AuraRepository or not UI.AuraRepository.GetAuraDraft then
        return
      end
      local draft = UI.AuraRepository:GetAuraDraft(auraId)
      if draft then
        o:SetDraft(draft)
      end
    end)

    E:On(E.Names.STATE_CHANGED, function()
      local previewDraft = getPreviewDraftFromState()
      if previewDraft then
        o:SetDraft(previewDraft)
      elseif o.draft then
        o:SetDraft(o.draft)
      end
    end)
    o._alEventBound = true
  end

  return o
end

W.PreviewPanelWidget = Preview
