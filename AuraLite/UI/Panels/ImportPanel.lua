local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin
local Widgets = UI.Widgets or {}

local ImportPanel = {}
ImportPanel.__index = ImportPanel

local function createBackdrop(frame)
  if Skin and Skin.ApplyWindow then
    Skin:ApplyWindow(frame)
    return
  end
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.06, 0.14, 0.96)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.95)
end

local function applyFloatingWindowChrome(frame)
  frame:SetFrameStrata("FULLSCREEN_DIALOG")
  frame:SetToplevel(true)
  frame:SetClampedToScreen(true)
  frame:SetMovable(true)
  frame:EnableMouse(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", function(self)
    self:Raise()
    self:StartMoving()
  end)
  frame:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
  end)
end

local function attachDragHandle(frame, handle)
  if not frame or not handle then
    return
  end
  local dragHandle = handle
  if type(dragHandle) == "table" and dragHandle.frame and dragHandle.frame.GetObjectType then
    dragHandle = dragHandle.frame
  end
  if not (dragHandle and dragHandle.EnableMouse and dragHandle.RegisterForDrag and dragHandle.SetScript) then
    local proxy = CreateFrame("Frame", nil, frame)
    proxy:SetPoint("TOPLEFT", handle, "TOPLEFT", 0, 0)
    proxy:SetPoint("BOTTOMRIGHT", handle, "BOTTOMRIGHT", 0, 0)
    dragHandle = proxy
  end
  dragHandle:EnableMouse(true)
  dragHandle:RegisterForDrag("LeftButton")
  dragHandle:SetScript("OnDragStart", function()
    frame:Raise()
    frame:StartMoving()
  end)
  dragHandle:SetScript("OnDragStop", function()
    frame:StopMovingOrSizing()
  end)
end

local function makeButton(parent, text, w, variant, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w or 210, 18)
  btn:SetText(text)
  if Skin and Skin.ApplyButton then
    Skin:SetButtonVariant(btn, variant or "default")
  end
  btn:SetScript("OnClick", function()
    if onClick then
      onClick()
    end
  end)
  return btn
end

function ImportPanel:OpenImport()
  if UI and UI.ImportExportDialog and UI.ImportExportDialog.ShowImport and ns.ImportExport and ns.ImportExport.ImportString then
    UI.ImportExportDialog:ShowImport(
      "Import",
      "Paste any AuraLite share string here. AuraLite will automatically recognize whether it contains a single aura or a whole group.",
      function(raw)
        local result, err = ns.ImportExport:ImportString(raw, { forceStandalone = true })
        if not result then
          return tostring(err or "Import failed")
        end
        if result.kind == "aura" then
          if UI.State and UI.State.SetSelectedAura then
            UI.State:SetSelectedAura(result.auraKey, "import")
          end
          if E then
            E:Emit(E.Names.FILTER_CHANGED, { key = "import_aura", value = result.auraKey })
          end
          return "Aura imported"
        end
        if result.kind == "group" then
          if E then
            E:Emit(E.Names.FILTER_CHANGED, { key = "import_group", value = result.groupID or true })
          end
          return "Group imported"
        end
        return "Import complete"
      end
    )
  end
end

function ImportPanel:Create(parent)
  local o = setmetatable({}, self)

  o.frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
  o.frame:SetSize(356, 196)
  applyFloatingWindowChrome(o.frame)
  createBackdrop(o.frame)
  o.frame:Hide()

  o.title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  o.title:SetPoint("TOPLEFT", 14, -16)
  o.title:SetText("Import Package")
  o.title:SetTextColor(0.98, 0.88, 0.34)

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 14, -34)
  o.subtitle:SetPoint("RIGHT", -14, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("Bring in a single aura or a full group package without leaving the studio.")
  attachDragHandle(o.frame, o.title)
  attachDragHandle(o.frame, o.subtitle)

  if Widgets.SectionHeaderWidget and Widgets.SectionHeaderWidget.Create then
    o.header = Widgets.SectionHeaderWidget:Create(o.frame, {
      title = "Share String",
      helpTitle = "Import",
      helpBody = "Paste any AuraLite share string. AuraLite will detect whether it contains a single aura or a whole group.",
      compact = true,
      lineWidth = 60,
    })
    o.header:SetPoint("TOPLEFT", 14, -58)
    o.header:SetPoint("TOPRIGHT", -14, -58)
    attachDragHandle(o.frame, o.header)
  end

  local body = CreateFrame("Frame", nil, o.frame, "BackdropTemplate")
  if Skin and Skin.ApplyInsetPanel then
    Skin:ApplyInsetPanel(body)
  end
  body:SetPoint("TOPLEFT", 14, -76)
  body:SetPoint("TOPRIGHT", -14, -76)
  body:SetPoint("BOTTOMLEFT", 14, 48)
  body:SetPoint("BOTTOMRIGHT", -14, 48)

  local subtitle = body:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", 12, -10)
  subtitle:SetPoint("RIGHT", -12, 0)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Paste any AuraLite share string. The addon will detect aura or group automatically and route it into the repository.")

  o.btnImport = makeButton(body, "Import String", 224, "primary", function()
    o:OpenImport()
    o.frame:Hide()
  end)
  o.btnImport:SetSize(296, 24)
  o.btnImport:SetPoint("TOPLEFT", 12, -48)

  o.footer = CreateFrame("Frame", nil, o.frame)
  o.footer:SetPoint("BOTTOMLEFT", 14, 12)
  o.footer:SetPoint("BOTTOMRIGHT", -14, 12)
  o.footer:SetHeight(24)

  o.footerLine = o.footer:CreateTexture(nil, "ARTWORK")
  o.footerLine:SetPoint("TOPLEFT", 0, 0)
  o.footerLine:SetPoint("TOPRIGHT", 0, 0)
  o.footerLine:SetHeight(1)
  o.footerLine:SetColorTexture(1.0, 0.82, 0.18, 0.18)

  o.footerHint = o.footer:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.footerHint:SetPoint("LEFT", 0, -6)
  o.footerHint:SetText("Imports create fresh local IDs so your current repository stays stable.")

  o.btnClose = makeButton(o.footer, "Close", 88, "ghost", function()
    o.frame:Hide()
  end)
  o.btnClose:SetPoint("RIGHT", 0, -6)

  if E then
    E:On(E.Names.OPEN_IMPORT_PANEL, function(payload)
      o.frame:ClearAllPoints()
      o.frame:SetPoint("CENTER", UIParent, "CENTER", 0, 70)
      o.frame:Raise()
      o.frame:SetShown(not o.frame:IsShown())
    end)
  end

  return o
end

Panels.ImportPanel = ImportPanel
UI.ImportPanel = ImportPanel
