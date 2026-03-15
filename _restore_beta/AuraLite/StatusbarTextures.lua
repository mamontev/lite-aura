local _, ns = ...

local function registerStatusbar(name, path)
  if type(LibStub) ~= "table" or type(LibStub.GetLibrary) ~= "function" then
    return
  end
  local ok, media = pcall(function()
    return LibStub:GetLibrary("LibSharedMedia-3.0", true)
  end)
  if not ok or type(media) ~= "table" then
    return
  end
  media:Register("statusbar", name, path)
end

registerStatusbar("AuraLite Smooth", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_smooth]])
registerStatusbar("AuraLite Scanline", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_scanline]])
registerStatusbar("AuraLite Carbon", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_carbon]])
registerStatusbar("AuraLite Ember", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_ember]])
registerStatusbar("AuraLite Frost", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_frost]])
registerStatusbar("AuraLite Ridge", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_ridge]])
registerStatusbar("AuraLite Velvet", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_velvet]])
registerStatusbar("AuraLite Pulse", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_pulse]])
registerStatusbar("AuraLite Brass", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_brass]])
registerStatusbar("AuraLite Mist", [[Interface\AddOns\AuraLite\Media\StatusBars\aura_mist]])
