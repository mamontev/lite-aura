local _, ns = ...
local U = ns.Utils

ns.SettingsUI = ns.SettingsUI or {}
local UI = ns.SettingsUI

local function parseBarTextureToken(token)
  token = U.Trim(tostring(token or ""))
  if token == "" then
    return "", ""
  end
  if token:lower():find("^lsm:") then
    return token, ""
  end
  return "custom", token
end

function UI:RefreshBarTextureVisibility(mode)
  mode = tostring(mode or (self.ddTimerVisual and self.ddTimerVisual:GetValue()) or "icon"):lower()
  local guided = ns.db and ns.db.options and ns.db.options.uiGuidedMode == true
  local show = (self.activeTab == "display") and (mode == "bar" or mode == "iconbar")
  if self.lblBarTexture then
    self.lblBarTexture:SetShown(show)
  end
  if self.editBarTexture then
    self.editBarTexture:SetShown(show and (not guided))
  end
  if self.barTextureHelp then
    self.barTextureHelp:SetShown(show and (not guided))
  end
  if self.ddBarTexturePreset then
    self.ddBarTexturePreset:SetShown(show)
  end
end

function UI:RefreshBarTextureOptions()
  if not self.ddBarTexturePreset then
    return
  end
  if self.GetBarTextureOptions then
    self.ddBarTexturePreset:SetOptions(self:GetBarTextureOptions())
  end
end

function UI:SyncBarTexturePresetFromPath(path)
  if not self.ddBarTexturePreset then
    return
  end
  local token, custom = parseBarTextureToken(path)
  if token == "custom" then
    self.ddBarTexturePreset:SetValue("custom")
    if self.editBarTexture then
      self.editBarTexture:SetText(custom)
    end
    return
  end
  self.ddBarTexturePreset:SetValue(token)
end
