local _, ns = ...

ns.AuraAPI = ns.AuraAPI or {}
local A = ns.AuraAPI

local hasIsSecretValue = type(_G.issecretvalue) == "function"
A._spellIDAliasCache = A._spellIDAliasCache or {}
A._spellBaseDurationCache = A._spellBaseDurationCache or {}

local SPELL_BASE_DURATION_OVERRIDES = {
  [388539] = 15,
}

local function normalizeSpellName(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower():gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function makeLegacyAuraIterator(filter)
  if filter == "HARMFUL" and type(UnitDebuff) == "function" then
    return UnitDebuff, false
  end
  if filter == "HELPFUL" and type(UnitBuff) == "function" then
    return UnitBuff, false
  end
  if type(UnitAura) == "function" then
    return UnitAura, true
  end
  return nil, false
end

local function callLegacyAuraIterator(iterator, passFilter, unit, index, filter)
  if type(iterator) ~= "function" then
    return nil
  end
  if passFilter then
    return iterator(unit, index, filter)
  end
  return iterator(unit, index)
end

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

function A:GetSpellIDAliases(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return {}
  end

  local cached = self._spellIDAliasCache[spellID]
  if cached then
    return cached
  end

  local aliases = { spellID }
  local seen = {
    [spellID] = true,
  }

  local spellName = normalizeSpellName(self:GetSpellName(spellID))
  if spellName ~= "" and type(ns.SpellCatalogData) == "table" then
    for _, row in ipairs(ns.SpellCatalogData) do
      local candidateID = tonumber(row and row.id)
      local candidateName = normalizeSpellName(row and row.name or "")
      if candidateID and candidateName == spellName and not seen[candidateID] then
        seen[candidateID] = true
        aliases[#aliases + 1] = candidateID
      end
    end
  end

  self._spellIDAliasCache[spellID] = aliases
  return aliases
end

function A:GetSpellNameAliases(spellID)
  local out = {}
  local seen = {}

  local function addName(name)
    if type(name) ~= "string" or name == "" then
      return
    end
    local key = normalizeSpellName(name)
    if key == "" or seen[key] then
      return
    end
    seen[key] = true
    out[#out + 1] = name
  end

  spellID = tonumber(spellID)
  if not spellID then
    return out
  end

  local aliases = self:GetSpellIDAliases(spellID)
  for i = 1, #aliases do
    addName(self:GetSpellName(aliases[i]))
  end

  if type(ns.SpellCatalogData) == "table" then
    local aliasIDs = {}
    for i = 1, #aliases do
      aliasIDs[aliases[i]] = true
    end
    for _, row in ipairs(ns.SpellCatalogData) do
      local candidateID = tonumber(row and row.id)
      if candidateID and aliasIDs[candidateID] then
        addName(row.name)
      end
    end
  end

  return out
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

function A:GetSpellBaseDurationSeconds(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end

  local cached = self._spellBaseDurationCache[spellID]
  if cached ~= nil then
    return cached or nil
  end

  local duration = SPELL_BASE_DURATION_OVERRIDES[spellID]
  if not duration and C_Spell and type(C_Spell.GetSpellDescription) == "function" then
    local ok, description = pcall(C_Spell.GetSpellDescription, spellID)
    if ok and type(description) == "string" and description ~= "" then
      local seconds =
        description:match("(%d+%.?%d*)%s+[Ss]ec") or
        description:match("(%d+%.?%d*)%s+[Ss]econds") or
        description:match("(%d+%.?%d*)%s+[Ss]econdi") or
        description:match("(%d+%.?%d*)%s+[Ss]econdo")
      duration = tonumber(seconds)
    end
  end

  self._spellBaseDurationCache[spellID] = duration or false
  return duration
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

local function scanUnitAurasBySpellID(unit, spellID)
  spellID = tonumber(spellID)
  if not unit or not spellID then
    return nil
  end
  local candidateIDs = A:GetSpellIDAliases(spellID)
  local candidateSet = {}
  for i = 1, #candidateIDs do
    candidateSet[candidateIDs[i]] = true
  end

  local function makeLegacyAura(name, icon, applications, duration, expirationTime, sourceUnit, spellIDValue)
    local safeSpellID = tonumber(spellIDValue)
    if not safeSpellID or safeSpellID <= 0 then
      return nil
    end
    return {
      name = name,
      icon = icon,
      applications = tonumber(applications) or 0,
      duration = tonumber(duration) or nil,
      expirationTime = tonumber(expirationTime) or nil,
      sourceUnit = type(sourceUnit) == "string" and sourceUnit or nil,
      spellId = safeSpellID,
      spellID = safeSpellID,
      auraInstanceID = 0,
    }
  end

  local function scanLegacy(filter)
    local iterator, passFilter = makeLegacyAuraIterator(filter)
    if type(iterator) ~= "function" then
      return nil
    end
    for index = 1, 255 do
      local name, icon, applications, _, duration, expirationTime, sourceUnit, _, _, spellIDValue =
        callLegacyAuraIterator(iterator, passFilter, unit, index, filter)
      if name == nil and icon == nil and spellIDValue == nil then
        break
      end
      if candidateSet[tonumber(spellIDValue)] then
        return makeLegacyAura(name, icon, applications, duration, expirationTime, sourceUnit, spellIDValue)
      end
    end
    return nil
  end

  local function scanLegacyByName(filter)
    local iterator, passFilter = makeLegacyAuraIterator(filter)
    if type(iterator) ~= "function" then
      return nil
    end
    local spellNames = A:GetSpellNameAliases(spellID)
    if #spellNames == 0 then
      return nil
    end
    local spellNameSet = {}
    for i = 1, #spellNames do
      spellNameSet[spellNames[i]] = true
    end
    for index = 1, 255 do
      local name, icon, applications, _, duration, expirationTime, sourceUnit, _, _, spellIDValue =
        callLegacyAuraIterator(iterator, passFilter, unit, index, filter)
      if name == nil and icon == nil and spellIDValue == nil then
        break
      end
      if spellNameSet[name] then
        local resolvedSpellID = tonumber(spellIDValue) or spellID
        return makeLegacyAura(name, icon, applications, duration, expirationTime, sourceUnit, resolvedSpellID)
      end
    end
    return nil
  end

  local function matchesAuraSpellID(aura)
    local auraSpellID = aura and (aura.spellId or aura.spellID)
    if not A:IsSafeNumber(auraSpellID) then
      return false
    end
    return candidateSet[tonumber(auraSpellID)] == true
  end

  if AuraUtil and type(AuraUtil.ForEachAura) == "function" then
    local found = nil
    local function visitor(aura)
      if matchesAuraSpellID(aura) then
        found = aura
        return true
      end
      return false
    end
    pcall(AuraUtil.ForEachAura, unit, "HARMFUL", nil, visitor, true)
    if found then
      return found
    end
    pcall(AuraUtil.ForEachAura, unit, "HELPFUL", nil, visitor, true)
    if found then
      return found
    end
  end

  if C_UnitAuras and type(C_UnitAuras.GetAuraDataByIndex) == "function" then
    local function scanFilter(filter)
      for index = 1, 255 do
        local ok, aura = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, filter)
        if not ok or aura == nil then
          break
        end
        if matchesAuraSpellID(aura) then
          return aura
        end
      end
      return nil
    end

    return scanFilter("HARMFUL") or scanFilter("HELPFUL")
  end

  return scanLegacy("HARMFUL") or scanLegacy("HELPFUL") or scanLegacyByName("HARMFUL") or scanLegacyByName("HELPFUL")
end

function A:GetAuraBySpellID(unit, spellID)
  if not unit or not spellID then
    return nil
  end
  local candidateIDs = self:GetSpellIDAliases(spellID)

  if C_UnitAuras and C_UnitAuras.GetUnitAuraBySpellID then
    for i = 1, #candidateIDs do
      local ok, aura = pcall(C_UnitAuras.GetUnitAuraBySpellID, unit, candidateIDs[i])
      if ok and aura then
        return aura
      end
    end
  end

  if unit == "player" and C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID then
    for i = 1, #candidateIDs do
      local ok, aura = pcall(C_UnitAuras.GetPlayerAuraBySpellID, candidateIDs[i])
      if ok and aura then
        return aura
      end
    end
  end

  return scanUnitAurasBySpellID(unit, spellID)
end

function A:DebugDumpUnitAuras(unit, limit)
  if not (ns.Debug and ns.Debug.IsEnabled and ns.Debug:IsEnabled()) then
    return
  end

  unit = tostring(unit or "")
  if unit == "" then
    return
  end

  limit = math.max(1, math.min(tonumber(limit) or 8, 16))

  local function collectFromIterator(filter)
    local out = {}
    local iterator, passFilter = makeLegacyAuraIterator(filter)
    if type(iterator) ~= "function" then
      return out
    end

    for index = 1, limit do
      local name, _, _, _, duration, expirationTime, sourceUnit, _, _, spellIDValue =
        callLegacyAuraIterator(iterator, passFilter, unit, index, filter)
      if name == nil and spellIDValue == nil then
        break
      end
      out[#out + 1] = ("%s#%s src=%s dur=%s exp=%s"):format(
        tostring(name or "?"),
        tostring(tonumber(spellIDValue) or "?"),
        tostring(sourceUnit or "?"),
        tostring(tonumber(duration) or "?"),
        tostring(tonumber(expirationTime) or "?")
      )
    end
    return out
  end

  local harmful = collectFromIterator("HARMFUL")
  local helpful = collectFromIterator("HELPFUL")
  ns.Debug:Logf("Unit aura dump unit=%s harmful=[%s] helpful=[%s]", unit, table.concat(harmful, "; "), table.concat(helpful, "; "))
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

