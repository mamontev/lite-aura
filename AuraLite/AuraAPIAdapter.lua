local _, ns = ...

ns.AuraAPI = ns.AuraAPI or {}
local A = ns.AuraAPI

local hasIsSecretValue = type(_G.issecretvalue) == "function"

function A:IsSecret(value)
  if hasIsSecretValue then
    return issecretvalue(value)
  end
  return false
end

function A:IsSafeNumber(value)
  return type(value) == "number" and not self:IsSecret(value)
end

function A:IsSafeBoolean(value)
  return type(value) == "boolean" and not self:IsSecret(value)
end

function A:IsSafeTexture(value)
  if value == nil or self:IsSecret(value) then
    return false
  end

  local valueType = type(value)
  if valueType == "number" then
    return value > 0
  end
  if valueType == "string" then
    return value ~= ""
  end
  return false
end

function A:SelectBestTexture(...)
  local count = select("#", ...)
  for i = 1, count do
    local texture = select(i, ...)
    if self:IsSafeTexture(texture) then
      return texture
    end
  end
  return 136243
end

function A:CanComputeRemaining(aura)
  if type(aura) ~= "table" then
    return false
  end
  local expirationTime, duration = self:GetAuraTiming(aura)
  return self:IsSafeNumber(expirationTime) and self:IsSafeNumber(duration)
end

function A:IsFromPlayerOrPet(aura)
  if not aura then
    return false
  end
  if self:IsSafeBoolean(aura.isFromPlayerOrPlayerPet) then
    return aura.isFromPlayerOrPlayerPet == true
  end
  local sourceUnit = self:GetAuraSourceUnit(aura)
  return sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle"
end

function A:GetAuraSpellID(aura)
  if type(aura) ~= "table" then
    return nil
  end
  local spellID = aura.spellId
  if not self:IsSafeNumber(spellID) then
    spellID = aura.spellID
  end
  if self:IsSafeNumber(spellID) then
    return spellID
  end
  return nil
end

function A:GetAuraApplications(aura)
  if type(aura) ~= "table" then
    return 0
  end
  local stacks = aura.applications
  if self:IsSafeNumber(stacks) then
    return math.max(0, math.floor(stacks + 0.0001))
  end
  return 0
end

function A:GetAuraTiming(aura)
  if type(aura) ~= "table" then
    return nil, nil
  end
  local expirationTime = aura.expirationTime
  local duration = aura.duration
  if not self:IsSafeNumber(expirationTime) then
    expirationTime = nil
  end
  if not self:IsSafeNumber(duration) then
    duration = nil
  end
  return expirationTime, duration
end

function A:GetAuraInstanceID(aura)
  if type(aura) ~= "table" then
    return 0
  end
  local auraInstanceID = aura.auraInstanceID
  if self:IsSafeNumber(auraInstanceID) then
    return auraInstanceID
  end
  return 0
end

function A:GetAuraSourceUnit(aura)
  if type(aura) ~= "table" then
    return nil
  end
  local sourceUnit = aura.sourceUnit
  if sourceUnit == nil or self:IsSecret(sourceUnit) then
    return nil
  end
  if type(sourceUnit) ~= "string" then
    return nil
  end
  return sourceUnit
end

function A:GetSpellName(spellID)
  if C_Spell and C_Spell.GetSpellName then
    return C_Spell.GetSpellName(spellID)
  end
  if GetSpellInfo then
    return GetSpellInfo(spellID)
  end
  return nil
end

function A:GetSpellTexture(spellID)
  local texture = nil
  if C_Spell and C_Spell.GetSpellTexture then
    texture = C_Spell.GetSpellTexture(spellID)
  elseif GetSpellInfo then
    local _, _, icon = GetSpellInfo(spellID)
    texture = icon
  end

  if self:IsSafeTexture(texture) then
    return texture
  end
  return nil
end

function A:GetSpellCooldownData(spellID)
  if not spellID then
    return nil
  end
  if self:IsSecretCooldownsRestricted(spellID) then
    return nil
  end

  local function safeNumber(value, fallback)
    if type(value) == "number" and self:IsSafeNumber(value) then
      return value
    end
    return fallback or 0
  end

  local function safeEnabled(value)
    if value == false then
      return 0
    end
    if value == true then
      return 1
    end
    local n = safeNumber(value, 1)
    if n == 0 then
      return 0
    end
    return 1
  end

  local startTime = 0
  local duration = 0
  local enabled = 1

  local cStart, cDuration, cEnabled = 0, 0, 1
  if C_Spell and C_Spell.GetSpellCooldown then
    local ok, data = pcall(C_Spell.GetSpellCooldown, spellID)
    if ok and type(data) == "table" then
      cStart = safeNumber(data.startTime or data.cooldownStartTime, 0)
      cDuration = safeNumber(data.duration or data.cooldownDuration, 0)
      cEnabled = safeEnabled(data.isEnabled)
    end
  end

  local lStart, lDuration, lEnabled = 0, 0, 1
  if GetSpellCooldown then
    local s, d, e = GetSpellCooldown(spellID)
    lStart = safeNumber(s, 0)
    lDuration = safeNumber(d, 0)
    lEnabled = safeEnabled(e)
  end

  if cDuration >= lDuration then
    startTime, duration, enabled = cStart, cDuration, cEnabled
  else
    startTime, duration, enabled = lStart, lDuration, lEnabled
  end

  local chargeStart = 0
  local chargeDuration = 0
  local currentCharges, maxCharges = nil, nil
  if GetSpellCharges then
    local c, m, cs, cd = GetSpellCharges(spellID)
    currentCharges = safeNumber(c, nil)
    maxCharges = safeNumber(m, nil)
    chargeStart = safeNumber(cs, 0)
    chargeDuration = safeNumber(cd, 0)
  end

  local finalStart = startTime
  local finalDuration = duration
  if maxCharges and maxCharges > 1 and currentCharges and currentCharges < maxCharges and chargeDuration > 0 and chargeStart > 0 then
    finalStart = chargeStart
    finalDuration = chargeDuration
  end

  if enabled == 0 then
    return nil
  end
  if not self:IsSafeNumber(finalStart) or not self:IsSafeNumber(finalDuration) then
    return nil
  end
  if finalDuration <= 0 or finalStart <= 0 then
    return nil
  end

  local gcdStart = 0
  local gcdDuration = 0
  if GetSpellCooldown then
    local gs, gd = GetSpellCooldown(61304)
    gcdStart = safeNumber(gs, 0)
    gcdDuration = safeNumber(gd, 0)
  end
  if gcdDuration > 0 then
    local sameStart = math.abs(finalStart - gcdStart) <= 0.06
    local sameDuration = math.abs(finalDuration - gcdDuration) <= 0.06
    if sameStart and sameDuration then
      return nil
    end
  end

  if finalDuration <= 0.05 then
    return nil
  end

  return {
    startTime = finalStart,
    duration = finalDuration,
    expirationTime = finalStart + finalDuration,
    canCompute = true,
  }
end

function A:NormalizeTexturePath(path)
  if type(path) ~= "string" then
    return ""
  end
  local out = path:gsub("^%s+", ""):gsub("%s+$", "")
  out = out:gsub("/", "\\")
  repeat
    local before = out
    out = out:gsub("\\\\", "\\")
    if before == out then
      break
    end
  until false
  out = out:gsub("%.tga$", ""):gsub("%.TGA$", "")
  out = out:gsub("%.blp$", ""):gsub("%.BLP$", "")
  return out
end

function A:ResolveCustomTexturePath(path)
  local normalized = self:NormalizeTexturePath(path)
  if normalized == "" then
    return ""
  end

  if normalized:lower():find("^interface\\", 1, true) then
    return normalized
  end

  if normalized:find("\\", 1, true) then
    return normalized
  end

  return "Interface\\AddOns\\AuraLite\\Media\\Custom\\" .. normalized
end

function A:ResolveBarTexturePath(path)
  local normalized = self:NormalizeTexturePath(path)
  if normalized == "" then
    return "Interface\\TargetingFrame\\UI-StatusBar"
  end

  if normalized:lower():find("^lsm:", 1, true) then
    local key = normalized:sub(5)
    if key ~= "" and ns.Media and ns.Media.Fetch then
      local resolved = ns.Media:Fetch("statusbar", key)
      if type(resolved) == "string" and resolved ~= "" then
        return resolved
      end
    end
    return "Interface\\TargetingFrame\\UI-StatusBar"
  end

  if normalized:lower():find("^interface\\", 1, true) then
    return normalized
  end

  if normalized:find("\\", 1, true) then
    return normalized
  end

  return "Interface\\AddOns\\AuraLite\\Media\\Custom\\" .. normalized
end

function A:GetDisplayTextureForItem(item, aura)
  if item and item.iconMode == "custom" then
    local custom = self:ResolveCustomTexturePath(item.customTexture)
    if custom ~= "" then
      return custom
    end
  end

  local auraIcon = aura and aura.icon or nil
  local spellIcon = nil
  if item and item.spellID then
    spellIcon = self:GetSpellTexture(item.spellID)
  end

  return self:SelectBestTexture(auraIcon, spellIcon, 136243)
end

function A:GetAuraBySpellID(unit, spellID)
  if not unit or not spellID then
    return nil
  end

  if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, spellID)
    if ok then
      return aura
    end
  end

  if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, spellID)
    if ok then
      return aura
    end
  end

  return nil
end

function A:IsPlayerAuraPresentBySpellID(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return false
  end
  local aura = self:GetAuraBySpellID("player", spellID)
  return aura ~= nil
end

function A:GetAuraByInstanceID(unit, auraInstanceID)
  if C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
    local ok, aura = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, auraInstanceID)
    if ok then
      return aura
    end
  end
  return nil
end

function A:IsRestrictionActive()
  if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
    local restriction = Enum.AddOnRestrictionType.SecretAuras
    if restriction and C_RestrictedActions.IsAddOnRestrictionActive(restriction) then
      return true
    end
  end

  if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
    local actionType = Enum.RestrictedActionType.SecretAuras
    if actionType then
      local ok, restricted = pcall(GetRestrictedActionStatus, actionType)
      if ok then
        return restricted == true
      end
    end
  end

  return false
end

function A:IsSecretCooldownsRestricted(spellID)
  if C_Secrets and C_Secrets.ShouldCooldownsBeSecret then
    local ok, restricted = pcall(C_Secrets.ShouldCooldownsBeSecret)
    if ok and restricted == true then
      return true
    end
  end

  if spellID and C_Secrets and C_Secrets.ShouldSpellCooldownBeSecret then
    local ok, restricted = pcall(C_Secrets.ShouldSpellCooldownBeSecret, spellID)
    if ok and restricted == true then
      return true
    end
  end

  if C_RestrictedActions and C_RestrictedActions.IsAddOnRestrictionActive and Enum and Enum.AddOnRestrictionType then
    local restriction = Enum.AddOnRestrictionType.SecretCooldowns
    if restriction and C_RestrictedActions.IsAddOnRestrictionActive(restriction) then
      return true
    end
  end

  if GetRestrictedActionStatus and Enum and Enum.RestrictedActionType then
    local actionType = Enum.RestrictedActionType.SecretCooldowns
    if actionType then
      local ok, restricted = pcall(GetRestrictedActionStatus, actionType)
      if ok then
        return restricted == true
      end
    end
  end
  return false
end

function A:GetSourceLabel(aura)
  local sourceUnit = self:GetAuraSourceUnit(aura)
  if sourceUnit == nil then
    return ""
  end
  if sourceUnit == "player" then
    return ""
  end
  if sourceUnit == "pet" or sourceUnit == "vehicle" then
    return ""
  end
  local txt = tostring(sourceUnit):upper()
  return txt:sub(1, 3)
end
