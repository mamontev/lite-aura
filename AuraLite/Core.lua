local addonName, ns = ...

ns.name = addonName
ns.frame = ns.frame or CreateFrame("Frame")
ns.state = ns.state or {
  editMode = false,
  restrictionActive = false,
  profileKey = "default",
}

local initialized = false

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
  if self.Debug then
    self.Debug:Log("Addon initialized.")
  end
  initialized = true
end

function ns:RegisterRuntimeEvents()
  -- Hard-safe mode: cast success uses hook+poll confirmation, not protected cast events.
  self.state.runtimeEventsRegistered = false
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
ns.frame:RegisterEvent("UNIT_POWER_UPDATE")
ns.frame:RegisterEvent("UNIT_MAXPOWER")
ns.frame:RegisterEvent("UNIT_DISPLAYPOWER")
ns.frame:RegisterEvent("SPELL_UPDATE_COOLDOWN")
ns.frame:RegisterEvent("SPELL_UPDATE_CHARGES")
ns.frame:RegisterEvent("ACTIONBAR_UPDATE_COOLDOWN")
ns.frame:RegisterEvent("SPELL_UPDATE_USABLE")
ns.frame:RegisterEvent("UI_ERROR_MESSAGE")

SLASH_AURALITE1 = "/al"
SLASH_AURALITE2 = "/auralite"
SlashCmdList.AURALITE = function(msg)
  ns.ConfigUI:HandleSlash(msg)
end
