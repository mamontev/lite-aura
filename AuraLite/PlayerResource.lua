local _, ns = ...

ns.PlayerResource = ns.PlayerResource or {}
local R = ns.PlayerResource

local tokenLabelFallback = {
  MANA = "Mana",
  RAGE = "Rage",
  FOCUS = "Focus",
  ENERGY = "Energy",
  COMBO_POINTS = "Combo Points",
  RUNES = "Runes",
  RUNIC_POWER = "Runic Power",
  SOUL_SHARDS = "Soul Shards",
  LUNAR_POWER = "Astral Power",
  HOLY_POWER = "Holy Power",
  MAELSTROM = "Maelstrom",
  CHI = "Chi",
  INSANITY = "Insanity",
  ARCANE_CHARGES = "Arcane Charges",
  FURY = "Fury",
  PAIN = "Pain",
  ESSENCE = "Essence",
}

local function clampPct(value, fallback)
  local n = tonumber(value)
  if not n then
    return fallback
  end
  n = math.floor(n + 0.5)
  if n < 0 then
    n = 0
  end
  if n > 100 then
    n = 100
  end
  return n
end

local function toSafeNumber(value, fallback)
  if type(value) ~= "number" then
    return fallback, false
  end
  if ns.AuraAPI and ns.AuraAPI.IsSecret and ns.AuraAPI:IsSecret(value) then
    return fallback, false
  end
  return value, true
end

function R:GetPrimaryResource()
  local powerType, token = UnitPowerType("player")
  powerType = tonumber(powerType) or 0
  token = tostring(token or "MANA")

  local rawCurrent = UnitPower("player", powerType)
  local rawMax = UnitPowerMax("player", powerType)
  local current, hasCurrent = toSafeNumber(rawCurrent, 0)
  local max, hasMax = toSafeNumber(rawMax, 0)
  local pct = 0
  local available = hasCurrent and hasMax and max > 0
  if available then
    pct = (current / max) * 100
  end

  return {
    type = powerType,
    token = token,
    current = current,
    max = max,
    pct = pct,
    available = available,
  }
end

function R:GetPrimaryLabel()
  local data = self:GetPrimaryResource()
  local token = data.token
  if _G[token] and type(_G[token]) == "string" and _G[token] ~= "" then
    return _G[token]
  end
  return tokenLabelFallback[token] or token
end

function R:NormalizeRange(minPct, maxPct)
  local minV = clampPct(minPct, 0)
  local maxV = clampPct(maxPct, 100)
  if maxV < minV then
    minV, maxV = maxV, minV
  end
  return minV, maxV
end

function R:MatchesRange(minPct, maxPct)
  local data = self:GetPrimaryResource()
  if data.available ~= true then
    return false, data
  end
  local minV, maxV = self:NormalizeRange(minPct, maxPct)
  return data.pct >= minV and data.pct <= maxV, data
end
