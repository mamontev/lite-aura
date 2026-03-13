local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.Bootstrap = UI.Bootstrap or {}
local B = UI.Bootstrap

B._slashRegistered = B._slashRegistered or false
local function ensureDbDefaults()
  ns.db = ns.db or {}
  ns.db.settings = ns.db.settings or {}
  ns.db.settings.uiV2 = true
end

function B:IsEnabled()
  ensureDbDefaults()
  return true
end

function B:OpenConfig()
  if UI.ConfigFrame and UI.ConfigFrame.Open then
    UI.ConfigFrame:Open()
    return true
  end
  return false
end

function B:ToggleConfig()
  if UI.ConfigFrame and UI.ConfigFrame.Toggle then
    UI.ConfigFrame:Toggle()
    return true
  end
  return false
end

function B:FallbackCommand(msg)
  if ns.ConfigUI and ns.ConfigUI.HandleSlash then
    ns.ConfigUI:HandleSlash(msg or "")
  end
end

function B:HandleSlash(msg)
  local cmd = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")

  if cmd == "" or cmd == "v2" or cmd == "ui2" or cmd == "newui" or cmd == "config" or cmd == "ui" or cmd == "options" then
    if self:ToggleConfig() then
      return
    end
  end

  self:FallbackCommand(msg)
end

function B:RegisterSlashCommands()
  if self._slashRegistered then
    return
  end
  SLASH_AURALITEV21 = "/al2"
  SLASH_AURALITEV22 = "/auralite2"
  SlashCmdList.AURALITEV2 = function(msg)
    B:HandleSlash(msg)
  end
  self._slashRegistered = true
end

function B:Initialize()
  ensureDbDefaults()
  self:RegisterSlashCommands()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  B:Initialize()
end)
