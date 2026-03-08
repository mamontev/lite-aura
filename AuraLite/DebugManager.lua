local _, ns = ...

ns.Debug = ns.Debug or {}
local D = ns.Debug

D.lastByKey = D.lastByKey or {}

local function colorWrap(prefix, text)
  return "|cff9af06bAuraLite|r |cffffcc66" .. prefix .. "|r " .. tostring(text or "")
end

local function ensureGlobalLogStore()
  AuraLiteDB = AuraLiteDB or {}
  AuraLiteDB.global = type(AuraLiteDB.global) == "table" and AuraLiteDB.global or {}
  AuraLiteDB.global.debugLog = type(AuraLiteDB.global.debugLog) == "table" and AuraLiteDB.global.debugLog or {}
  return AuraLiteDB.global.debugLog
end

local function getNowTimestamp()
  local ok, ts = pcall(date, "%Y-%m-%d %H:%M:%S")
  if ok and type(ts) == "string" then
    return ts
  end
  return tostring(GetTime() or 0)
end

local function sanitizeLine(text)
  text = tostring(text or "")
  if #text > 600 then
    text = text:sub(1, 600)
  end
  return text:gsub("[\r\n]+", " ")
end

function D:EnsureOptionsDefaults(options)
  options.debugEnabled = options.debugEnabled == true
  options.debugVerbose = options.debugVerbose == true
  if options.debugToChat == nil then
    options.debugToChat = true
  end
  if options.debugToSaved == nil then
    options.debugToSaved = true
  end
  options.debugToChat = options.debugToChat == true
  options.debugToSaved = options.debugToSaved == true
  options.debugSavedMax = tonumber(options.debugSavedMax) or 1500
  if options.debugSavedMax < 200 then
    options.debugSavedMax = 200
  end
  if options.debugSavedMax > 8000 then
    options.debugSavedMax = 8000
  end
end

function D:IsEnabled()
  return ns.db and ns.db.options and ns.db.options.debugEnabled == true
end

function D:IsVerbose()
  return self:IsEnabled() and ns.db.options.debugVerbose == true
end

function D:IsChatOutputEnabled()
  return ns.db and ns.db.options and ns.db.options.debugToChat ~= false
end

function D:IsSavedOutputEnabled()
  return ns.db and ns.db.options and ns.db.options.debugToSaved == true
end

function D:SetEnabled(enabled)
  if not ns.db or not ns.db.options then
    return
  end
  ns.db.options.debugEnabled = enabled == true
end

function D:SetVerbose(enabled)
  if not ns.db or not ns.db.options then
    return
  end
  ns.db.options.debugVerbose = enabled == true
end

function D:SetChatOutput(enabled)
  if not ns.db or not ns.db.options then
    return
  end
  ns.db.options.debugToChat = enabled == true
end

function D:SetSavedOutput(enabled)
  if not ns.db or not ns.db.options then
    return
  end
  ns.db.options.debugToSaved = enabled == true
end

function D:WritePersistent(level, text)
  if not self:IsSavedOutputEnabled() then
    return
  end
  local store = ensureGlobalLogStore()
  local maxLines = tonumber(ns.db and ns.db.options and ns.db.options.debugSavedMax) or 1500
  local entry = {
    t = getNowTimestamp(),
    level = tostring(level or "debug"),
    msg = sanitizeLine(text),
    profile = tostring((ns.state and ns.state.profileKey) or "?"),
  }
  store[#store + 1] = entry
  local overflow = #store - maxLines
  if overflow > 0 then
    for _ = 1, overflow do
      table.remove(store, 1)
    end
  end
end

function D:GetSavedLogCount()
  local store = ensureGlobalLogStore()
  return #store
end

function D:ClearSavedLog()
  local store = ensureGlobalLogStore()
  local count = #store
  for i = #store, 1, -1 do
    store[i] = nil
  end
  return count
end

function D:GetSavedLogText(limit)
  local store = ensureGlobalLogStore()
  local total = #store
  local n = tonumber(limit) or total
  if n < 1 then
    n = total
  end
  if n > total then
    n = total
  end
  local start = total - n + 1
  if start < 1 then
    start = 1
  end
  local lines = {}
  for i = start, total do
    local e = store[i]
    local ts = tostring(e and e.t or "?")
    local lvl = tostring(e and e.level or "debug")
    local profile = tostring(e and e.profile or "?")
    local msg = tostring(e and e.msg or "")
    lines[#lines + 1] = string.format("[%s] [%s] [profile:%s] %s", ts, lvl, profile, msg)
  end
  return table.concat(lines, "\n")
end

function D:Toggle()
  self:SetEnabled(not self:IsEnabled())
  return self:IsEnabled()
end

function D:Log(text)
  if not self:IsEnabled() then
    return
  end
  text = tostring(text or "")
  self:WritePersistent("debug", text)
  if self:IsChatOutputEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage(colorWrap("[debug]", text))
  end
end

function D:Verbose(text)
  if not self:IsVerbose() then
    return
  end
  text = tostring(text or "")
  self:WritePersistent("verbose", text)
  if self:IsChatOutputEnabled() then
    DEFAULT_CHAT_FRAME:AddMessage(colorWrap("[verbose]", text))
  end
end

function D:Verbosef(fmt, ...)
  if not self:IsVerbose() then
    return
  end
  local ok, msg = pcall(string.format, tostring(fmt or ""), ...)
  if not ok then
    msg = tostring(fmt)
  end
  self:Verbose(msg)
end

function D:Logf(fmt, ...)
  if not self:IsEnabled() then
    return
  end
  local ok, msg = pcall(string.format, tostring(fmt or ""), ...)
  if not ok then
    msg = tostring(fmt)
  end
  self:Log(msg)
end

function D:Throttled(key, seconds, fmt, ...)
  if not self:IsEnabled() then
    return
  end
  local now = GetTime()
  local last = self.lastByKey[key] or 0
  if (now - last) < (seconds or 0.3) then
    return
  end
  self.lastByKey[key] = now
  self:Logf(fmt, ...)
end

function D:PrintTaintAuditChecklist()
  local lines = {
    "Taint audit checklist:",
    "1) No SecureActionButtonTemplate",
    "2) No SetAttribute in combat paths",
    "3) No RegisterForClicks click-casting paths",
    "4) No parenting to protected Blizzard frames",
    "5) No SetPoint/ClearAllPoints/Show/Hide on protected descendants in combat",
    "6) No Blizzard action button APIs from custom frames",
    "7) Enable taint log for root-cause: /console taintLog 2",
    "8) Reproduce popup, then inspect _retail_/Logs/taint.log",
  }
  local enabled = self:IsEnabled()
  if not enabled then
    self:SetEnabled(true)
  end
  for i = 1, #lines do
    self:Log(lines[i])
  end
  if not enabled then
    self:SetEnabled(false)
  end
end
