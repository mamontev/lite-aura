local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.FieldFactory = UI.FieldFactory or {}
local F = UI.FieldFactory

local SpellInput = UI.SpellInput
local Skin = ns.UISkin

local function createInputBackground(parent)
  local bg = parent:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.03, 0.09, 0.16, 0.65)
  return bg
end

local function createDropdown(parent, width)
  local drop = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(drop, width or 260)
  UIDropDownMenu_JustifyText(drop, "LEFT")
  drop.options = {}
  drop.value = nil
  drop.onChanged = nil

  local function findLabel(value)
    for i = 1, #(drop.options or {}) do
      local row = drop.options[i]
      if tostring(row.value) == tostring(value) then
        return row.label
      end
    end
    return "Choose..."
  end

  local function init(_, level)
    if level ~= 1 then
      return
    end
    for i = 1, #(drop.options or {}) do
      local opt = drop.options[i]
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.checked = tostring(drop.value) == tostring(opt.value)
      info.func = function()
        drop:SetValue(opt.value, true)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end

  UIDropDownMenu_Initialize(drop, init)

  function drop:SetOptions(options)
    self.options = options or {}
    UIDropDownMenu_Initialize(self, init)
  end

  function drop:SetValue(value, emit)
    self.value = value
    UIDropDownMenu_SetText(self, findLabel(value))
    if emit and self.onChanged then
      self.onChanged(value)
    end
  end

  function drop:GetValue()
    return self.value
  end

  function drop:SetOnValueChanged(fn)
    self.onChanged = fn
  end

  if Skin and Skin.ApplyDropdown then
    Skin:ApplyDropdown(drop)
  end

  return drop
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
      hint:SetText("")
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
      hint:SetText("")
      hideAutocomplete()
      return
    end
    local raw = tostring(control:GetText() or "")
    if field.widget == "spellid" then
      local normalized, preview, ok = SpellInput:ResolveSpellIDInput(raw)
      hint:SetText(preview or "")
      if apply and ok then
        control:SetText(normalized)
        onChange(field.key, normalized)
      end
    else
      local normalized, preview, ok = SpellInput:ResolveSpellCSVInput(raw)
      hint:SetText(preview or "")
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
  local holder = CreateFrame("Frame", nil, parent)
  local multiline = field.widget == "multiline"
  holder:SetHeight(multiline and 92 or 52)

  local label = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("TOPLEFT", 0, 0)
  label:SetText(field.label or field.key or "Field")

  local control = nil

  if field.widget == "dropdown" then
    control = createDropdown(holder, field.width or 300)
    control:SetPoint("TOPLEFT", -16, -16)
    local options = field.options
    if type(field.optionsProvider) == "function" then
      options = field.optionsProvider(model)
    end
    control:SetOptions(options or {})
    control:SetValue(model[field.key])
    control:SetOnValueChanged(function(value)
      onChange(field.key, value)
    end)
  elseif field.widget == "checkbox" then
    control = CreateFrame("CheckButton", nil, holder, "UICheckButtonTemplate")
    control:SetPoint("TOPLEFT", 0, -18)
    control:SetChecked(model[field.key] == true)
    if Skin and Skin.ApplyCheckbox then
      Skin:ApplyCheckbox(control)
    end

    local cbLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbLabel:SetPoint("LEFT", control, "RIGHT", 4, 0)
    cbLabel:SetText(field.label or field.key or "Enabled")
    label:SetText(" ")

    control:SetScript("OnClick", function(btn)
      if Skin and Skin.RefreshCheckbox then
        Skin:RefreshCheckbox(btn)
      end
      onChange(field.key, btn:GetChecked() == true)
    end)
  elseif field.widget == "spinner" then
    holder:SetHeight(52)
    control = CreateFrame("EditBox", nil, holder, "InputBoxTemplate")
    control:SetAutoFocus(false)
    control:SetPoint("TOPLEFT", 26, -18)
    control:SetSize(72, 24)
    control:SetNumeric(true)
    control:SetNumber(tonumber(model[field.key]) or tonumber(field.default) or 0)

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
    minus:SetSize(22, 22)
    minus:SetPoint("LEFT", control, "LEFT", -24, 0)
    minus:SetText("-")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(minus, "ghost")
    end
    minus:SetScript("OnClick", function()
      commit((tonumber(control:GetNumber()) or 0) - (tonumber(field.step) or 1))
    end)

    local plus = CreateFrame("Button", nil, holder, "UIPanelButtonTemplate")
    plus:SetSize(22, 22)
    plus:SetPoint("LEFT", control, "RIGHT", 4, 0)
    plus:SetText("+")
    if Skin and Skin.ApplyButton then
      Skin:SetButtonVariant(plus, "ghost")
    end
    plus:SetScript("OnClick", function()
      commit((tonumber(control:GetNumber()) or 0) + (tonumber(field.step) or 1))
    end)

    local hint = holder:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    hint:SetPoint("LEFT", plus, "RIGHT", 8, 0)
    hint:SetText(field.help or "")

    control:SetScript("OnEnterPressed", function(edit)
      commit(edit:GetNumber())
      edit:ClearFocus()
    end)
    control:SetScript("OnEditFocusLost", function(edit)
      commit(edit:GetNumber())
    end)
  elseif field.widget == "color" then
    local frame = CreateFrame("Frame", nil, holder)
    frame:SetPoint("TOPLEFT", 0, -18)
    frame:SetSize(220, 24)
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
    control:SetPoint("TOPLEFT", 0, -18)
    if multiline then
      control:SetSize(field.width or 520, 66)
    else
      control:SetSize(field.width or 320, 24)
    end
    control:SetText(tostring(model[field.key] or ""))
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
    createInputBackground(bgHolder)
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
  return holder
end

