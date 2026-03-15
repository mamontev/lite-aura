local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.SpellInput = UI.SpellInput or {}
local SI = UI.SpellInput

local function trim(text)
  text = tostring(text or "")
  text = text:gsub("^%s+", "")
  text = text:gsub("%s+$", "")
  return text
end

local function splitCSV(text)
  local out = {}
  for token in tostring(text or ""):gmatch("[^,;]+") do
    token = trim(token)
    if token ~= "" then
      out[#out + 1] = token
    end
  end
  return out
end

function SI:ResolveToken(token)
  token = trim(token)
  if token == "" then
    return nil, ""
  end

  local n = tonumber(token)
  if n and n > 0 then
    return math.floor(n + 0.0001), tostring(math.floor(n + 0.0001))
  end

  if ns.Utils and ns.Utils.ResolveSpellID then
    local fromUtils = ns.Utils.ResolveSpellID(ns.Utils, token)
    if tonumber(fromUtils) and tonumber(fromUtils) > 0 then
      local id = math.floor(tonumber(fromUtils) + 0.0001)
      return id, tostring(id)
    end
  end

  if ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
    local exact = ns.SpellCatalog:ResolveNameToSpellID(token)
    if tonumber(exact) and tonumber(exact) > 0 then
      local id = math.floor(tonumber(exact) + 0.0001)
      return id, tostring(id)
    end
  end

  if ns.SpellCatalog and ns.SpellCatalog.Search then
    local found = ns.SpellCatalog:Search(token, 1)
    if type(found) == "table" and found[1] and tonumber(found[1].id) then
      local id = math.floor(tonumber(found[1].id) + 0.0001)
      return id, tostring(id)
    end
  end

  return nil, token
end

function SI:ResolveSpellIDInput(text)
  local id, unresolved = self:ResolveToken(text)
  if id then
    return tostring(id), "ID: " .. tostring(id), true
  end
  return trim(text), unresolved ~= "" and ("Unresolved: " .. unresolved) or "", false
end

function SI:ResolveSpellCSVInput(text)
  local tokens = splitCSV(text)
  local ids = {}
  local unresolved = {}
  local seen = {}
  for i = 1, #tokens do
    local id = self:ResolveToken(tokens[i])
    if id and not seen[id] then
      seen[id] = true
      ids[#ids + 1] = tostring(id)
    elseif not id then
      unresolved[#unresolved + 1] = tokens[i]
    end
  end

  local resolvedText = table.concat(ids, ",")
  local preview = ""
  if #ids > 0 then
    preview = "IDs: " .. resolvedText
  else
    preview = "No valid spell IDs"
  end
  if #unresolved > 0 then
    preview = preview .. " | Unresolved: " .. table.concat(unresolved, ", ")
  end

  return resolvedText, preview, #ids > 0, unresolved
end

