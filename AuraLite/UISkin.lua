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
    windowBG = { 0.13, 0.20, 0.30, 0.84 },
    windowBorder = { 0.20, 0.56, 0.82, 0.92 },
    sectionBG = { 0.17, 0.27, 0.40, 0.78 },
    sectionBorder = { 0.24, 0.48, 0.72, 0.92 },
    sectionAccent = { 0.48, 0.82, 1.00, 0.90 },
    textureAlpha = 0.10,
    buttonBG = { 0.12, 0.22, 0.34, 0.88 },
    buttonHover = { 0.19, 0.33, 0.48, 0.94 },
    buttonBorder = { 0.22, 0.62, 0.92, 0.9 },
    rowNormal = { 0.11, 0.19, 0.30, 0.60 },
    rowHover = { 0.21, 0.34, 0.50, 0.86 },
    rowSelected = { 0.28, 0.50, 0.76, 0.90 },
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
  local p = self:GetPalette()

  if not button._alButtonStyled then
    button._alButtonStyled = true
    button:SetNormalTexture("Interface\\Buttons\\WHITE8x8")
    button:SetPushedTexture("Interface\\Buttons\\WHITE8x8")
    button:SetHighlightTexture("Interface\\Buttons\\WHITE8x8")
  end

  if button.GetNormalTexture then
    local n = button:GetNormalTexture()
    if n then
      n:SetVertexColor(p.buttonBG[1], p.buttonBG[2], p.buttonBG[3], p.buttonBG[4])
    end
    local pressed = button:GetPushedTexture()
    if pressed then
      pressed:SetVertexColor(p.buttonHover[1], p.buttonHover[2], p.buttonHover[3], p.buttonHover[4])
    end
    local high = button:GetHighlightTexture()
    if high then
      high:SetVertexColor(p.buttonHover[1], p.buttonHover[2], p.buttonHover[3], 0.25)
    end
  end

  if not button._alButtonBorder then
    button._alButtonBorder = button:CreateTexture(nil, "BORDER")
    button._alButtonBorder:SetPoint("TOPLEFT", 0, 0)
    button._alButtonBorder:SetPoint("BOTTOMRIGHT", 0, 0)
    button._alButtonBorder:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  button._alButtonBorder:SetVertexColor(p.buttonBorder[1], p.buttonBorder[2], p.buttonBorder[3], 0.24)
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
  if dropdown.Text then
    dropdown.Text:SetTextColor(0.95, 0.97, 1.0)
    dropdown.Text:SetShadowOffset(1, -1)
  end
  if dropdown.Button and dropdown.Button.NormalTexture then
    dropdown.Button.NormalTexture:SetVertexColor(p.sectionAccent[1], p.sectionAccent[2], p.sectionAccent[3], 0.9)
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

