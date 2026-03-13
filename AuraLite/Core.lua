local addonName, ns = ...

ns.name = addonName
ns.frame = ns.frame or CreateFrame("Frame")
ns.state = ns.state or {
  editMode = false,
  restrictionActive = false,
  profileKey = "default",
}

local initialized = false

local function getAddonVersion()
  if C_AddOns and type(C_AddOns.GetAddOnMetadata) == "function" then
    local version = C_AddOns.GetAddOnMetadata(addonName, "Version")
    if type(version) == "string" and version ~= "" then
      return version
    end
  end
  if type(GetAddOnMetadata) == "function" then
    local version = GetAddOnMetadata(addonName, "Version")
    if type(version) == "string" and version ~= "" then
      return version
    end
  end
  return "unknown"
end

local function printStartupBanner()
  local version = getAddonVersion()
  local line1 = "|cffffd200[AuraLite]|r    _____                        .____    .__  __          "
  local line2 = "|cffffd200[AuraLite]|r   /  _  \\  __ ______________    |    |   |__|/  |_  ____  "
  local line3 = "|cffffd200[AuraLite]|r  /  /_\\  \\|  |  \\_  __ \\__  \\   |    |   |  \\   __\\/ __ \\ "
  local line4 = "|cffffd200[AuraLite]|r /    |    \\  |  /|  | \\/ __ \\_ |    |___|  ||  | \\  ___/ "
  local line5 = "|cffffd200[AuraLite]|r \\____|__  /____/ |__|  (____  / |_______ \\__||__|  \\___  >"
  local line6 = string.format("|cffffd200[AuraLite]|r         \\/                  \\/          \\/             \\/  v%s", tostring(version))

  if DEFAULT_CHAT_FRAME and DEFAULT_CHAT_FRAME.AddMessage then
    DEFAULT_CHAT_FRAME:AddMessage(line1)
    DEFAULT_CHAT_FRAME:AddMessage(line2)
    DEFAULT_CHAT_FRAME:AddMessage(line3)
    DEFAULT_CHAT_FRAME:AddMessage(line4)
    DEFAULT_CHAT_FRAME:AddMessage(line5)
    DEFAULT_CHAT_FRAME:AddMessage(line6)
  end

  if ns.Debug and ns.Debug.Log then
    ns.Debug:Log(string.format("Startup banner shown. version=%s", tostring(version)))
  end
end

function ns:RebuildWatchIndex()
  if not self.db then
    return
  end
  self.Registry:Rebuild(self.db)
end

function ns:Initialize()
  if initialized then
    return
  end

  self.ProfileManager:Init()
  if self.SpellCatalog and self.SpellCatalog.BuildStaticIndex then
    self.SpellCatalog:BuildStaticIndex()
  end
  self:RebuildWatchIndex()
  self.GroupManager:EnsureTicker()

  if self.db.locked == nil then
    self.db.locked = true
  end

  self.Dragger:SetLocked(self.db.locked)
  if self.OptionsIntegration and self.OptionsIntegration.Register then
    self.OptionsIntegration:Register()
  end
  printStartupBanner()
  if self.Debug then
    self.Debug:Log("Addon initialized.")
  end
  initialized = true
end

function ns:RegisterRuntimeEvents()
  -- Player spellcast observer events are read-only and help the resolver
  -- correlate cast attempts without relying purely on heuristic cooldown edges.
  self.state.runtimeEventsRegistered = true
  if self.Debug and self.Debug.Log then
    self.Debug:Log("Runtime cast observer events enabled.")
  end
end

function ns:UnregisterRuntimeEvents()
  self.state.runtimeEventsRegistered = false
end

local function dispatchEvent(_, event, ...)
  local fn = ns.EventRouter and ns.EventRouter[event]
  if fn then
    fn(ns.EventRouter, ...)
  end
end

ns.frame:SetScript("OnEvent", dispatchEvent)
ns.frame:RegisterEvent("PLAYER_LOGIN")
ns.frame:RegisterEvent("PLAYER_ENTERING_WORLD")
ns.frame:RegisterEvent("PLAYER_TARGET_CHANGED")
ns.frame:RegisterEvent("PLAYER_FOCUS_CHANGED")
ns.frame:RegisterEvent("UNIT_PET")
ns.frame:RegisterEvent("PLAYER_REGEN_ENABLED")
ns.frame:RegisterEvent("PLAYER_REGEN_DISABLED")
ns.frame:RegisterEvent("PLAYER_SPECIALIZATION_CHANGED")
ns.frame:RegisterEvent("PLAYER_TALENT_UPDATE")
ns.frame:RegisterEvent("TRAIT_CONFIG_UPDATED")
ns.frame:RegisterEvent("ADDON_RESTRICTION_STATE_CHANGED")
ns.frame:RegisterEvent("UNIT_AURA")
ns.frame:RegisterEvent("UNIT_HEALTH")
ns.frame:RegisterEvent("UNIT_POWER_UPDATE")
ns.frame:RegisterEvent("UNIT_MAXPOWER")
ns.frame:RegisterEvent("UNIT_DISPLAYPOWER")
ns.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ns.frame:RegisterEvent("SPELL_UPDATE_CHARGES")
ns.frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
ns.frame:RegisterEvent("SPELL_UPDATE_USABLE")
ns.frame:RegisterEvent("UI_ERROR_MESSAGE")
ns.frame:RegisterEvent("UNIT_SPELLCAST_SUCCEEDED")
ns.frame:RegisterEvent("UNIT_SPELLCAST_FAILED")
ns.frame:RegisterEvent("UNIT_SPELLCAST_FAILED_QUIET")
ns.frame:RegisterEvent("UNIT_SPELLCAST_INTERRUPTED")

SLASH_AURALITE1 = "/al"
SLASH_AURALITE2 = "/auralite"
SlashCmdList.AURALITE = function(msg)
  if ns.UIV2 and ns.UIV2.Bootstrap and ns.UIV2.Bootstrap.HandleSlash then
    ns.UIV2.Bootstrap:HandleSlash(msg)
    return
  end
  ns.ConfigUI:HandleSlash(msg)
end


