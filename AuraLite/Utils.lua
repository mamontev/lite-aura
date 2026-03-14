local _, ns = ...

ns.Utils = ns.Utils or {}
local U = ns.Utils

function U.Trim(text)
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

function U.DeepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return seen[value]
  end

  local out = {}
  seen[value] = out
  for k, v in pairs(value) do
    out[U.DeepCopy(k, seen)] = U.DeepCopy(v, seen)
  end
  return out
end

function U.ResolveSpellID(value)
  if value == nil then
    return nil
  end

  local asNumber = tonumber(value)
  if asNumber and asNumber > 0 then
    return math.floor(asNumber)
  end

  local text = U.Trim(value)
  if text == "" then
    return nil
  end

  if ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
    local spellID = ns.SpellCatalog:ResolveNameToSpellID(text)
    if tonumber(spellID) then
      return tonumber(spellID)
    end
  end

  if C_Spell and type(C_Spell.GetSpellInfo) == "function" then
    local info = C_Spell.GetSpellInfo(text)
    if type(info) == "table" and tonumber(info.spellID) then
      return tonumber(info.spellID)
    end
  end

  return nil
end

function U.KeysSortedByNumberField(map, fieldName)
  local keys = {}
  if type(map) ~= "table" then
    return keys
  end

  for key in pairs(map) do
    keys[#keys + 1] = key
  end

  table.sort(keys, function(a, b)
    local av = tonumber(type(map[a]) == "table" and map[a][fieldName]) or 0
    local bv = tonumber(type(map[b]) == "table" and map[b][fieldName]) or 0
    if av ~= bv then
      return av < bv
    end
    return tostring(a) < tostring(b)
  end)

  return keys
end

local function isArray(tbl)
  if type(tbl) ~= "table" then
    return false
  end
  local n = 0
  for key in pairs(tbl) do
    if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
      return false
    end
    if key > n then
      n = key
    end
  end
  for i = 1, n do
    if tbl[i] == nil then
      return false
    end
  end
  return true
end

local function serialize(value)
  local valueType = type(value)
  if valueType == "nil" then
    return "nil"
  end
  if valueType == "number" or valueType == "boolean" then
    return tostring(value)
  end
  if valueType == "string" then
    return string.format("%q", value)
  end
  if valueType ~= "table" then
    error("unsupported value type: " .. valueType)
  end

  local parts = {}
  if isArray(value) then
    for i = 1, #value do
      parts[#parts + 1] = serialize(value[i])
    end
  else
    local keys = {}
    for key in pairs(value) do
      keys[#keys + 1] = key
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    for i = 1, #keys do
      local key = keys[i]
      parts[#parts + 1] = "[" .. serialize(key) .. "]=" .. serialize(value[key])
    end
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function U.MakeImportString(payload)
  return "AuraLite:" .. serialize(payload)
end

function U.ParseImportString(serialized)
  local text = U.Trim(serialized)
  if text == "" then
    return nil, "empty import string"
  end

  if text:sub(1, 9) == "AuraLite:" then
    text = text:sub(10)
  end

  local loader = loadstring or load
  local chunk, err = loader("return " .. text)
  if not chunk then
    return nil, err or "invalid import string"
  end

  local ok, result = pcall(chunk)
  if not ok or type(result) ~= "table" then
    return nil, ok and "invalid import payload" or result
  end
  return result
end

