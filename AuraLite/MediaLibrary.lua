local _, ns = ...

ns.Media = ns.Media or {}
local M = ns.Media

M._lsm = M._lsm or nil
M._lsmResolved = M._lsmResolved == true

function M:GetLSM()
  if self._lsmResolved then
    return self._lsm
  end
  self._lsmResolved = true

  if type(LibStub) ~= "table" then
    return nil
  end

  local ok, lib = pcall(function()
    if type(LibStub.GetLibrary) == "function" then
      return LibStub:GetLibrary("LibSharedMedia-3.0", true)
    end
    return nil
  end)
  if ok and type(lib) == "table" then
    self._lsm = lib
  end
  return self._lsm
end

function M:HasLSM()
  return self:GetLSM() ~= nil
end

function M:Fetch(kind, name)
  local lib = self:GetLSM()
  if not lib or type(name) ~= "string" or name == "" then
    return nil
  end
  local ok, value = pcall(lib.Fetch, lib, kind, name, true)
  if ok and value ~= nil then
    return value
  end
  return nil
end

function M:List(kind)
  local lib = self:GetLSM()
  if not lib then
    return {}
  end
  local ok, list = pcall(lib.List, lib, kind)
  if ok and type(list) == "table" then
    return list
  end
  return {}
end

local function buildOptionsFromList(prefix, list)
  local out = {}
  for i = 1, #list do
    local name = tostring(list[i] or "")
    if name ~= "" then
      out[#out + 1] = {
        value = prefix .. name,
        label = "LSM: " .. name,
      }
    end
  end
  table.sort(out, function(a, b)
    return tostring(a.label) < tostring(b.label)
  end)
  return out
end

function M:GetStatusbarOptions()
  return buildOptionsFromList("lsm:", self:List("statusbar"))
end

function M:GetStatusbarEntries()
  local list = self:List("statusbar")
  local entries = {
    {
      value = "",
      label = "Default (Blizzard)",
      texture = "Interface\\TargetingFrame\\UI-StatusBar",
      builtin = true,
    },
  }

  for i = 1, #list do
    local name = tostring(list[i] or "")
    if name ~= "" then
      entries[#entries + 1] = {
        value = "lsm:" .. name,
        label = name,
        texture = self:Fetch("statusbar", name) or "Interface\\TargetingFrame\\UI-StatusBar",
        builtin = (name == "Blizzard" or name == "Blizzard Character Skills Bar" or name == "Blizzard Raid Bar" or name == "Solid"),
      }
    end
  end

  table.sort(entries, function(a, b)
    if a.value == "" then
      return true
    end
    if b.value == "" then
      return false
    end
    if a.builtin ~= b.builtin then
      return a.builtin == true
    end
    return tostring(a.label) < tostring(b.label)
  end)

  return entries
end

function M:GetSoundOptions()
  return buildOptionsFromList("lsm:", self:List("sound"))
end
