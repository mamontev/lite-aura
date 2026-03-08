local _, ns = ...

ns.UIComponents = ns.UIComponents or {}
local C = ns.UIComponents

local function titleCase(text)
  text = tostring(text or "")
  return text:gsub("^%l", string.upper)
end

function C:CreateSection(parent, title, width, height)
  local frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  frame:SetSize(width, height)
  frame:SetBackdrop({
    bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
  })
  frame:SetBackdropColor(0, 0, 0, 0.55)
  frame:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.85)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  frame.title:SetPoint("TOPLEFT", 10, -8)
  frame.title:SetText(titleCase(title))
  if ns.UISkin then
    ns.UISkin:ApplySection(frame)
  end
  return frame
end

function C:CreateLabel(parent, text, template)
  local label = parent:CreateFontString(nil, "OVERLAY", template or "GameFontHighlight")
  label:SetText(text or "")
  return label
end

function C:CreateButton(parent, text, width, height, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(width or 120, height or 22)
  btn:SetText(text or "Button")
  if onClick then
    btn:SetScript("OnClick", onClick)
  end
  if ns.UISkin then
    ns.UISkin:ApplyButton(btn)
  end
  return btn
end

function C:CreateCheckBox(parent, labelText, onChanged)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  local name = cb:GetName()
  if name and _G[name .. "Text"] then
    cb.text = _G[name .. "Text"]
  else
    cb.text = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  end
  cb.text:SetText(labelText or "")
  cb.text:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  if onChanged then
    cb:SetScript("OnClick", function(self)
      onChanged(self:GetChecked() == true)
    end)
  end
  return cb
end

function C:CreateEditBox(parent, width, height, multiline)
  local edit = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  edit:SetAutoFocus(false)
  edit:SetSize(width or 160, height or 20)
  edit:SetMultiLine(multiline == true)
  edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  edit:SetScript("OnEnterPressed", function(self)
    self:ClearFocus()
  end)
  if ns.UISkin then
    ns.UISkin:ApplyEditBox(edit)
  end
  return edit
end

function C:CreateScrollEdit(parent, width, height)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width, height)

  local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 0, 0)
  scroll:SetPoint("BOTTOMRIGHT", -26, 0)

  local edit = self:CreateEditBox(scroll, width - 34, height, true)
  edit:SetPoint("TOPLEFT", 0, 0)
  edit:SetFontObject(ChatFontNormal)
  edit:SetJustifyH("LEFT")
  edit:SetScript("OnTextChanged", function(self)
    local textHeight = self:GetStringHeight() + 20
    if textHeight < height then
      textHeight = height
    end
    self:SetHeight(textHeight)
    scroll:UpdateScrollChildRect()
  end)

  scroll:SetScrollChild(edit)
  holder.scroll = scroll
  holder.edit = edit
  return holder
end

function C:CreateDropdown(parent, width)
  local drop = CreateFrame("Frame", nil, parent, "UIDropDownMenuTemplate")
  UIDropDownMenu_SetWidth(drop, width or 150)
  UIDropDownMenu_JustifyText(drop, "LEFT")
  drop.options = {}
  drop.value = nil
  drop._onValueChanged = nil

  UIDropDownMenu_Initialize(drop, function(frame, level)
    for i = 1, #(frame.options or {}) do
      local opt = frame.options[i]
      local info = UIDropDownMenu_CreateInfo()
      info.text = opt.label
      info.arg1 = opt.value
      info.checked = (frame.value == opt.value)
      info.func = function(_, value)
        frame:SetValue(value, true)
      end
      UIDropDownMenu_AddButton(info, level)
    end
  end)

  function drop:SetOptions(options)
    self.options = options or {}
    UIDropDownMenu_Initialize(self, function(frame, level)
      for i = 1, #(frame.options or {}) do
        local opt = frame.options[i]
        local info = UIDropDownMenu_CreateInfo()
        info.text = opt.label
        info.arg1 = opt.value
        info.checked = (frame.value == opt.value)
        info.func = function(_, value)
          frame:SetValue(value, true)
        end
        UIDropDownMenu_AddButton(info, level)
      end
    end)
  end

  function drop:SetOnValueChanged(fn)
    self._onValueChanged = fn
  end

  function drop:GetValue()
    return self.value
  end

  function drop:SetValue(value, emitEvent)
    self.value = value
    local label = tostring(value or "")
    for i = 1, #(self.options or {}) do
      local opt = self.options[i]
      if opt.value == value then
        label = opt.label
        break
      end
    end
    UIDropDownMenu_SetText(self, label)
    if emitEvent and self._onValueChanged then
      self._onValueChanged(value)
    end
  end

  if ns.UISkin then
    ns.UISkin:ApplyDropdown(drop)
  end

  return drop
end

function C:CreateSegmentedControl(parent, width, height, options, onChanged)
  local holder = CreateFrame("Frame", nil, parent)
  holder:SetSize(width or 300, height or 22)
  holder.buttons = {}
  holder.options = options or {}
  holder.value = nil
  holder.onChanged = onChanged

  local function updateVisualState()
    for i = 1, #holder.buttons do
      local btn = holder.buttons[i]
      local selected = btn and btn._alValue == holder.value
      if btn and btn.Disable and btn.Enable then
        if selected then
          btn:Disable()
        else
          btn:Enable()
        end
      end
    end
  end

  function holder:SetOptions(newOptions)
    self.options = newOptions or {}
    local count = #self.options
    if count <= 0 then
      return
    end

    local spacing = 4
    local btnWidth = math.floor((self:GetWidth() - ((count - 1) * spacing)) / count)
    for i = 1, count do
      local opt = self.options[i]
      local btn = self.buttons[i]
      if not btn then
        btn = C:CreateButton(self, opt.label or tostring(opt.value), btnWidth, self:GetHeight(), function(selfBtn)
          self:SetValue(selfBtn._alValue, true)
        end)
        self.buttons[i] = btn
      end

      btn:SetSize(btnWidth, self:GetHeight())
      btn:ClearAllPoints()
      if i == 1 then
        btn:SetPoint("LEFT", self, "LEFT", 0, 0)
      else
        btn:SetPoint("LEFT", self.buttons[i - 1], "RIGHT", spacing, 0)
      end
      btn:SetText(opt.label or tostring(opt.value))
      btn._alValue = opt.value
      btn:Show()
    end

    for i = count + 1, #self.buttons do
      self.buttons[i]:Hide()
    end

    if self.value == nil and self.options[1] then
      self.value = self.options[1].value
    end
    updateVisualState()
  end

  function holder:SetOnValueChanged(fn)
    self.onChanged = fn
  end

  function holder:SetValue(value, emitEvent)
    self.value = value
    updateVisualState()
    if emitEvent and self.onChanged then
      self.onChanged(value)
    end
  end

  function holder:GetValue()
    return self.value
  end

  holder:SetOptions(options or {})
  if holder.value == nil and holder.options[1] then
    holder:SetValue(holder.options[1].value, false)
  else
    updateVisualState()
  end

  return holder
end
