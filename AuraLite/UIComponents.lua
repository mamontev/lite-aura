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

local function findLabelByValue(options, value)
  for i = 1, #(options or {}) do
    local opt = options[i]
    if opt.value ~= nil and tostring(opt.value) == tostring(value) then
      return tostring(opt.label or value or "")
    end
    if type(opt.menuList) == "table" then
      local nested = findLabelByValue(opt.menuList, value)
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

function C:CreateDropdown(parent, width)
  local picker = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  picker:SetSize(width or 180, 28)
  picker.options = {}
  picker.value = nil
  picker._onValueChanged = nil

  picker:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  picker:SetBackdropColor(0.04, 0.08, 0.14, 0.88)
  picker:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.88)

  picker.text = picker:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  picker.text:SetPoint("LEFT", 8, 0)
  picker.text:SetPoint("RIGHT", -30, 0)
  picker.text:SetJustifyH("LEFT")
  picker.text:SetWordWrap(false)

  picker.trigger = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
  picker.trigger:SetSize(24, 22)
  picker.trigger:SetPoint("RIGHT", -3, 0)
  picker.trigger:SetText("v")
  if ns.UISkin and ns.UISkin.SetButtonVariant then
    ns.UISkin:SetButtonVariant(picker.trigger, "ghost")
  end

  picker.popup = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  picker.popup:SetFrameStrata("TOOLTIP")
  picker.popup:SetClampedToScreen(true)
  picker.popup:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 10,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  picker.popup:SetBackdropColor(0.02, 0.05, 0.11, 0.97)
  picker.popup:SetBackdropBorderColor(0.14, 0.42, 0.70, 0.92)
  picker.popup:SetSize((width or 180) + 24, 228)
  picker.popup:Hide()

  picker.popupHeader = picker.popup:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  picker.popupHeader:SetPoint("TOPLEFT", 10, -10)
  picker.popupHeader:SetText("Choose Option")

  local scroll = CreateFrame("ScrollFrame", nil, picker.popup, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 8, -28)
  scroll:SetPoint("BOTTOMRIGHT", -28, 8)

  local content = CreateFrame("Frame", nil, scroll)
  content:SetSize(width or 180, 1)
  scroll:SetScrollChild(content)
  picker.popupContent = content
  picker.popupRows = {}

  local function closePopup()
    picker.popup:Hide()
  end

  local function updateLabel()
    local label = findLabelByValue(picker.options, picker.value)
    picker.text:SetText(label or tostring(picker.value or "Choose..."))
  end

  function picker:SetOptions(options)
    self.options = options or {}
    local flat = flattenMenuOptions(self.options)
    local rowHeight = 24
    for i = 1, #flat do
      local row = self.popupRows[i]
      if not row then
        row = CreateFrame("Button", nil, self.popupContent)
        if ns.UISkin and ns.UISkin.ApplyClickableRow then
          ns.UISkin:ApplyClickableRow(row, "row")
        end
        if ns.UISkin and ns.UISkin.SetClickableRowState then
          row:SetScript("OnEnter", function(selfRow)
            ns.UISkin:SetClickableRowState(selfRow, "hover")
          end)
          row:SetScript("OnLeave", function(selfRow)
            ns.UISkin:SetClickableRowState(selfRow, "normal")
          end)
        end
        row.text = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row.text:SetPoint("LEFT", 8, 0)
        row.text:SetPoint("RIGHT", -12, 0)
        row.text:SetJustifyH("LEFT")
        self.popupRows[i] = row
      end
      row:ClearAllPoints()
      row:SetPoint("TOPLEFT", 0, -((i - 1) * rowHeight))
      row:SetSize((width or 180) - 8, rowHeight)
      row.value = flat[i].value
      row.text:SetText(flat[i].label or tostring(flat[i].value or ""))
      row:SetScript("OnClick", function(selfRow)
        picker:SetValue(selfRow.value, true)
        closePopup()
      end)
      row:Show()
    end
    for i = #flat + 1, #self.popupRows do
      self.popupRows[i]:Hide()
    end
    self.popupContent:SetHeight(math.max(1, #flat * rowHeight))
    updateLabel()
  end

  function picker:SetOnValueChanged(fn)
    self._onValueChanged = fn
  end

  function picker:GetValue()
    return self.value
  end

  function picker:SetValue(value, emitEvent)
    self.value = value
    updateLabel()
    if emitEvent and self._onValueChanged then
      self._onValueChanged(value)
    end
  end

  picker.trigger:SetScript("OnClick", function()
    if picker.popup:IsShown() then
      closePopup()
      return
    end
    picker.popup:ClearAllPoints()
    picker.popup:SetPoint("TOPLEFT", picker, "BOTTOMLEFT", -2, -4)
    picker.popup:Show()
  end)

  picker:SetScript("OnHide", closePopup)
  return picker
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
