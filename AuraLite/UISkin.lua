local _, ns = ...
local U = ns.Utils

ns.UISkin = ns.UISkin or {}
local S = ns.UISkin

local validThemes = {
  modern = true,
  sky = true,
  classic = true,
}

local palettes = {
  modern = {
    windowBG = { 0.09, 0.12, 0.18, 0.90 },
    windowBorder = { 0.28, 0.48, 0.68, 0.90 },
    sectionBG = { 0.12, 0.16, 0.23, 0.84 },
    sectionBorder = { 0.24, 0.36, 0.50, 0.82 },
    sectionAccent = { 0.42, 0.72, 0.88, 0.84 },
    textureAlpha = 0.10,
    buttonBG = { 0.15, 0.20, 0.28, 0.92 },
    buttonHover = { 0.20, 0.28, 0.38, 0.96 },
    buttonBorder = { 0.36, 0.56, 0.74, 0.82 },
    rowNormal = { 0.10, 0.14, 0.21, 0.72 },
    rowHover = { 0.16, 0.22, 0.31, 0.90 },
    rowSelected = { 0.20, 0.30, 0.42, 0.94 },
  },
  sky = {
    windowBG = { 0.17, 0.26, 0.38, 0.86 },
    windowBorder = { 0.45, 0.78, 0.98, 0.96 },
    sectionBG = { 0.22, 0.34, 0.49, 0.80 },
    sectionBorder = { 0.30, 0.60, 0.84, 0.92 },
    sectionAccent = { 0.56, 0.87, 1.00, 0.92 },
    textureAlpha = 0.11,
    buttonBG = { 0.16, 0.28, 0.42, 0.88 },
    buttonHover = { 0.24, 0.40, 0.58, 0.94 },
    buttonBorder = { 0.53, 0.86, 1.00, 0.94 },
    rowNormal = { 0.14, 0.25, 0.38, 0.62 },
    rowHover = { 0.24, 0.39, 0.56, 0.86 },
    rowSelected = { 0.31, 0.54, 0.78, 0.92 },
  },
  classic = {
    windowBG = { 0.00, 0.00, 0.00, 0.78 },
    windowBorder = { 0.30, 0.30, 0.30, 0.90 },
    sectionBG = { 0.00, 0.00, 0.00, 0.58 },
    sectionBorder = { 0.30, 0.30, 0.30, 0.85 },
    sectionAccent = { 0.72, 0.62, 0.20, 0.75 },
    textureAlpha = 0.10,
    buttonBG = { 0.10, 0.06, 0.02, 0.76 },
    buttonHover = { 0.20, 0.12, 0.04, 0.84 },
    buttonBorder = { 0.55, 0.40, 0.10, 0.88 },
    rowNormal = { 0.00, 0.00, 0.00, 0.35 },
    rowHover = { 0.15, 0.15, 0.15, 0.50 },
    rowSelected = { 0.20, 0.35, 0.65, 0.65 },
  },
}

local function trim(text)
  return U and U.Trim and U.Trim(text or "") or tostring(text or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function normalizePath(path)
  path = trim(path)
  if path == "" then
    return ""
  end
  path = path:gsub("/", "\\")
  path = path:gsub("%.tga$", ""):gsub("%.TGA$", "")
  path = path:gsub("%.blp$", ""):gsub("%.BLP$", "")
  return path
end

local function resolveCustomPath(path)
  local normalized = normalizePath(path)
  if normalized == "" then
    return ""
  end
  if ns.AuraAPI and ns.AuraAPI.ResolveCustomTexturePath then
    return ns.AuraAPI:ResolveCustomTexturePath(normalized)
  end
  if normalized:lower():find("^interface\\", 1, true) then
    return normalized
  end
  if normalized:find("\\", 1, true) then
    return normalized
  end
  return "Interface\\AddOns\\AuraLite\\Media\\Custom\\" .. normalized
end

function S:EnsureOptionsDefaults(options)
  options = options or {}
  if type(options.uiTheme) ~= "string" or not validThemes[options.uiTheme] then
    options.uiTheme = "modern"
  end
  if type(options.uiTexturePath) ~= "string" then
    options.uiTexturePath = ""
  end
  options.uiTexturePath = trim(options.uiTexturePath)
end

function S:GetTheme()
  local options = ns.db and ns.db.options or nil
  local chosen = options and tostring(options.uiTheme or "modern") or "modern"
  if validThemes[chosen] then
    return chosen
  end
  return "modern"
end

function S:GetPalette()
  return palettes[self:GetTheme()] or palettes.modern
end

function S:GetThemeOptions()
  return {
    { value = "modern", label = (ns.Localization and ns.Localization:T("loc_theme_modern")) or "Modern" },
    { value = "sky", label = (ns.Localization and ns.Localization:T("loc_theme_sky")) or "Sky" },
    { value = "classic", label = (ns.Localization and ns.Localization:T("loc_theme_classic")) or "Classic" },
  }
end

function S:GetResolvedTexturePath()
  local options = ns.db and ns.db.options or nil
  local customPath = resolveCustomPath(options and options.uiTexturePath or "")
  if customPath ~= "" then
    return customPath
  end
  return "Interface\\Buttons\\WHITE8x8"
end

local function applyBackdrop(frame, color, border)
  if not frame or not frame.SetBackdrop then
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 1, right = 1, top = 1, bottom = 1 },
  })
  frame:SetBackdropColor(color[1], color[2], color[3], color[4])
  frame:SetBackdropBorderColor(border[1], border[2], border[3], border[4])
end

local function applyFillTexture(target, key, path, alpha)
  if not target[key] then
    target[key] = target:CreateTexture(nil, "BACKGROUND", nil, 1)
    target[key]:SetPoint("TOPLEFT", 1, -1)
    target[key]:SetPoint("BOTTOMRIGHT", -1, 1)
  end
  target[key]:SetTexture(path)
  target[key]:SetVertexColor(1, 1, 1, alpha)
end

local function clamp01(value)
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function shiftColor(color, delta, alphaOverride)
  return {
    clamp01((color[1] or 0) + delta),
    clamp01((color[2] or 0) + delta),
    clamp01((color[3] or 0) + delta),
    alphaOverride or color[4] or 1,
  }
end

local function getButtonVariantPalette(base, variant)
  variant = tostring(variant or "default")
  if variant == "primary" then
    return {
      bg = shiftColor(base.sectionAccent, -0.12, 0.92),
      hover = shiftColor(base.sectionAccent, -0.04, 0.98),
      pressed = shiftColor(base.sectionAccent, -0.18, 1.0),
      border = shiftColor(base.sectionAccent, 0.02, 0.95),
      text = { 1.0, 0.98, 0.92 },
    }
  elseif variant == "danger" then
    return {
      bg = { 0.42, 0.14, 0.16, 0.88 },
      hover = { 0.56, 0.18, 0.20, 0.94 },
      pressed = { 0.34, 0.10, 0.12, 1.0 },
      border = { 0.95, 0.36, 0.32, 0.94 },
      text = { 1.0, 0.94, 0.94 },
    }
  elseif variant == "ghost" then
    return {
      bg = { base.sectionBG[1], base.sectionBG[2], base.sectionBG[3], 0.38 },
      hover = { base.sectionBG[1] + 0.06, base.sectionBG[2] + 0.06, base.sectionBG[3] + 0.06, 0.58 },
      pressed = { base.sectionBG[1] + 0.03, base.sectionBG[2] + 0.03, base.sectionBG[3] + 0.03, 0.72 },
      border = { base.sectionBorder[1], base.sectionBorder[2], base.sectionBorder[3], 0.55 },
      text = { 0.90, 0.96, 1.0 },
    }
  end

  return {
    bg = { base.buttonBG[1], base.buttonBG[2], base.buttonBG[3], 0.86 },
    hover = { base.buttonHover[1], base.buttonHover[2], base.buttonHover[3], 0.94 },
    pressed = shiftColor(base.buttonBG, -0.04, 0.98),
    border = { base.buttonBorder[1], base.buttonBorder[2], base.buttonBorder[3], 0.80 },
    text = { 0.94, 0.97, 1.0 },
  }
end

local function getButtonFontString(button)
  return (button.GetFontString and button:GetFontString()) or button.Text
end

local function applyButtonState(button, state)
  if not button or not button._alButtonSkin then
    return
  end

  local variantPalette = getButtonVariantPalette(S:GetPalette(), button._alButtonVariant)
  local palette = variantPalette
  local bg = palette.bg
  local border = palette.border
  local text = palette.text
  local accent = shiftColor(border, 0.10, 0.95)
  local shadowAlpha = 0.28

  if button._alButtonSelected then
    bg = palette.hover
    border = shiftColor(palette.border, 0.10, 0.98)
    text = { 0.96, 0.98, 1.0 }
    accent = shiftColor(border, 0.08, 1.0)
    shadowAlpha = 0.36
  elseif state == "pressed" then
    bg = palette.pressed
    accent = shiftColor(border, -0.04, 0.82)
    shadowAlpha = 0.16
  elseif state == "hover" then
    bg = palette.hover
    border = shiftColor(palette.border, 0.06, 0.92)
    accent = shiftColor(border, 0.10, 1.0)
    shadowAlpha = 0.34
  end

  button._alButtonSkin.bg:SetColorTexture(bg[1], bg[2], bg[3], bg[4])
  button._alButtonSkin.border:SetColorTexture(border[1], border[2], border[3], border[4])
  if button._alButtonSkin.shadow then
    button._alButtonSkin.shadow:SetColorTexture(0, 0, 0, shadowAlpha)
  end

  if button._alButtonSkin.innerBorder then
    button._alButtonSkin.innerBorder:SetColorTexture(border[1], border[2], border[3], 0.16)
  end
  if button._alButtonSkin.accent then
    button._alButtonSkin.accent:SetColorTexture(accent[1], accent[2], accent[3], accent[4] or 0.95)
  end
  if button._alButtonSkin.bottomShade then
    button._alButtonSkin.bottomShade:SetColorTexture(0, 0, 0, state == "pressed" and 0.06 or 0.14)
  end
  if button._alButtonSkin.gloss then
    if state == "pressed" then
      button._alButtonSkin.gloss:SetAlpha(0.03)
    elseif state == "hover" or button._alButtonSelected then
      button._alButtonSkin.gloss:SetAlpha(0.12)
    else
      button._alButtonSkin.gloss:SetAlpha(0.08)
    end
  end

  local fs = getButtonFontString(button)
  if fs and fs.SetTextColor then
    fs:SetTextColor(text[1], text[2], text[3])
    fs:SetShadowColor(0, 0, 0, 0.85)
    fs:SetShadowOffset(1, -1)
  end
end

function S:ApplyWindow(frame)
  if not frame then
    return
  end
  local p = self:GetPalette()
  applyBackdrop(frame, p.windowBG, p.windowBorder)
  applyFillTexture(frame, "_alWindowFill", self:GetResolvedTexturePath(), p.textureAlpha)
  if frame.Bg then
    frame.Bg:Hide()
  end
  if frame.NineSlice then
    frame.NineSlice:SetAlpha(0.12)
  end
end

function S:ApplySection(frame)
  if not frame then
    return
  end
  local p = self:GetPalette()
  applyBackdrop(frame, p.sectionBG, p.sectionBorder)
  applyFillTexture(frame, "_alSectionFill", self:GetResolvedTexturePath(), p.textureAlpha)

  if not frame._alSectionAccent then
    frame._alSectionAccent = frame:CreateTexture(nil, "ARTWORK")
    frame._alSectionAccent:SetHeight(1)
    frame._alSectionAccent:SetPoint("TOPLEFT", 2, -2)
    frame._alSectionAccent:SetPoint("TOPRIGHT", -2, -2)
  end
  frame._alSectionAccent:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], p.sectionAccent[4])
end

function S:ApplyButton(button)
  if not button then
    return
  end
  if not button._alButtonStyled then
    button._alButtonStyled = true
    button:SetNormalTexture("")
    button:SetPushedTexture("")
    button:SetHighlightTexture("")
    if button.Left then
      button.Left:SetAlpha(0)
      button.Left:Hide()
    end
    if button.Middle then
      button.Middle:SetAlpha(0)
      button.Middle:Hide()
    end
    if button.Right then
      button.Right:SetAlpha(0)
      button.Right:Hide()
    end

    local skin = {}
    skin.shadow = button:CreateTexture(nil, "BACKGROUND")
    skin.shadow:SetPoint("TOPLEFT", 0, -1)
    skin.shadow:SetPoint("BOTTOMRIGHT", 0, 1)
    skin.shadow:SetTexture("Interface\\Buttons\\WHITE8x8")

    skin.bg = button:CreateTexture(nil, "BORDER")
    skin.bg:SetPoint("TOPLEFT", 1, -1)
    skin.bg:SetPoint("BOTTOMRIGHT", -1, 1)
    skin.bg:SetTexture("Interface\\Buttons\\WHITE8x8")

    skin.gloss = button:CreateTexture(nil, "ARTWORK")
    skin.gloss:SetPoint("TOPLEFT", 2, -2)
    skin.gloss:SetPoint("TOPRIGHT", -2, -2)
    skin.gloss:SetHeight(math.max(7, math.floor((button:GetHeight() or 24) * 0.40)))
    skin.gloss:SetTexture("Interface\\Buttons\\WHITE8x8")
    if skin.gloss.SetGradientAlpha then
      skin.gloss:SetGradientAlpha("VERTICAL", 1, 1, 1, 0.14, 1, 1, 1, 0.02)
    else
      skin.gloss:SetColorTexture(1, 1, 1, 0.08)
    end

    skin.accent = button:CreateTexture(nil, "ARTWORK")
    skin.accent:SetPoint("TOPLEFT", 2, -2)
    skin.accent:SetPoint("TOPRIGHT", -2, -2)
    skin.accent:SetHeight(1)
    skin.accent:SetTexture("Interface\\Buttons\\WHITE8x8")

    skin.bottomShade = button:CreateTexture(nil, "ARTWORK")
    skin.bottomShade:SetPoint("BOTTOMLEFT", 2, 2)
    skin.bottomShade:SetPoint("BOTTOMRIGHT", -2, 2)
    skin.bottomShade:SetHeight(math.max(5, math.floor((button:GetHeight() or 24) * 0.22)))
    skin.bottomShade:SetTexture("Interface\\Buttons\\WHITE8x8")

    skin.border = button:CreateTexture(nil, "BORDER")
    skin.border:SetPoint("TOPLEFT", 0, 0)
    skin.border:SetPoint("BOTTOMRIGHT", 0, 0)
    skin.border:SetTexture("Interface\\Buttons\\WHITE8x8")

    skin.innerBorder = button:CreateTexture(nil, "BORDER")
    skin.innerBorder:SetPoint("TOPLEFT", 1, -1)
    skin.innerBorder:SetPoint("BOTTOMRIGHT", -1, 1)
    skin.innerBorder:SetTexture("Interface\\Buttons\\WHITE8x8")

    button._alButtonSkin = skin

    button:HookScript("OnEnter", function(selfBtn)
      applyButtonState(selfBtn, "hover")
    end)
    button:HookScript("OnLeave", function(selfBtn)
      applyButtonState(selfBtn, "normal")
    end)
    button:HookScript("OnMouseDown", function(selfBtn)
      applyButtonState(selfBtn, "pressed")
    end)
    button:HookScript("OnMouseUp", function(selfBtn)
      applyButtonState(selfBtn, selfBtn:IsMouseOver() and "hover" or "normal")
    end)
    button:HookScript("OnEnable", function(selfBtn)
      applyButtonState(selfBtn, "normal")
    end)
    button:HookScript("OnDisable", function(selfBtn)
      if selfBtn._alButtonSkin then
        selfBtn._alButtonSkin.bg:SetColorTexture(0.14, 0.16, 0.20, 0.55)
        selfBtn._alButtonSkin.border:SetColorTexture(0.28, 0.30, 0.34, 0.50)
      end
      local fs = getButtonFontString(selfBtn)
      if fs and fs.SetTextColor then
        fs:SetTextColor(0.58, 0.62, 0.68)
      end
    end)
  end

  if button.SetTextInsets then
    button:SetTextInsets(10, 10, 0, 0)
  end

  if not button._alButtonVariant then
    button._alButtonVariant = "default"
  end
  applyButtonState(button, "normal")
end

function S:SetButtonVariant(button, variant)
  if not button then
    return
  end
  button._alButtonVariant = tostring(variant or "default")
  self:ApplyButton(button)
  applyButtonState(button, "normal")
end

function S:SetButtonSelected(button, selected)
  if not button then
    return
  end
  button._alButtonSelected = selected == true
  self:ApplyButton(button)
  applyButtonState(button, "normal")
end

function S:ApplyEditBox(edit)
  if not edit then
    return
  end
  local p = self:GetPalette()

  if not edit._alEditStyled then
    edit._alEditStyled = true
    edit._alEditBG = edit:CreateTexture(nil, "BACKGROUND")
    edit._alEditBG:SetPoint("TOPLEFT", -4, 4)
    edit._alEditBG:SetPoint("BOTTOMRIGHT", 4, -4)
    edit._alEditBG:SetTexture("Interface\\Buttons\\WHITE8x8")

    edit._alEditBorder = edit:CreateTexture(nil, "BORDER")
    edit._alEditBorder:SetPoint("TOPLEFT", -4, 4)
    edit._alEditBorder:SetPoint("BOTTOMRIGHT", 4, -4)
    edit._alEditBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
  end

  edit._alEditBG:SetVertexColor(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.9)
  edit._alEditBorder:SetVertexColor(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.42)
end

function S:ApplyDropdown(dropdown)
  if not dropdown then
    return
  end
  local p = self:GetPalette()
  if dropdown.Left then
    dropdown.Left:SetAlpha(0)
    dropdown.Left:Hide()
  end
  if dropdown.Middle then
    dropdown.Middle:SetAlpha(0)
    dropdown.Middle:Hide()
  end
  if dropdown.Right then
    dropdown.Right:SetAlpha(0)
    dropdown.Right:Hide()
  end
  if not dropdown._alDropBG then
    dropdown._alDropBG = dropdown:CreateTexture(nil, "BACKGROUND")
    dropdown._alDropBG:SetPoint("TOPLEFT", 16, -3)
    dropdown._alDropBG:SetPoint("BOTTOMRIGHT", -18, 8)
    dropdown._alDropBG:SetTexture("Interface\\Buttons\\WHITE8x8")

    dropdown._alDropBorder = dropdown:CreateTexture(nil, "BORDER")
    dropdown._alDropBorder:SetPoint("TOPLEFT", 16, -3)
    dropdown._alDropBorder:SetPoint("BOTTOMRIGHT", -18, 8)
    dropdown._alDropBorder:SetTexture("Interface\\Buttons\\WHITE8x8")

    dropdown._alDropAccent = dropdown:CreateTexture(nil, "ARTWORK")
    dropdown._alDropAccent:SetPoint("TOPLEFT", 17, -4)
    dropdown._alDropAccent:SetPoint("TOPRIGHT", -19, -4)
    dropdown._alDropAccent:SetHeight(1)
    dropdown._alDropAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  dropdown._alDropBG:SetColorTexture(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.82)
  dropdown._alDropBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.55)
  dropdown._alDropAccent:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.70)
  if dropdown.Text then
    dropdown.Text:SetTextColor(0.95, 0.97, 1.0)
    dropdown.Text:SetShadowOffset(1, -1)
  end
  if dropdown.Button then
    local btn = dropdown.Button
    if btn.Left then btn.Left:SetAlpha(0) end
    if btn.Middle then btn.Middle:SetAlpha(0) end
    if btn.Right then btn.Right:SetAlpha(0) end
    if btn.NormalTexture then btn.NormalTexture:SetAlpha(0) end
    if btn.PushedTexture then btn.PushedTexture:SetAlpha(0) end
    if btn.HighlightTexture then btn.HighlightTexture:SetAlpha(0) end
    btn:ClearAllPoints()
    btn:SetPoint("RIGHT", dropdown, "RIGHT", -18, -2)
    btn:SetSize(18, 18)

    if not btn._alDropBtnBG then
      btn._alDropBtnBG = btn:CreateTexture(nil, "BORDER")
      btn._alDropBtnBG:SetAllPoints()
      btn._alDropBtnBG:SetTexture("Interface\\Buttons\\WHITE8x8")

      btn._alDropBtnBorder = btn:CreateTexture(nil, "ARTWORK")
      btn._alDropBtnBorder:SetPoint("TOPLEFT", 0, 0)
      btn._alDropBtnBorder:SetPoint("BOTTOMRIGHT", 0, 0)
      btn._alDropBtnBorder:SetTexture("Interface\\Buttons\\WHITE8x8")

      btn._alDropBtnGlyph = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      btn._alDropBtnGlyph:SetPoint("CENTER", 0, -1)
      btn._alDropBtnGlyph:SetText("v")

      btn:HookScript("OnEnter", function(selfBtn)
        selfBtn._alDropBtnBG:SetColorTexture(p.buttonHover[1], p.buttonHover[2], p.buttonHover[3], 0.92)
      end)
      btn:HookScript("OnLeave", function(selfBtn)
        selfBtn._alDropBtnBG:SetColorTexture(p.buttonBG[1], p.buttonBG[2], p.buttonBG[3], 0.88)
      end)
      btn:HookScript("OnMouseDown", function(selfBtn)
        selfBtn._alDropBtnBG:SetColorTexture(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.96)
      end)
      btn:HookScript("OnMouseUp", function(selfBtn)
        if selfBtn:IsMouseOver() then
          selfBtn._alDropBtnBG:SetColorTexture(p.buttonHover[1], p.buttonHover[2], p.buttonHover[3], 0.92)
        else
          selfBtn._alDropBtnBG:SetColorTexture(p.buttonBG[1], p.buttonBG[2], p.buttonBG[3], 0.88)
        end
      end)
    end

    btn._alDropBtnBG:SetColorTexture(p.buttonBG[1], p.buttonBG[2], p.buttonBG[3], 0.88)
    btn._alDropBtnBorder:SetColorTexture(p.buttonBorder[1], p.buttonBorder[2], p.buttonBorder[3], 0.72)
    btn._alDropBtnGlyph:SetTextColor(0.92, 0.96, 1.0)
  end
end

function S:ApplyCheckbox(check)
  if not check then
    return
  end
  local p = self:GetPalette()
  if check.Left then
    check.Left:SetAlpha(0)
  end
  if check.Middle then
    check.Middle:SetAlpha(0)
  end
  if check.Right then
    check.Right:SetAlpha(0)
  end
  local normal = check.GetNormalTexture and check:GetNormalTexture() or nil
  local pushed = check.GetPushedTexture and check:GetPushedTexture() or nil
  local highlight = check.GetHighlightTexture and check:GetHighlightTexture() or nil
  local checked = check.GetCheckedTexture and check:GetCheckedTexture() or nil
  if normal then normal:SetAlpha(0) end
  if pushed then pushed:SetAlpha(0) end
  if highlight then highlight:SetAlpha(0) end
  if checked then checked:SetAlpha(0) end

  if not check._alCheckBG then
    check._alCheckBG = check:CreateTexture(nil, "BORDER")
    check._alCheckBG:SetPoint("TOPLEFT", 4, -4)
    check._alCheckBG:SetPoint("BOTTOMRIGHT", -4, 4)
    check._alCheckBG:SetTexture("Interface\\Buttons\\WHITE8x8")

    check._alCheckBorder = check:CreateTexture(nil, "ARTWORK")
    check._alCheckBorder:SetPoint("TOPLEFT", 4, -4)
    check._alCheckBorder:SetPoint("BOTTOMRIGHT", -4, 4)
    check._alCheckBorder:SetTexture("Interface\\Buttons\\WHITE8x8")

    check._alCheckMark = check:CreateTexture(nil, "OVERLAY")
    check._alCheckMark:SetPoint("TOPLEFT", 8, -8)
    check._alCheckMark:SetPoint("BOTTOMRIGHT", -8, 8)
    check._alCheckMark:SetTexture("Interface\\Buttons\\WHITE8x8")

    check:HookScript("OnClick", function(selfCheck)
      S:RefreshCheckbox(selfCheck)
    end)
  end

  check._alCheckBG:SetColorTexture(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.82)
  check._alCheckBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.65)
  self:RefreshCheckbox(check)
end

function S:RefreshCheckbox(check)
  if not check or not check._alCheckMark then
    return
  end
  local p = self:GetPalette()
  if check:GetChecked() then
    check._alCheckMark:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.95)
    check._alCheckMark:Show()
    check._alCheckBorder:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.90)
  else
    check._alCheckMark:Hide()
    check._alCheckBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.65)
  end
end

function S:ApplyClickableRow(row, variant)
  if not row then
    return
  end
  local p = self:GetPalette()
  row._alRowVariant = variant or row._alRowVariant or "row"
  if not row._alRowBG then
    row._alRowBG = row.bg or row:CreateTexture(nil, "BACKGROUND")
    row._alRowBG:SetAllPoints()
    row._alRowBG:SetTexture("Interface\\Buttons\\WHITE8x8")

    row._alRowBorder = row:CreateTexture(nil, "BORDER")
    row._alRowBorder:SetPoint("TOPLEFT", 0, 0)
    row._alRowBorder:SetPoint("BOTTOMRIGHT", 0, 0)
    row._alRowBorder:SetTexture("Interface\\Buttons\\WHITE8x8")

    row._alRowAccent = row:CreateTexture(nil, "ARTWORK")
    row._alRowAccent:SetPoint("TOPLEFT", 1, -1)
    row._alRowAccent:SetPoint("TOPRIGHT", -1, -1)
    row._alRowAccent:SetHeight(1)
    row._alRowAccent:SetTexture("Interface\\Buttons\\WHITE8x8")
  end

  if row._alRowVariant == "header" then
    row._alRowBG:SetColorTexture(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.90)
    row._alRowBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.70)
    row._alRowAccent:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.85)
  else
    row._alRowBG:SetColorTexture(p.rowNormal[1], p.rowNormal[2], p.rowNormal[3], p.rowNormal[4])
    row._alRowBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], 0.32)
    row._alRowAccent:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.35)
  end
end

function S:SetClickableRowState(row, state)
  if not row or not row._alRowBG then
    return
  end
  local p = self:GetPalette()
  if row._alRowVariant == "header" then
    row._alRowBG:SetColorTexture(p.sectionBG[1], p.sectionBG[2], p.sectionBG[3], 0.90)
    return
  end
  local color = p.rowNormal
  local borderAlpha = 0.32
  local accentAlpha = 0.35
  if state == "selected" then
    color = p.rowSelected
    borderAlpha = 0.76
    accentAlpha = 0.95
  elseif state == "hover" then
    color = p.rowHover
    borderAlpha = 0.52
    accentAlpha = 0.72
  end
  row._alRowBG:SetColorTexture(color[1], color[2], color[3], color[4])
  row._alRowBorder:SetColorTexture(p.sectionBorder[1], p.sectionBorder[2], p.sectionBorder[3], borderAlpha)
  row._alRowAccent:SetColorTexture(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], accentAlpha)
end

function S:ApplyCloseButton(button)
  if not button then
    return
  end
  self:SetButtonVariant(button, "ghost")
  button:SetSize(24, 24)
  if button.SetNormalTexture then
    button:SetNormalTexture("")
    button:SetPushedTexture("")
    button:SetHighlightTexture("")
  end
  if not button._alCloseGlyph then
    button._alCloseGlyph = button:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    button._alCloseGlyph:SetPoint("CENTER", 0, 0)
    button._alCloseGlyph:SetText("x")
  end
end

function S:GetListRowColor(state)
  local p = self:GetPalette()
  local color = p.rowNormal
  if state == "hover" then
    color = p.rowHover
  elseif state == "selected" then
    color = p.rowSelected
  end
  return color[1], color[2], color[3], color[4]
end

