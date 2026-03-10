local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.FieldFactory = UI.FieldFactory or {}
local F = UI.FieldFactory

local SpellInput = UI.SpellInput

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

  return drop
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
    updateAutocomplete(userInput)
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

    local cbLabel = holder:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    cbLabel:SetPoint("LEFT", control, "RIGHT", 4, 0)
    cbLabel:SetText(field.label or field.key or "Enabled")
    label:SetText(" ")

    control:SetScript("OnClick", function(btn)
      onChange(field.key, btn:GetChecked() == true)
    end)
  else
    local box = CreateFrame("EditBox", nil, holder, multiline and "InputBoxMultiLineTemplate" or "InputBoxTemplate")
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

    if not multiline then
      local bgHolder = CreateFrame("Frame", nil, holder)
      bgHolder:SetPoint("TOPLEFT", control, -3, 3)
      bgHolder:SetPoint("BOTTOMRIGHT", control, 3, -3)
      bgHolder:SetFrameLevel(holder:GetFrameLevel())
      createInputBackground(bgHolder)
      control:SetFrameLevel(bgHolder:GetFrameLevel() + 1)

      attachSpellResolver(holder, control, field, onChange)
    end
  end

  holder.label = label
  holder.control = control
  holder.key = field.key
  return holder
end

