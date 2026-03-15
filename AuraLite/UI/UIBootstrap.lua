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
  local raw = tostring(msg or ""):gsub("^%s+", ""):gsub("%s+$", "")
  local cmd = raw:lower()

  if cmd == "" or cmd == "v2" or cmd == "ui2" or cmd == "newui" or cmd == "config" or cmd == "ui" or cmd == "options" then
    if self:ToggleConfig() then
      return
    end
  end

  if cmd == "examples warrior" or cmd == "seed warrior" then
    if ns.SettingsData and ns.SettingsData.InstallWarriorExamples then
      local count = tonumber(ns.SettingsData:InstallWarriorExamples()) or 0
      if UI and UI.Events and UI.Events.Emit and UI.Events.Names and UI.Events.Names.FILTER_CHANGED then
        UI.Events:Emit(UI.Events.Names.FILTER_CHANGED, { key = "examples_warrior", value = count })
      end
      if UI and UI.Events and UI.Events.Emit and UI.Events.Names and UI.Events.Names.STATE_CHANGED and UI.State and UI.State.Get then
        UI.Events:Emit(UI.Events.Names.STATE_CHANGED, UI.State:Get())
      end
      print(string.format("AuraLite: installed/updated %d warrior example aura(s).", count))
      self:OpenConfig()
      return
    end
  end

  if cmd == "debug" or cmd == "debug on" then
    if ns.Debug and ns.Debug.SetEnabled then
      ns.Debug:SetEnabled(true)
      print("AuraLite: debug logging enabled.")
      return
    end
  end

  if cmd == "debug off" then
    if ns.Debug and ns.Debug.SetEnabled then
      ns.Debug:SetEnabled(false)
      print("AuraLite: debug logging disabled.")
      return
    end
  end

  if cmd == "debug verbose" then
    if ns.Debug and ns.Debug.SetEnabled and ns.Debug.SetVerbose then
      ns.Debug:SetEnabled(true)
      ns.Debug:SetVerbose(true)
      print("AuraLite: verbose debug logging enabled.")
      return
    end
  end

  if cmd == "debug quiet" then
    if ns.Debug and ns.Debug.SetVerbose then
      ns.Debug:SetVerbose(false)
      print("AuraLite: verbose debug logging disabled.")
      return
    end
  end

  if cmd == "debug saved on" then
    if ns.Debug and ns.Debug.SetSavedOutput then
      ns.Debug:SetSavedOutput(true)
      print("AuraLite: saved debug log enabled.")
      return
    end
  end

  if cmd == "debug saved off" then
    if ns.Debug and ns.Debug.SetSavedOutput then
      ns.Debug:SetSavedOutput(false)
      print("AuraLite: saved debug log disabled.")
      return
    end
  end

  if cmd == "debug chat on" then
    if ns.Debug and ns.Debug.SetChatOutput then
      ns.Debug:SetChatOutput(true)
      print("AuraLite: chat debug output enabled.")
      return
    end
  end

  if cmd == "debug chat off" then
    if ns.Debug and ns.Debug.SetChatOutput then
      ns.Debug:SetChatOutput(false)
      print("AuraLite: chat debug output disabled.")
      return
    end
  end

  if cmd == "debug clear" then
    if ns.Debug and ns.Debug.ClearSavedLog then
      local count = tonumber(ns.Debug:ClearSavedLog()) or 0
      print(string.format("AuraLite: cleared %d saved debug lines.", count))
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
