local _, ns = ...

ns.TestMode = ns.TestMode or {}
local T = ns.TestMode

function T:IsEnabled()
  return ns.state.editMode == true
end

function T:SetEnabled(enabled)
  ns.state.editMode = enabled == true
end

function T:BuildPlaceholder(item, unit)
  local now = GetTime()
  local duration = tonumber(item and (item.estimatedDuration or item.duration)) or 0
  if duration <= 0 then
    duration = 12 + ((tonumber(item and item.spellID) or 0) % 9)
  end
  local elapsed = (item.spellID % duration)

  return {
    unit = unit,
    spellID = item.spellID,
    auraInstanceID = 0,
    icon = ns.AuraAPI:GetDisplayTextureForItem(item, nil),
    fallbackIcon = ns.AuraAPI:GetSpellTexture(item.spellID) or 136243,
    applications = math.max(1, (item.spellID % 4)),
    expirationTime = now + (duration - elapsed),
    duration = duration,
    sourceLabel = "TEST",
    canCompute = true,
    alert = item.alert ~= false,
  }
end
