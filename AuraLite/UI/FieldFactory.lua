local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.FieldFactory = UI.FieldFactory or {}
local F = UI.FieldFactory

local SpellInput = UI.SpellInput
local Skin = ns.UISkin
local Widgets = UI.Widgets or {}

local function createInputBackground(parent)
  local bg = parent:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0)
  return bg
end

local function styleFieldShell(holder)
  holder:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Buttons\\WHITE8x8",
    tile = true,
    tileSize = 8,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  })
  holder:SetBackdropColor(0.10, 0.11, 0.13, 0.30)
  holder:SetBackdropBorderColor(0.24, 0.25, 0.28, 0.18)

  if not holder._alBottomShade then
    holder._alBottomShade = holder:CreateTexture(nil, "BORDER")
    holder._alBottomShade:SetPoint("BOTTOMLEFT", 1, 1)
    holder._alBottomShade:SetPoint("BOTTOMRIGHT", -1, 1)
    holder._alBottomShade:SetHeight(10)
    holder._alBottomShade:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  holder._alBottomShade:SetColorTexture(0, 0, 0, 0.03)

  if not holder._alTopLine then
    holder._alTopLine = holder:CreateTexture(nil, "ARTWORK")
    holder._alTopLine:SetPoint("TOPLEFT", 1, -1)
    holder._alTopLine:SetPoint("TOPRIGHT", -1, -1)
    holder._alTopLine:SetHeight(1)
    holder._alTopLine:SetTexture("Interface\\Buttons\\WHITE8x8")
  end
  holder._alTopLine:SetColorTexture(1.0, 0.82, 0.18, 0.05)
end

local function createFieldShell(parent, field, multiline)
  local holder = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  local hasHelpText = tostring(field and field.help or "") ~= ""
  local isWideWidget = multiline
    or field.widget == "multiline"
    or field.widget == "dropdown"
    or field.widget == "bartexture"
    or field.widget == "soundpicker"
    or field.widget == "groupselect"
  local baseHeight = isWideWidget and 58 or 30
  holder:SetHeight(baseHeight)
  styleFieldShell(holder)

  local label = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  label:SetPoint("TOPLEFT", 12, -4)
  label:SetPoint("RIGHT", -32, 0)
  label:SetJustifyH("LEFT")
  label:SetText(field.label or field.key or "Field")
  label:SetTextColor(0.78, 0.82, 0.88)

  local helpIcon = nil
  if hasHelpText and Widgets.HelpIconWidget and Widgets.HelpIconWidget.Create then
    helpIcon = Widgets.HelpIconWidget:Create(holder, {
      title = field.label or field.key or "Field",
      body = field.help,
      size = 14,
    })
    helpIcon:SetPoint("TOPRIGHT", -10, -6)
  end

  local anchor = CreateFrame("Frame", nil, holder)
  if isWideWidget then
    anchor:SetPoint("TOPLEFT", 12, -18)
    anchor:SetPoint("TOPRIGHT", -12, -18)
    anchor:SetHeight(baseHeight - 22)
  else
    anchor:SetPoint("TOPRIGHT", -10, -3)
    anchor:SetPoint("BOTTOMRIGHT", -10, 4)
    anchor:SetWidth(math.max(180, tonumber(field.width) or 220))
  end

  holder.label = label
  holder.desc = nil
  holder.helpIcon = helpIcon
  holder.anchor = anchor
  holder.hasHelpText = hasHelpText
  holder.isWideWidget = isWideWidget
  return holder
end

local function flattenMenuOptions(options, prefix, rows)
  rows = rows or {}
  prefix = tostring(prefix or "")
  for i = 1, #(options or {}) do
    local opt = options[i]
    local label = tostring(opt and opt.label or opt and opt.value or "")
    if type(opt and opt.menuList) == "table" and #(opt.menuList or {}) > 0 then
      local nextPrefix = prefix ~= "" and (prefix .. " / " .. label) or label
      flattenMenuOptions(opt.menuList, nextPrefix, rows)
    elseif opt and opt.value ~= nil then
      rows[#rows + 1] = {
        label = prefix ~= "" and (prefix .. " / " .. label) or label,
        value = opt.value,
      }
    end
  end
  return rows
end

local function findOptionLabel(options, wanted)
  wanted = tostring(wanted or "")
  for i = 1, #(options or {}) do
    local opt = options[i]
    if tostring(opt and opt.value or "") == wanted then
      return tostring(opt.label or wanted)
    end
    if type(opt and opt.menuList) == "table" then
      local nested = findOptionLabel(opt.menuList, wanted)
      if nested then
        local parent = tostring(opt.label or "")
        if parent ~= "" and nested ~= parent then
          return parent .. " / " .. nested
        end
        return nested
      end
    end
  end
  return nil
end

local function createPickerControl(holder, field, model, config)
  config = type(config) == "table" and config or {}
  local helperText = tostring(config.helperText or "")
  local hasPreview = config.previewAction ~= nil
  local width = tonumber(field and field.width) or tonumber(config.width) or 320

  if helperText ~= "" then
    holder:SetHeight(holder.hasHelpText and 102 or 84)
  else
    holder:SetHeight(60)
  end

  local control = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  control:SetPoint("TOPLEFT", holder.anchor, "TOPLEFT", 0, 0)
  control:SetPoint("TOPRIGHT", holder.anchor, "TOPRIGHT", 0, 0)
  control:SetHeight(28)
  control:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  control:SetBackdropColor(0.04, 0.08, 0.14, 0.88)
  control:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.88)
  control.options = {}
  control.value = nil
  control.onChanged = nil

  local rightInset = hasPreview and -58 or -30
  local valueText = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("LEFT", 8, 0)
  valueText:SetPoint("RIGHT", rightInset, 0)
  valueText:SetJustifyH("LEFT")
  valueText:SetWordWrap(false)

  local previewBtn = nil
  if hasPreview then
    previewBtn = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
    previewBtn:SetSize(22, 22)
    previewBtn:SetPoint("RIGHT", -29, 0)
    previewBtn:SetText(config.previewGlyph or ">")
    if Skin and Skin.SetButtonVariant then
      Skin:SetButtonVariant(previewBtn, "ghost")
    end
  end

  local trigger = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
  trigger:SetSize(24, 22)
  trigger:SetPoint("RIGHT", -3, 0)
  trigger:SetText("v")
  if Skin and Skin.SetButtonVariant then
    Skin:SetButtonVariant(trigger, "ghost")
  end

  local helper = nil
  if helperText ~= "" then
    helper = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    helper:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -4)
    helper:SetPoint("RIGHT", -4, 0)
    helper:SetJustifyH("LEFT")
    helper:SetText(helperText)
  end

  local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  popup:SetFrameStrata("TOOLTIP")
  popup:SetClampedToScreen(true)
  popup:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  popup:SetBackdropColor(0.02, 0.05, 0.11, 0.97)
  popup:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.92)
  popup:SetSize(width + 24, 228)
  popup:Hide()

  local popupHeader = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  popupHeader:SetPoint("TOPLEFT", 10, -10)
  popupHeader:SetText(tostring(config.popupTitle or field.label or "Options"))

  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -28)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width, 1)
  scroll:SetScrollChild(content)
  popup.rows = popup.rows or {}

  local function closePopup()
    popup:Hide()
  end

  local function updateControl()
    control.value = model[field.key]
    local label = nil
    if type(config.labelProvider) == "function" then
      label = config.labelProvider(control.value, control.options)
    end
    if not label or label == "" then
      label = findOptionLabel(control.options, control.value) or tostring(config.placeholder or "Choose...")
    end
    valueText:SetText(label)
  end

  local function selectValue(value, emit)
    control.value = value
    model[field.key] = value
    updateControl()
    if emit and control.onChanged then
      control.onChanged(value)
    end
    closePopup()
  end

  function control:SetOptions(options)
    self.options = options or {}
    local flat = flattenMenuOptions(self.options)
    local rowHeight = 24
    for i = 1, #flat do
      local row = popup.rows[i]
      if not row then
        row = CreateFrame("Button", nil, content)
        if Skin and Skin.ApplyClickableRow then
          Skin:ApplyClickableRow(row, "row")
        end
        if Skin and Skin.SetClickableRowState then
          row:SetScript("OnEnter", function(selfRow)
            Skin:SetClickableRowState(selfRow, "hover")
          end)
          row:SetScript("OnLeave", function(selfRow)
            Skin:SetClickableRowState(selfRow, "normal")
          end)
        end
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -12, 0)
        row.text:SetJustifyH("LEFT")
        popup.rows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -((i - 1) * rowHeight))
      row:SetSize(width - 8, rowHeight)
      row.value = flat[i].value
      row.text:SetText(flat[i].label or tostring(flat[i].value or ""))
      row:SetScript("OnClick", function(selfRow)
        selectValue(selfRow.value, true)
      end)
      row:Show()
    end
    for i = #flat + 1, #(popup.rows or {}) do
      popup.rows[i]:Hide()
    end
    content:SetHeight(math.max(1, #flat * rowHeight))
    updateControl()
  end

  function control:SetValue(value, emit)
    selectValue(value, emit == true)
  end

  function control:GetValue()
    return self.value
  end

  function control:SetOnValueChanged(fn)
    self.onChanged = fn
  end

  if previewBtn then
    previewBtn:SetScript("OnClick", function()
      config.previewAction(model[field.key])
    end)
  end

  trigger:SetScript("OnClick", function()
    if popup:IsShown() then
      closePopup()
      return
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", control, "BOTTOMLEFT", -2, -4)
    popup:Show()
  end)

  control:SetScript("OnHide", closePopup)
  control.helper = helper
  control.popup = popup
  control.valueText = valueText
  updateControl()
  holder.control = control
  holder.popup = popup
  return control
end

local function createDropdown(holder, field, model)
  return createPickerControl(holder, field, model, {
    popupTitle = field and field.label or "Options",
    placeholder = "Choose...",
  })
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

local function formatColorCSV(r, g, b)
  return string.format("%.2f,%.2f,%.2f", tonumber(r) or 1, tonumber(g) or 1, tonumber(b) or 1)
end

local function findStatusbarEntry(entries, value)
  value = tostring(value or "")
  for i = 1, #(entries or {}) do
    local row = entries[i]
    if tostring(row.value or "") == value then
      return row
    end
  end
  return nil
end

local function createStatusbarPicker(holder, field, model, onChange)
  local compact = field and field.minimalHelp == true
  holder:SetHeight(compact and 122 or (holder.hasHelpText and 150 or 132))

  local entries = {}
  if ns.Media and ns.Media.GetStatusbarEntries then
    entries = ns.Media:GetStatusbarEntries()
  end

  local selectedValue = tostring(model[field.key] or "")
  local control = CreateFrame("Frame", nil, holder, "BackdropTemplate")
  control:SetPoint("TOPLEFT", holder.anchor, "TOPLEFT", 0, 0)
  control:SetSize(field.width or 320, 28)
  control:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  control:SetBackdropColor(0.04, 0.08, 0.14, 0.88)
  control:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.88)

  local preview = CreateFrame("StatusBar", nil, control)
  preview:SetPoint("LEFT", 6, 0)
  preview:SetSize(86, 14)
  preview:SetMinMaxValues(0, 1)
  preview:SetValue(1)
  preview:SetStatusBarColor(0.18, 0.72, 1.0, 0.95)
  preview.bg = preview:CreateTexture(nil, "BACKGROUND")
  preview.bg:SetAllPoints()
  preview.bg:SetColorTexture(0.06, 0.10, 0.16, 0.85)

  local valueText = control:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  valueText:SetPoint("LEFT", preview, "RIGHT", 10, 0)
  valueText:SetPoint("RIGHT", -34, 0)
  valueText:SetJustifyH("LEFT")

  local trigger = CreateFrame("Button", nil, control, "UIPanelButtonTemplate")
  trigger:SetSize(24, 22)
  trigger:SetPoint("RIGHT", -3, 0)
  trigger:SetText("v")
  if Skin and Skin.SetButtonVariant then
    Skin:SetButtonVariant(trigger, "ghost")
  end

  local help = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  help:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -4)
  help:SetPoint("RIGHT", -4, 0)
  help:SetJustifyH("LEFT")
  help:SetText("SharedMedia packs add more textures here automatically.")
  if compact then
    help:Hide()
  end

  local customLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  customLabel:SetPoint("TOPLEFT", compact and control or help, "BOTTOMLEFT", 0, -8)
  customLabel:SetText("Custom Path")

  local customBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  customBox:SetAutoFocus(false)
  customBox:SetPoint("TOPLEFT", customLabel, "BOTTOMLEFT", 0, -4)
  customBox:SetSize(field.width or 320, 24)
  customBox:SetTextInsets(6, 6, 0, 0)

  local customBg = CreateFrame("Frame", nil, holder)
  customBg:SetPoint("TOPLEFT", customBox, -3, 3)
  customBg:SetPoint("BOTTOMRIGHT", customBox, 3, -3)
  customBg:SetFrameLevel(holder:GetFrameLevel())
  if not (Skin and Skin.ApplyEditBox) then
    createInputBackground(customBg)
  end
  customBox:SetFrameLevel(customBg:GetFrameLevel() + 1)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(customBox)
  end

  local popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  popup:SetFrameStrata("TOOLTIP")
  popup:SetClampedToScreen(true)
  popup:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  popup:SetBackdropColor(0.02, 0.05, 0.11, 0.97)
  popup:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.92)
  popup:SetSize((field.width or 320) + 24, 228)
  popup:Hide()

  local popupHeader = popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  popupHeader:SetPoint("TOPLEFT", 10, -10)
  popupHeader:SetText("Statusbar Textures")

  local scroll = CreateFrame("ScrollFrame", nil, popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -28)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize((field.width or 320), 1)
  scroll:SetScrollChild(content)
  popup.rows = popup.rows or {}

  local customOption = {
    value = "__custom__",
    label = "Custom Path",
    texture = "Interface\\TargetingFrame\\UI-StatusBar",
  }

  local function updateControl()
    local currentValue = tostring(model[field.key] or "")
    local custom = currentValue ~= "" and not currentValue:lower():match("^lsm:")
    local selected = findStatusbarEntry(entries, currentValue)
    if custom then
      valueText:SetText("Custom Path")
      customBox:SetText(currentValue)
      customLabel:Show()
      customBox:Show()
      if ns.AuraAPI and ns.AuraAPI.ResolveBarTexturePath then
        preview:SetStatusBarTexture(ns.AuraAPI:ResolveBarTexturePath(currentValue))
      else
        preview:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
      end
    else
      if not selected then
        selected = entries[1]
      end
      valueText:SetText(selected and selected.label or "Default (Blizzard)")
      customBox:SetText("")
      customLabel:Hide()
      customBox:Hide()
      preview:SetStatusBarTexture((selected and selected.texture) or "Interface\\TargetingFrame\\UI-StatusBar")
    end
  end

  local function closePopup()
    popup:Hide()
  end

  local function selectValue(value)
    model[field.key] = tostring(value or "")
    updateControl()
    onChange(field.key, model[field.key])
    closePopup()
  end

  local displayEntries = { customOption }
  for i = 1, #entries do
    displayEntries[#displayEntries + 1] = entries[i]
  end

  local rowHeight = 26
  for i = 1, #displayEntries do
    local row = CreateFrame("Button", nil, content)
    row:SetPoint("TOPLEFT", 0, -((i - 1) * rowHeight))
    row:SetSize((field.width or 320) - 8, rowHeight)
    if Skin and Skin.ApplyClickableRow then
      Skin:ApplyClickableRow(row, "row")
    end
    if Skin and Skin.SetClickableRowState then
      row:SetScript("OnEnter", function(selfRow)
        Skin:SetClickableRowState(selfRow, "hover")
      end)
      row:SetScript("OnLeave", function(selfRow)
        Skin:SetClickableRowState(selfRow, "normal")
      end)
    end

    row.bar = CreateFrame("StatusBar", nil, row)
    row.bar:SetPoint("LEFT", 8, 0)
    row.bar:SetSize(92, 12)
    row.bar:SetMinMaxValues(0, 1)
    row.bar:SetValue(1)
    row.bar:SetStatusBarColor(0.18, 0.72, 1.0, 0.95)
    row.bar.bg = row.bar:CreateTexture(nil, "BACKGROUND")
    row.bar.bg:SetAllPoints()
    row.bar.bg:SetColorTexture(0.06, 0.10, 0.16, 0.85)

    row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.text:SetPoint("LEFT", row.bar, "RIGHT", 10, 0)
    row.text:SetPoint("RIGHT", -10, 0)
    row.text:SetJustifyH("LEFT")

    row.entry = displayEntries[i]
    if row.entry.value == "__custom__" then
      row.bar:SetStatusBarTexture("Interface\\TargetingFrame\\UI-StatusBar")
      row.bar:SetStatusBarColor(0.36, 0.40, 0.48, 0.95)
    else
      row.bar:SetStatusBarTexture(row.entry.texture or "Interface\\TargetingFrame\\UI-StatusBar")
      row.bar:SetStatusBarColor(0.18, 0.72, 1.0, 0.95)
    end
    row.text:SetText(row.entry.label)
    row:SetScript("OnClick", function(selfRow)
      if selfRow.entry.value == "__custom__" then
        model[field.key] = customBox:GetText() or ""
        updateControl()
        closePopup()
        customBox:SetFocus()
        return
      end
      selectValue(selfRow.entry.value)
    end)
    popup.rows[i] = row
  end
  content:SetHeight(#displayEntries * rowHeight)

  customBox:SetScript("OnTextChanged", function(edit)
    local value = tostring(edit:GetText() or "")
    model[field.key] = value
    updateControl()
    onChange(field.key, value)
  end)
  customBox:SetScript("OnEscapePressed", function(edit)
    edit:ClearFocus()
  end)
  customBox:SetScript("OnEnterPressed", function(edit)
    edit:ClearFocus()
  end)

  trigger:SetScript("OnClick", function()
    if popup:IsShown() then
      closePopup()
      return
    end
    popup:ClearAllPoints()
    popup:SetPoint("TOPLEFT", control, "BOTTOMLEFT", -2, -4)
    popup:Show()
  end)

  control:SetScript("OnHide", closePopup)
  updateControl()

  holder.control = control
  holder.popup = popup
  return control
end

local function createSoundPicker(holder, field, model, onChange)
  local options = {}
  if type(field.optionsProvider) == "function" then
    options = field.optionsProvider(model) or {}
  elseif type(field.options) == "table" then
    options = field.options
  end

  local control = createPickerControl(holder, field, model, {
    popupTitle = "Aura Sounds",
    helperText = "Pick a sound, then use > to hear a preview.",
    previewGlyph = ">",
    labelProvider = function(currentValue)
      if ns.SoundManager and ns.SoundManager.GetTokenLabel then
        return ns.SoundManager:GetTokenLabel(tostring(currentValue or "default"), field.soundState or "gain")
      end
      return tostring(currentValue or "default")
    end,
    previewAction = function(currentValue)
      if ns.SoundManager and ns.SoundManager.Preview then
        ns.SoundManager:Preview(currentValue or "default", field.soundState or "gain")
      end
    end,
  })
  control:SetOptions(options or {})
  control:SetValue(tostring(model[field.key] or "default"))
  control:SetOnValueChanged(function(value)
    onChange(field.key, tostring(value or "default"))
  end)

  return control
end

local function createGroupSelect(holder, field, model, onChange)
  local compact = field and field.minimalHelp == true
  holder:SetHeight(compact and 96 or (holder.hasHelpText and 132 or 114))

  local function buildOptions()
    local options = {}
    if type(field.optionsProvider) == "function" then
      options = field.optionsProvider(model) or {}
    elseif type(field.options) == "table" then
      options = field.options
    end
    return options
  end

  local control = createDropdown(holder, field, model)

  local helper = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  helper:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -4)
  helper:SetPoint("RIGHT", -4, 0)
  helper:SetJustifyH("LEFT")
  helper:SetText("A group keeps related auras together so one mover can position them all.")
  if compact then
    helper:Hide()
  end

  local newLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  newLabel:SetPoint("TOPLEFT", compact and control or helper, "BOTTOMLEFT", 0, -8)
  newLabel:SetText("New Group Name")

  local newBox = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
  newBox:SetAutoFocus(false)
  newBox:SetPoint("TOPLEFT", newLabel, "BOTTOMLEFT", 0, -4)
  newBox:SetSize(224, 24)
  newBox:SetTextInsets(6, 6, 0, 0)

  local newBg = CreateFrame("Frame", nil, holder)
  newBg:SetPoint("TOPLEFT", newBox, -3, 3)
  newBg:SetPoint("BOTTOMRIGHT", newBox, 3, -3)
  newBg:SetFrameLevel(holder:GetFrameLevel())
  if not (Skin and Skin.ApplyEditBox) then
    createInputBackground(newBg)
  end
  newBox:SetFrameLevel(newBg:GetFrameLevel() + 1)
  if Skin and Skin.ApplyEditBox then
    Skin:ApplyEditBox(newBox)
  end

  local createBtn = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
  createBtn:SetSize(86, 22)
  createBtn:SetPoint("LEFT", newBox, "RIGHT", 8, 0)
  createBtn:SetText("Create")
  if Skin and Skin.SetButtonVariant then
    Skin:SetButtonVariant(createBtn, "ghost")
  end

  local function refreshOptions(selectedValue)
    control:SetOptions(buildOptions())
    control:SetValue(selectedValue or model[field.key] or model.groupID or "")
  end

  local function commitGroup(groupID)
    groupID = tostring(groupID or "")
    model[field.key] = groupID
    model.groupID = groupID
    refreshOptions(groupID)
    onChange(field.key, groupID)
  end

  local function createGroupFromInput()
    local displayName = tostring(newBox:GetText() or ""):gsub("^%s+", ""):gsub("%s+$", "")
    if displayName == "" or not ns.SettingsData then
      return
    end
    local groupID = ns.SettingsData.SuggestGroupID and ns.SettingsData:SuggestGroupID(displayName) or displayName:lower():gsub("%s+", "_")
    if ns.SettingsData.EnsureGroup then
      ns.SettingsData:EnsureGroup(groupID, displayName)
    end
    newBox:SetText("")
    commitGroup(groupID)
  end

  control:SetOnValueChanged(function(value)
    value = tostring(value or "")
      if value == "__new__" then
        newLabel:Show()
        newBox:Show()
        createBtn:Show()
        newBox:SetFocus()
        return
    end
    newLabel:Hide()
    newBox:Hide()
    createBtn:Hide()
    commitGroup(value)
  end)

  createBtn:SetScript("OnClick", createGroupFromInput)
  newBox:SetScript("OnEnterPressed", function(edit)
    createGroupFromInput()
    edit:ClearFocus()
  end)
  newBox:SetScript("OnEscapePressed", function(edit)
    edit:ClearFocus()
  end)

  newLabel:Hide()
  newBox:Hide()
  createBtn:Hide()
  refreshOptions(model[field.key] or model.groupID or "")
  return control
end

local function attachSpellResolver(holder, control, field, onChange)
  if not SpellInput then
    return
  end

  local function isSpellWidget()
    return field and (field.widget == "spellid" or field.widget == "spellcsv")
  end

  local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  hint:SetPoint("TOPLEFT", control, "BOTTOMLEFT", 0, -2)
  hint:SetPoint("RIGHT", -4, 0)
  hint:SetJustifyH("LEFT")
  hint:SetText("")
  if field and field.compactHint == false then
    hint:Hide()
  end

  local auto = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  auto:SetFrameStrata("TOOLTIP")
  auto:SetFrameLevel((control:GetFrameLevel() or 1) + 10)
  auto:SetClampedToScreen(true)
  auto:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  auto:SetBackdropColor(0.02, 0.05, 0.12, 0.96)
  auto:SetBackdropBorderColor(0.12, 0.50, 0.80, 0.90)
  auto:Hide()
  auto.buttons = {}
  local autocompleteRevision = 0

  local function hideAutocomplete()
    auto:Hide()
  end

  local function extractQuery(text)
    if not isSpellWidget() then
      return ""
    end
    text = tostring(text or "")
    if field.widget == "spellid" then
      return text
    end
    local token = text:match("([^,;]*)$")
    return token or ""
  end

  local function applySuggestion(row)
    if not isSpellWidget() or not row or not row.id then
      return
    end
    local idText = tostring(row.id)
    if field.widget == "spellid" then
      control:SetText(idText)
      onChange(field.key, idText)
    else
      local raw = tostring(control:GetText() or "")
      local prefix = raw:match("^(.*[,;])%s*[^,;]*$") or ""
      local nextText = prefix .. idText
      control:SetText(nextText)
      onChange(field.key, nextText)
    end
    hideAutocomplete()
    control:SetFocus()
  end

  local function showAutocomplete(rows)
    if type(rows) ~= "table" or #rows == 0 then
      hideAutocomplete()
      return
    end

    local rowH = 18
    local width = math.max((control:GetWidth() or 280), 280)
    auto:ClearAllPoints()
    auto:SetPoint("TOPLEFT", control, "BOTTOMLEFT", -2, -4)
    auto:SetSize(width + 4, math.min(#rows, 8) * rowH + 6)

    for i = 1, #rows do
      local row = rows[i]
      local btn = auto.buttons[i]
      if not btn then
        btn = CreateFrame("Button", nil, auto)
        btn:SetSize(width - 4, rowH)
        btn:SetPoint("TOPLEFT", 4, -((i - 1) * rowH) - 3)
        btn.bg = btn:CreateTexture(nil, "BACKGROUND")
        btn.bg:SetAllPoints()
        btn.bg:SetColorTexture(0.08, 0.14, 0.25, 0.78)
        btn.text = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        btn.text:SetPoint("LEFT", 4, 0)
        btn.text:SetPoint("RIGHT", -4, 0)
        btn.text:SetJustifyH("LEFT")
        btn:SetScript("OnEnter", function(selfBtn)
          selfBtn.bg:SetColorTexture(0.18, 0.30, 0.52, 0.90)
        end)
        btn:SetScript("OnLeave", function(selfBtn)
          selfBtn.bg:SetColorTexture(0.08, 0.14, 0.25, 0.78)
        end)
        btn:SetScript("OnMouseDown", function(selfBtn)
          applySuggestion(selfBtn.row)
        end)
        if Skin and Skin.ApplyClickableRow then
          Skin:ApplyClickableRow(btn, "row")
        end
        if Skin and Skin.SetClickableRowState then
          btn:SetScript("OnEnter", function(selfBtn)
            Skin:SetClickableRowState(selfBtn, "hover")
          end)
          btn:SetScript("OnLeave", function(selfBtn)
            Skin:SetClickableRowState(selfBtn, "normal")
          end)
        end
        auto.buttons[i] = btn
      end
      btn.row = row
      btn.text:SetText(string.format("%s (%d)", tostring(row.name or ("Spell " .. tostring(row.id))), tonumber(row.id) or 0))
      btn:Show()
    end

    for i = #rows + 1, #auto.buttons do
      auto.buttons[i]:Hide()
    end

    auto:Show()
  end

  local function updateAutocomplete(userInput)
    if not isSpellWidget() then
      if hint:IsShown() then
        hint:SetText("")
      end
      hideAutocomplete()
      return
    end
    if not ns.SpellCatalog or not ns.SpellCatalog.Search then
      hideAutocomplete()
      return
    end
    if not control:HasFocus() and userInput ~= true then
      hideAutocomplete()
      return
    end
    local query = extractQuery(control:GetText())
    query = tostring(query or ""):gsub("^%s+", ""):gsub("%s+$", "")
    local numeric = tonumber(query) ~= nil
    if query == "" or ((not numeric) and #query < 2) then
      hideAutocomplete()
      return
    end
    local rows = ns.SpellCatalog:Search(query, 8)
    showAutocomplete(rows)
  end

  local function updateHintAndMaybeNormalize(apply)
    if not isSpellWidget() then
      if hint:IsShown() then
        hint:SetText("")
      end
      hideAutocomplete()
      return
    end
    local raw = tostring(control:GetText() or "")
    if field.widget == "spellid" then
      local normalized, preview, ok = SpellInput:ResolveSpellIDInput(raw)
      if hint:IsShown() then
        hint:SetText(preview or "")
      end
      if apply and ok then
        control:SetText(normalized)
        onChange(field.key, normalized)
      end
    else
      local normalized, preview, ok = SpellInput:ResolveSpellCSVInput(raw)
      if hint:IsShown() then
        hint:SetText(preview or "")
      end
      if apply and ok then
        control:SetText(normalized)
        onChange(field.key, normalized)
      end
    end
  end

  control:HookScript("OnTextChanged", function(_, userInput)
    updateHintAndMaybeNormalize(false)
    autocompleteRevision = autocompleteRevision + 1
    local revision = autocompleteRevision
    C_Timer.After(0.06, function()
      if revision ~= autocompleteRevision then
        return
      end
      if not control or not control:IsShown() then
        return
      end
      updateAutocomplete(userInput)
    end)
  end)

  control:HookScript("OnEditFocusGained", function()
    updateAutocomplete(false)
  end)

  control:HookScript("OnEditFocusLost", function()
    updateHintAndMaybeNormalize(true)
    C_Timer.After(0.05, hideAutocomplete)
  end)

  control:HookScript("OnEnterPressed", function(selfBox)
    updateHintAndMaybeNormalize(true)
    hideAutocomplete()
    selfBox:ClearFocus()
  end)

  control:HookScript("OnEscapePressed", function(selfBox)
    hideAutocomplete()
    selfBox:ClearFocus()
  end)

  updateHintAndMaybeNormalize(false)
end

F.AttachSpellResolver = attachSpellResolver

function F:CreateField(parent, field, model, onChange)
  local multiline = field.widget == "multiline"
  local holder = createFieldShell(parent, field, multiline)
  local label = holder.label

  local control = nil

  if field.widget == "dropdown" then
    control = createDropdown(holder, field, model)
    local options = field.options
    if type(field.optionsProvider) == "function" then
      options = field.optionsProvider(model)
    end
    control:SetOptions(options or {})
    control:SetValue(model[field.key])
    control:SetOnValueChanged(function(value)
      onChange(field.key, value)
    end)
  elseif field.widget == "groupselect" then
    control = createGroupSelect(holder, field, model, onChange)
  elseif field.widget == "checkbox" then
    holder:SetHeight(34)
    control = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    control:SetPoint("TOPLEFT", 8, -8)
    control:SetChecked(model[field.key] == true)
    if Skin and Skin.ApplyCheckbox then
      Skin:ApplyCheckbox(control)
    end

    local cbLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    cbLabel:SetPoint("LEFT", control, "RIGHT", 4, 0)
    cbLabel:SetPoint("RIGHT", -10, 0)
    cbLabel:SetJustifyH("LEFT")
    cbLabel:SetText(field.label or field.key or "Enabled")
    label:SetText(" ")

    control:SetScript("OnClick", function(btn)
      if Skin and Skin.RefreshCheckbox then
        Skin:RefreshCheckbox(btn)
      end
      onChange(field.key, btn:GetChecked() == true)
    end)
  elseif field.widget == "spinner" then
    holder:SetHeight(40)
    control = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    control:SetAutoFocus(false)
    control:SetPoint("TOPRIGHT", holder.anchor, "TOPRIGHT", -26, -1)
    control:SetSize(64, 22)
    control:SetNumeric(true)
    control:SetNumber(tonumber(model[field.key]) or tonumber(field.default) or 0)
    if Skin and Skin.ApplyEditBox then
      Skin:ApplyEditBox(control)
    end

    local function clampValue(value)
      value = tonumber(value) or tonumber(field.default) or 0
      if field.min ~= nil and value < field.min then
        value = field.min
      end
      if field.max ~= nil and value > field.max then
        value = field.max
      end
      return math.floor(value + 0.5)
    end

    local function commit(value)
      value = clampValue(value)
      control:SetNumber(value)
      onChange(field.key, value)
    end

    local minus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    minus:SetSize(18, 18)
    minus:SetPoint("RIGHT", control, "LEFT", -4, 0)
    minus:SetText("-")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(minus, "ghost")
    end
    minus:SetScript("OnClick", function()
      commit((tonumber(control:GetNumber()) or 0) - (tonumber(field.step) or 1))
    end)

    local plus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    plus:SetSize(18, 18)
    plus:SetPoint("LEFT", control, "RIGHT", 4, 0)
    plus:SetText("+")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(plus, "ghost")
    end
    plus:SetScript("OnClick", function()
      commit((tonumber(control:GetNumber()) or 0) + (tonumber(field.step) or 1))
    end)

    control:SetScript("OnEnterPressed", function(edit)
      commit(edit:GetNumber())
      edit:ClearFocus()
    end)
    control:SetScript("OnEditFocusLost", function(edit)
      commit(edit:GetNumber())
    end)
  elseif field.widget == "color" then
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetPoint("TOPRIGHT", holder.anchor, "TOPRIGHT", 0, 0)
    frame:SetSize(math.max(220, tonumber(field.width) or 220), 24)
    control = frame

    local swatch = CreateFrame("Button", nil, frame, "BackdropTemplate")
    swatch:SetSize(28, 22)
    swatch:SetPoint("LEFT", 0, 0)
    swatch:SetBackdrop({
      bgFile = "Interface/Tooltips/UI-Tooltip-Background",
      edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
      edgeSize = 10,
      insets = { left = 2, right = 2, top = 2, bottom = 2 },
    })
    swatch:SetBackdropBorderColor(0.12, 0.50, 0.80, 0.90)
    swatch:SetBackdropColor(0.16, 0.64, 1.0, 0.95)

    local valueText = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    valueText:SetPoint("LEFT", swatch, "RIGHT", 8, 0)
    valueText:SetText(tostring(model[field.key] or field.default or ""))

    local function setColorText(text)
      local r, g, b = parseColorCSV(text)
      if r and g and b then
        swatch:SetBackdropColor(r, g, b, 0.95)
        valueText:SetText(formatColorCSV(r, g, b))
      else
        swatch:SetBackdropColor(0.16, 0.64, 1.0, 0.95)
        valueText:SetText("Default")
      end
    end

    setColorText(model[field.key] or field.default or "")

    swatch:SetScript("OnClick", function()
      if not ColorPickerFrame then
        return
      end
      local r, g, b = parseColorCSV(model[field.key] or field.default or "")
      local startR, startG, startB = r or 0.16, g or 0.64, b or 1.0

      local function commitColor(nr, ng, nb)
        local text = formatColorCSV(nr, ng, nb)
        model[field.key] = text
        setColorText(text)
        onChange(field.key, text)
      end

      if ColorPickerFrame.SetupColorPickerAndShow then
        local info = {
          r = startR,
          g = startG,
          b = startB,
          opacity = 0,
          hasOpacity = false,
          swatchFunc = function()
            local nr, ng, nb
            if ColorPickerFrame.GetColorRGB then
              nr, ng, nb = ColorPickerFrame:GetColorRGB()
            end
            if not nr and ColorPickerFrame.Content and ColorPickerFrame.Content.ColorPicker and ColorPickerFrame.Content.ColorPicker.GetColorRGB then
              nr, ng, nb = ColorPickerFrame.Content.ColorPicker:GetColorRGB()
            end
            commitColor(nr or startR, ng or startG, nb or startB)
          end,
          cancelFunc = function(previousValues)
            if previousValues then
              commitColor(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
            else
              commitColor(startR, startG, startB)
            end
          end,
        }
        ColorPickerFrame:SetupColorPickerAndShow(info)
      else
        ColorPickerFrame.hasOpacity = false
        ColorPickerFrame.func = function()
          local nr, ng, nb = ColorPickerFrame:GetColorRGB()
          commitColor(nr or startR, ng or startG, nb or startB)
        end
        ColorPickerFrame.cancelFunc = function(previousValues)
          if previousValues then
            commitColor(previousValues.r or startR, previousValues.g or startG, previousValues.b or startB)
          else
            commitColor(startR, startG, startB)
          end
        end
        if ColorPickerFrame.SetColorRGB then
          ColorPickerFrame:SetColorRGB(startR, startG, startB)
        end
        ColorPickerFrame.previousValues = { r = startR, g = startG, b = startB }
        ColorPickerFrame:Show()
      end
    end)
  elseif field.widget == "bartexture" then
    control = createStatusbarPicker(holder, field, model, onChange)
  elseif field.widget == "soundpicker" then
    control = createSoundPicker(holder, field, model, onChange)
  else
    local box
    if multiline then
      box = CreateFrame("EditBox", nil, holder)
      box:SetMultiLine(true)
      box:SetFontObject(ChatFontNormal)
      box:SetTextInsets(6, 6, 6, 6)
      box:SetJustifyH("LEFT")
      box:SetJustifyV("TOP")
    else
      box = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    end
    control = box
    control:SetAutoFocus(false)
    control:SetPoint("TOPLEFT", holder.anchor, "TOPLEFT", 0, 0)
    if multiline then
      control:SetSize((field.width or 520), 66)
    else
      control:SetSize(holder.anchor:GetWidth() > 0 and holder.anchor:GetWidth() or (field.width or 320), 24)
    end
    control:SetText(tostring(model[field.key] or ""))
    if Skin and Skin.ApplyEditBox then
      Skin:ApplyEditBox(control)
    end
    control:SetScript("OnTextChanged", function(edit)
      local value = edit:GetText() or ""
      if field.widget == "number" then
        value = tonumber(value) or 0
      end
      onChange(field.key, value)
    end)

    local bgHolder = CreateFrame("Frame", nil, holder)
    bgHolder:SetPoint("TOPLEFT", control, -3, 3)
    bgHolder:SetPoint("BOTTOMRIGHT", control, 3, -3)
    bgHolder:SetFrameLevel(holder:GetFrameLevel())
    if not (Skin and Skin.ApplyEditBox) then
      createInputBackground(bgHolder)
    end
    control:SetFrameLevel(bgHolder:GetFrameLevel() + 1)

    if multiline then
      local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
      scroll:SetPoint("TOPLEFT", control, "TOPLEFT", -4, 4)
      scroll:SetPoint("BOTTOMRIGHT", control, "BOTTOMRIGHT", 24, -4)
      scroll:SetScrollChild(control)
      holder.scroll = scroll
    else
      attachSpellResolver(holder, control, field, onChange)
    end
  end

  holder.label = label
  holder.control = control
  holder.key = field.key
  holder.field = field
  return holder
end

