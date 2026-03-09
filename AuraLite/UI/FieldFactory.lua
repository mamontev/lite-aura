local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.FieldFactory = UI.FieldFactory or {}
local F = UI.FieldFactory

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
    end
  end

  holder.label = label
  holder.control = control
  holder.key = field.key
  return holder
end
