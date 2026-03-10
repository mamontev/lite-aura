local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.Bootstrap = UI.Bootstrap or {}
local B = UI.Bootstrap

B._slashRegistered = B._slashRegistered or false
B._legacyHookInstalled = B._legacyHookInstalled or false

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

function B:InstallLegacySlashHook()
  if self._legacyHookInstalled then
    return
  end
  if not ns.ConfigUI or type(ns.ConfigUI.HandleSlash) ~= "function" then
    return
  end

  local original = ns.ConfigUI.HandleSlash
  ns.ConfigUI.HandleSlash = function(selfRef, msg)
    local normalized = tostring(msg or ""):lower():gsub("^%s+", ""):gsub("%s+$", "")
    if normalized == "" or normalized == "v2" or normalized == "ui2" or normalized == "newui" or normalized == "config" or normalized == "ui" or normalized == "options" then
      if B:ToggleConfig() then
        return
      end
    end
    return original(selfRef, msg)
  end

  self._legacyHookInstalled = true
end

function B:Initialize()
  ensureDbDefaults()
  self:RegisterSlashCommands()
  self:InstallLegacySlashHook()
end

local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function()
  B:Initialize()
end)
