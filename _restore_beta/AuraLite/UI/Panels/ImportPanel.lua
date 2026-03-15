local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local Skin = ns.UISkin

local ImportPanel = {}
ImportPanel.__index = ImportPanel

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.02, 0.06, 0.14, 0.96)
  frame:SetBackdropBorderColor(0.12, 0.5, 0.8, 0.95)
end

local function makeButton(parent, text, w, variant, onClick)
  local btn = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  btn:SetSize(w or 210, 22)
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

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetSize(240, 104)
  o.frame:SetFrameStrata("DIALOG")
  o.frame:SetToplevel(true)
  createBackdrop(o.frame)
  o.frame:Hide()

  local title = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOPLEFT", 10, -8)
  title:SetText("Import")

  local subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  subtitle:SetPoint("TOPLEFT", 10, -26)
  subtitle:SetPoint("RIGHT", -10, 0)
  subtitle:SetJustifyH("LEFT")
  subtitle:SetText("Import any AuraLite share string. The addon will detect aura or group automatically.")

  o.btnImport = makeButton(o.frame, "Import String", 210, "primary", function()
    o:OpenImport()
    o.frame:Hide()
  end)
  o.btnImport:SetPoint("TOPLEFT", 14, -58)

  if E then
    E:On(E.Names.OPEN_IMPORT_PANEL, function(payload)
      local anchor = payload and payload.anchor
      if anchor then
        o.frame:ClearAllPoints()
        o.frame:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -6)
      end
      o.frame:SetShown(not o.frame:IsShown())
    end)
  end

  return o
end

Panels.ImportPanel = ImportPanel
UI.ImportPanel = ImportPanel
