local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2
local E = UI.Events

UI.ValidationBus = UI.ValidationBus or {}
local V = UI.ValidationBus

V._status = V._status or "ok"
V._entries = V._entries or {}
V._subscribers = V._subscribers or {}

local statusWeight = { ok = 1, warn = 2, error = 3 }

local function normalizeSeverity(value)
  value = tostring(value or "ok"):lower()
  if value ~= "warn" and value ~= "error" then
    value = "ok"
  end
  return value
end

local function publish()
  local snapshot = V:GetSnapshot()
  for i = 1, #V._subscribers do
    local fn = V._subscribers[i]
    if type(fn) == "function" then
      pcall(fn, snapshot)
    end
  end
  if E then
    E:Emit(E.Names.VALIDATION_CHANGED, snapshot)
  end
end

function V:GetSnapshot()
  local entries = {}
  for i = 1, #self._entries do
    local row = self._entries[i]
    entries[i] = {
      severity = row.severity,
      path = row.path,
      message = row.message,
    }
  end
  return {
    status = self._status,
    entries = entries,
  }
end

function V:Subscribe(callback)
  if type(callback) ~= "function" then
    return function() end
  end
  self._subscribers[#self._subscribers + 1] = callback
  callback(self:GetSnapshot())
  return function()
    for i = #V._subscribers, 1, -1 do
      if V._subscribers[i] == callback then
        table.remove(V._subscribers, i)
      end
    end
  end
end

function V:SetStatus(status, message)
  status = normalizeSeverity(status)
  self._status = status
  self._entries = {}
  if message and message ~= "" then
    self._entries[1] = {
      severity = status,
      path = "global",
      message = tostring(message),
    }
  end
  publish()
end

function V:SetEntries(entries)
  self._entries = {}
  local maxLevel = "ok"
  for i = 1, #(entries or {}) do
    local row = entries[i] or {}
    local sev = normalizeSeverity(row.severity)
    self._entries[#self._entries + 1] = {
      severity = sev,
      path = tostring(row.path or "global"),
      message = tostring(row.message or ""),
    }
    if statusWeight[sev] > statusWeight[maxLevel] then
      maxLevel = sev
    end
  end
  self._status = maxLevel
  publish()
end

function V:Push(severity, path, message)
  local sev = normalizeSeverity(severity)
  self._entries[#self._entries + 1] = {
    severity = sev,
    path = tostring(path or "global"),
    message = tostring(message or ""),
  }
  if statusWeight[sev] > statusWeight[self._status] then
    self._status = sev
  end
  publish()
end

function V:Clear()
  self._status = "ok"
  self._entries = {}
  publish()
end
