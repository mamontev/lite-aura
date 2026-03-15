local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2
local Skin = ns.UISkin

UI.ImportExportDialog = UI.ImportExportDialog or {}
local D = UI.ImportExportDialog

local function ensureFrame()
  if D.frame then
    return D.frame
  end

  local frame = CreateFrame("Frame", "AuraLiteImportExportFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(720, 340)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:SetToplevel(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
  frame:Hide()

  if Skin and Skin.ApplyPanel then
    Skin:ApplyPanel(frame)
  end

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOPLEFT", 16, -12)
  frame.title:SetPoint("RIGHT", -16, 0)
  frame.title:SetJustifyH("LEFT")

  frame.hint = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.hint:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -6)
  frame.hint:SetPoint("RIGHT", -16, 0)
  frame.hint:SetJustifyH("LEFT")

  frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
  frame.scroll:SetPoint("TOPLEFT", 16, -58)
  frame.scroll:SetPoint("BOTTOMRIGHT", -34, 48)

  frame.edit = CreateFrame("EditBox", nil, frame.scroll)
  frame.edit:SetMultiLine(true)
  frame.edit:SetAutoFocus(false)
  frame.edit:SetFontObject(ChatFontNormal)
  frame.edit:SetWidth(640)
  frame.edit:SetHeight(240)
  frame.edit:SetTextInsets(8, 8, 8, 8)
  frame.edit:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
  end)
  frame.scroll:SetScrollChild(frame.edit)

  frame.bg = frame:CreateTexture(nil, "BACKGROUND")
  frame.bg:SetPoint("TOPLEFT", frame.scroll, "TOPLEFT", -2, 2)
  frame.bg:SetPoint("BOTTOMRIGHT", frame.scroll, "BOTTOMRIGHT", 2, -2)
  frame.bg:SetColorTexture(0.03, 0.06, 0.12, 0.92)

  frame.confirm = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.confirm:SetSize(120, 24)
  frame.confirm:SetPoint("BOTTOMLEFT", 16, 12)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(frame.confirm, "primary")
  end

  frame.cancel = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  frame.cancel:SetSize(100, 24)
  frame.cancel:SetPoint("LEFT", frame.confirm, "RIGHT", 8, 0)
  frame.cancel:SetText("Close")
  frame.cancel:SetScript("OnClick", function()
    frame:Hide()
  end)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(frame.cancel, "ghost")
  end

  frame.status = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  frame.status:SetPoint("LEFT", frame.cancel, "RIGHT", 12, 0)
  frame.status:SetPoint("RIGHT", -16, 0)
  frame.status:SetJustifyH("LEFT")

  D.frame = frame
  return frame
end

function D:ShowExport(title, text, hint)
  local frame = ensureFrame()
  frame.title:SetText(title or "Export")
  frame.hint:SetText(hint or "Copy this string and share it or save it for later.")
  frame.edit:SetText(text or "")
  frame.edit:HighlightText()
  frame.edit:SetFocus()
  frame.status:SetText("Ready to copy")
  frame.confirm:SetText("Copy Ready")
  frame.confirm:SetScript("OnClick", function()
    frame.edit:HighlightText()
    frame.edit:SetFocus()
    frame.status:SetText("String selected")
  end)
  frame:Show()
end

function D:ShowImport(title, hint, onConfirm)
  local frame = ensureFrame()
  frame.title:SetText(title or "Import")
  frame.hint:SetText(hint or "Paste an AuraLite export string here.")
  frame.edit:SetText("")
  frame.edit:SetFocus()
  frame.status:SetText("")
  frame.confirm:SetText("Import")
  frame.confirm:SetScript("OnClick", function()
    local raw = tostring(frame.edit:GetText() or "")
    local ok, message = pcall(onConfirm, raw)
    if ok and message then
      frame.status:SetText(tostring(message))
    elseif not ok then
      frame.status:SetText("Import failed")
      if geterrorhandler then
        geterrorhandler()(message)
      end
    end
  end)
  frame:Show()
end
