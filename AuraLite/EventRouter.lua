local _, ns = ...
local U = ns.Utils or {}
ns.EventRouter = ns.EventRouter or {}
local E = ns.EventRouter
E.lastProcessedCast = E.lastProcessedCast or {}
E.lastCooldownRefresh = E.lastCooldownRefresh or 0
E.castResolverStates = E.castResolverStates or {}
E.castResolverTokenCounter = E.castResolverTokenCounter or 0
E.castResolverLastConfirmAt = E.castResolverLastConfirmAt or {}
E.castResolverGlobalGateUntil = E.castResolverGlobalGateUntil or 0
E.castResolverFailGateUntilBySpell = E.castResolverFailGateUntilBySpell or {}
E.hookedTriggerSet = E.hookedTriggerSet or {}
E.hookedTriggerRevision = E.hookedTriggerRevision or -1
E.lastRawAttempt = E.lastRawAttempt or nil
E.lastRefreshSummary = E.lastRefreshSummary or { key = "", at = 0 }

local function trimSafe(text)
  if U and type(U.Trim) == "function" then
    return U.Trim(text)
  end
  text = tostring(text or "")
  return (text:gsub("^%s+", ""):gsub("%s+$", ""))
end

local processPlayerCast
local getActiveGlobalCooldownEndAt
local isSpellOffGlobalCooldown
local getResolverGateEndAt

local RESOLVER_ATTRIBUTION_WINDOW = 0.08
local RESOLVER_MAX_AGE = 0.45
local RESOLVER_RESTRICTED_MIN_AGE = 0.12
local RESOLVER_RESTRICTED_MAX_AGE = 0.35
local RESOLVER_CONFIRM_DEDUPE = 0.20
local RESOLVER_DUPLICATE_OPEN_WINDOW = 0.18
local RESOLVER_BLOCKED_REUSE_WINDOW = 0.04
local RESOLVER_GCD_REUSE_MARGIN = 0.03
local RESOLVER_GCD_FALLBACK_DURATION = 0.75
local RESOLVER_FAIL_GATE_DURATION = 0.10

-- Conservative off-GCD overrides. We can expand this list as we validate
-- concrete spells in logs or from curated references.
local OFF_GCD_SPELLS = {
  [2565] = true,   -- Shield Block
  [23920] = true,  -- Spell Reflection
}

local function getSpellDebugName(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return "?"
  end
  local name = ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID) or nil
  if type(name) == "string" and name ~= "" then
    return name
  end
  return "spell#" .. tostring(spellID)
end

local function normalizeQueuedSpellID(spellIdentifier)
  local id = tonumber(spellIdentifier)
  if id and id > 0 then
    return id
  end
  if type(spellIdentifier) == "table" then
    id = tonumber(spellIdentifier.spellID)
    if id and id > 0 then
      return id
    end
    id = tonumber(spellIdentifier.spellId)
    if id and id > 0 then
      return id
    end
    id = tonumber(spellIdentifier.id)
    if id and id > 0 then
      return id
    end
  end
  return nil
end

local function ensureCooldownState()
  ns.state.cooldownLearned = ns.state.cooldownLearned or {}
  ns.state.cooldownEstimated = ns.state.cooldownEstimated or {}
end

local function learnCooldown(spellID, duration)
  spellID = tonumber(spellID)
  duration = tonumber(duration)
  if not spellID or not duration or duration <= 0.05 then
    return
  end
  ensureCooldownState()
  ns.state.cooldownLearned[spellID] = duration
end

local function clearEstimatedCooldown(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return
  end
  ensureCooldownState()
  ns.state.cooldownEstimated[spellID] = nil
end

local function getEstimatedCooldown(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  ensureCooldownState()
  local data = ns.state.cooldownEstimated[spellID]
  if not data then
    return nil
  end
  local now = GetTime()
  if not data.expirationTime or data.expirationTime <= now + 0.05 then
    ns.state.cooldownEstimated[spellID] = nil
    return nil
  end
  return {
    startTime = data.startTime,
    duration = data.duration,
    expirationTime = data.expirationTime,
    canCompute = true,
    isEstimated = true,
  }
end

local function startEstimatedCooldown(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  ensureCooldownState()
  local duration = tonumber(ns.state.cooldownLearned[spellID])
  if not duration or duration <= 0.05 then
    return nil
  end
  local now = GetTime()
  local out = {
    startTime = now,
    duration = duration,
    expirationTime = now + duration,
    canCompute = true,
    isEstimated = true,
  }
  ns.state.cooldownEstimated[spellID] = out
  return out
end

local function mergeGroupRows(dst, src)
  for groupID, rows in pairs(src) do
    dst[groupID] = dst[groupID] or {}
    for i = 1, #rows do
      dst[groupID][#dst[groupID] + 1] = rows[i]
    end
  end
end


local function sanitizeGroupToken(text)
  text = tostring(text or ""):lower()
  text = text:gsub("[^%w_]+", "_")
  text = text:gsub("_+", "_")
  text = text:gsub("^_+", "")
  text = text:gsub("_+$", "")
  return text
end

local function buildIndependentGroupID(unit, item)
  local spellID = tonumber(item and item.spellID) or 0
  local unitToken = sanitizeGroupToken(unit or "player")
  local uidToken = sanitizeGroupToken(item and item.instanceUID or "")
  if uidToken ~= "" then
    return string.format("aura_%s_%s", unitToken, uidToken)
  end
  local groupToken = sanitizeGroupToken(item and item.groupID or "group")
  local nameToken = sanitizeGroupToken(item and item.displayName or "")
  if nameToken == "" then
    nameToken = "spell" .. tostring(spellID)
  end
  return string.format("aura_%s_%s_%d_%s", unitToken, groupToken, spellID, nameToken)
end

local function cloneLayoutSafe(layout)
  if type(layout) ~= "table" then
    return { iconSize = 36, spacing = 4, direction = "RIGHT" }
  end
  return {
    iconSize = tonumber(layout.iconSize) or 36,
    spacing = tonumber(layout.spacing) or 4,
    direction = tostring(layout.direction or "RIGHT"),
    nudgeX = tonumber(layout.nudgeX) or 0,
    nudgeY = tonumber(layout.nudgeY) or 0,
  }
end
local function ensureIndependentGroup(groupID, sourceGroupID, item)
  if not ns.db or type(ns.db.groups) ~= "table" or type(ns.db.positions) ~= "table" then
    return
  end
  if ns.db.groups[groupID] then
    return
  end
  local maxOrder = 0
  for _, cfg in pairs(ns.db.groups) do
    maxOrder = math.max(maxOrder, tonumber(cfg and cfg.order) or 0)
  end
  local source = ns.db.groups[sourceGroupID]
  local layout = cloneLayoutSafe(source and source.layout)
  local spellID = tonumber(item and item.spellID) or 0
  local name = trimSafe(tostring(item and item.displayName or ""))
  if name == "" then
    name = (ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(spellID)) or ("Spell " .. tostring(spellID))
  end
  ns.db.groups[groupID] = {
    id = groupID,
    name = name,
    order = maxOrder + 1,
    layout = layout,
  }
  ns.db.positions[groupID] = ns.db.positions[groupID] or {
    point = "CENTER",
    relativePoint = "CENTER",
    x = 0,
    y = -72 - ((maxOrder + 1) * 52),
  }
end

local function resolveDisplayGroupID(unit, item)
  local sourceGroupID = tostring(item and item.groupID or "important_procs")

  if item and item.layoutGroupEnabled == true then
    local linkedGroupID = sanitizeGroupToken(sourceGroupID)
    if linkedGroupID == "" then
      linkedGroupID = "important_procs"
    end
    ensureIndependentGroup(linkedGroupID, sourceGroupID, item)
    return linkedGroupID
  end

  local groupID = buildIndependentGroupID(unit, item)
  ensureIndependentGroup(groupID, sourceGroupID, item)
  return groupID
end

local function isSelectedAuraInUnlock(unit, item)
  if not (ns.db and ns.db.locked == false and ns.state and ns.state.selectedAura) then
    return false
  end
  if tostring(ns.state.selectedAura.unit or "") ~= tostring(unit or "") then
    return false
  end
  local selectedUID = tostring(ns.state.selectedAura.instanceUID or "")
  local itemUID = tostring(item and item.instanceUID or "")
  if selectedUID ~= "" and itemUID ~= "" then
    return selectedUID == itemUID
  end
  return tonumber(ns.state.selectedAura.spellID) == tonumber(item and item.spellID)
end

local function getPlayerClassToken()
  local _, classToken = UnitClass("player")
  return tostring(classToken or "")
end

local function getPlayerSpecID()
  if not GetSpecialization or not GetSpecializationInfo then
    return nil
  end
  local specIndex = GetSpecialization()
  if not specIndex then
    return nil
  end
  local specID = GetSpecializationInfo(specIndex)
  return tonumber(specID)
end

local function isAuraLoadAllowed(item, playerClassToken, playerSpecID)
  if type(item) ~= "table" then
    return true
  end
  local loadClass = tostring(item.loadClassToken or "")
  if loadClass ~= "" and playerClassToken ~= "" and loadClass ~= playerClassToken then
    return false
  end
  local specList = item.loadSpecIDs
  if type(specList) == "table" and #specList > 0 then
    local sid = tonumber(playerSpecID)
    if not sid then
      return false
    end
    local matched = false
    for i = 1, #specList do
      if tonumber(specList[i]) == sid then
        matched = true
        break
      end
    end
    if not matched then
      return false
    end
  end
  return true
end

function E:RefreshHookedTriggerSet()
  local revision = (ns.ProcRules and ns.ProcRules.GetRevision and ns.ProcRules:GetRevision()) or 0
  if self.hookedTriggerRevision == revision and self.hookedTriggerSet then
    return
  end

  self.hookedTriggerSet = self.hookedTriggerSet or {}
  for k in pairs(self.hookedTriggerSet) do
    self.hookedTriggerSet[k] = nil
  end

  if not ns.ProcRules or not ns.ProcRules.GetTriggerSpellIDs then
    return
  end

  local ids = ns.ProcRules:GetTriggerSpellIDs()
  for i = 1, #ids do
    local spellID = tonumber(ids[i])
    if spellID and spellID > 0 then
      self.hookedTriggerSet[spellID] = true
    end
  end
  self.hookedTriggerRevision = revision
end

local function nextResolverToken(self)
  self.castResolverTokenCounter = (tonumber(self.castResolverTokenCounter) or 0) + 1
  return self.castResolverTokenCounter
end

local function getResolverStates(self)
  self.castResolverStates = self.castResolverStates or {}
  return self.castResolverStates
end

local function logResolverOutcome(state, outcome, detail, now)
  if type(state) ~= "table" then
    return
  end
  now = tonumber(now) or GetTime()
  ns.Debug:Logf(
    "CastResolver outcome=%s token=%d spellID=%d name=%s detail=%s age=%.2f",
    tostring(outcome or "unknown"),
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(getSpellDebugName(state.spellID)),
    tostring(detail or "none"),
    math.max(0, now - (tonumber(state.attemptAt) or 0))
  )
end

local function expireResolverState(self, state, reason, now)
  if type(state) ~= "table" then
    return
  end
  local states = getResolverStates(self)
  local current = states[state.spellID]
  if current ~= state then
    return
  end
  state.status = "expired"
  ns.Debug:Logf(
    "CastResolver attempt_expire token=%d spellID=%d reason=%s age=%.2f",
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(reason or "expired"),
    math.max(0, (tonumber(now) or GetTime()) - (tonumber(state.attemptAt) or 0))
  )
  logResolverOutcome(state, "cast expired unresolved", tostring(reason or "expired"), now)
  states[state.spellID] = nil
end

local function blockResolverState(self, state, reason, now)
  if type(state) ~= "table" or state.status ~= "attempted" then
    return false
  end
  local states = getResolverStates(self)
  if states[state.spellID] ~= state then
    return false
  end
  state.status = "blocked"
  state.lastErrorAt = tonumber(now) or GetTime()
  state.blockReason = tostring(reason or "ui_error")
  ns.Debug:Logf(
    "CastResolver attempt_block token=%d spellID=%d reason=%s age=%.2f",
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(state.blockReason),
    math.max(0, (tonumber(state.lastErrorAt) or 0) - (tonumber(state.attemptAt) or 0))
  )
  logResolverOutcome(state, "cast failed by game", tostring(state.blockReason), now)
  self.castResolverFailGateUntilBySpell = self.castResolverFailGateUntilBySpell or {}
  self.castResolverFailGateUntilBySpell[state.spellID] = (tonumber(now) or GetTime()) + RESOLVER_FAIL_GATE_DURATION
  states[state.spellID] = nil
  return true
end

local function confirmResolverState(self, state, sourceTag, now)
  if type(state) ~= "table" or state.status ~= "attempted" then
    return false
  end
  local states = getResolverStates(self)
  if states[state.spellID] ~= state then
    return false
  end
  now = tonumber(now) or GetTime()
  self.castResolverLastConfirmAt = self.castResolverLastConfirmAt or {}
  local lastConfirm = tonumber(self.castResolverLastConfirmAt[state.spellID]) or 0
  if (now - lastConfirm) < RESOLVER_CONFIRM_DEDUPE then
    expireResolverState(self, state, "duplicate_confirm", now)
    return false
  end
  self.castResolverLastConfirmAt[state.spellID] = now
  state.status = "confirmed"
  state.lastConfirmAt = now
  ns.Debug:Logf(
    "CastResolver attempt_confirm token=%d spellID=%d via=%s age=%.2f restricted=%s",
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(sourceTag or state.sourceTag or "resolver"),
    math.max(0, now - (tonumber(state.attemptAt) or 0)),
    tostring(state.restricted == true)
  )
  logResolverOutcome(state, "cast confirmed", tostring(sourceTag or state.sourceTag or "resolver"), now)
  if state.offGCD ~= true then
    local gateUntil = tonumber(state.gcdEndAt) or 0
    local usedFallback = false
    if gateUntil <= now then
      gateUntil, usedFallback = getResolverGateEndAt(now)
    end
    if gateUntil and gateUntil > now then
      self.castResolverGlobalGateUntil = math.max(tonumber(self.castResolverGlobalGateUntil) or 0, gateUntil)
      ns.Debug:Verbosef(
        "CastResolver global_gate spellID=%d until=%.2f remaining=%.2f fallback=%s",
        tonumber(state.spellID) or 0,
        tonumber(self.castResolverGlobalGateUntil) or 0,
        math.max(0, (tonumber(self.castResolverGlobalGateUntil) or 0) - now),
        tostring(usedFallback == true)
      )
    end
  end
  states[state.spellID] = nil
  processPlayerCast(self, state.spellID, sourceTag or state.sourceTag or "resolver")
  return true
end

local function openResolverState(self, spellID, sourceTag, now)
  local states = getResolverStates(self)
  local previous = states[spellID]
  local offGCD = isSpellOffGlobalCooldown(spellID)
  local gcdEndAt = nil
  if not offGCD then
    gcdEndAt = getResolverGateEndAt(now)
  end
  local openDelta = math.abs((tonumber(now) or GetTime()) - (tonumber(previous and previous.attemptAt) or 0))
  if type(previous) == "table"
    and previous.status == "attempted"
    and tostring(previous.sourceTag or "") == tostring(sourceTag or "HOOK")
    and openDelta <= RESOLVER_DUPLICATE_OPEN_WINDOW
  then
    ns.Debug:Verbosef(
      "CastResolver attempt_reuse token=%d spellID=%d source=%s state=%s",
      tonumber(previous.attemptToken) or 0,
      tonumber(spellID) or 0,
      tostring(sourceTag or "HOOK"),
      tostring(previous.status or "unknown")
    )
    return previous
  end
  if type(previous) == "table"
    and previous.status == "attempted"
    and tostring(previous.sourceTag or "") == tostring(sourceTag or "HOOK")
    and gcdEndAt
  then
    ns.Debug:Verbosef(
      "CastResolver attempt_reuse token=%d spellID=%d source=%s state=%s until_gcd=%.2f",
      tonumber(previous.attemptToken) or 0,
      tonumber(spellID) or 0,
      tostring(sourceTag or "HOOK"),
      tostring(previous.status or "unknown"),
      math.max(0, gcdEndAt - (tonumber(now) or GetTime()))
    )
    return previous
  end
  if type(previous) == "table"
    and previous.status == "blocked"
    and tostring(previous.sourceTag or "") == tostring(sourceTag or "HOOK")
    and openDelta <= RESOLVER_BLOCKED_REUSE_WINDOW
  then
    ns.Debug:Verbosef(
      "CastResolver attempt_reuse token=%d spellID=%d source=%s state=%s",
      tonumber(previous.attemptToken) or 0,
      tonumber(spellID) or 0,
      tostring(sourceTag or "HOOK"),
      tostring(previous.status or "unknown")
    )
    return previous
  end
  if type(previous) == "table"
    and previous.status == "blocked"
    and tostring(previous.sourceTag or "") == tostring(sourceTag or "HOOK")
    and gcdEndAt
  then
    ns.Debug:Verbosef(
      "CastResolver attempt_reuse token=%d spellID=%d source=%s state=%s until_gcd=%.2f",
      tonumber(previous.attemptToken) or 0,
      tonumber(spellID) or 0,
      tostring(sourceTag or "HOOK"),
      tostring(previous.status or "unknown"),
      math.max(0, gcdEndAt - (tonumber(now) or GetTime()))
    )
    return previous
  end

  local token = nextResolverToken(self)
  if type(previous) == "table" then
    ns.Debug:Logf(
      "CastResolver attempt_supersede old=%d new=%d spellID=%d prev=%s",
      tonumber(previous.attemptToken) or 0,
      tonumber(token) or 0,
      tonumber(spellID) or 0,
      tostring(previous.status or "unknown")
    )
  end
  local state = {
    spellID = spellID,
    attemptAt = tonumber(now) or GetTime(),
    gcdEndAt = gcdEndAt,
    sourceTag = tostring(sourceTag or "HOOK"),
    restricted = ns.AuraAPI:IsSecretCooldownsRestricted(spellID),
    offGCD = offGCD,
    attemptToken = token,
    lastErrorAt = 0,
    lastConfirmAt = 0,
    status = "attempted",
    blockReason = nil,
    restrictedFallbackUsed = false,
  }
  states[spellID] = state
  ns.Debug:Logf(
    "CastResolver attempt_open token=%d spellID=%d source=%s restricted=%s offGCD=%s",
    tonumber(token) or 0,
    tonumber(spellID) or 0,
    tostring(sourceTag or "HOOK"),
    tostring(state.restricted == true),
    tostring(state.offGCD == true)
  )
  return state
end

local function queueCastAttempt(self, spellID, sourceTag)
  spellID = normalizeQueuedSpellID(spellID)
  if not spellID or spellID <= 0 then
    return
  end

  self:RefreshHookedTriggerSet()
  local tracked = self.hookedTriggerSet and self.hookedTriggerSet[spellID] == true
  local now = GetTime()
  local state = nil
  if tracked then
    local failGateUntilBySpell = self.castResolverFailGateUntilBySpell or {}
    local failGateUntil = tonumber(failGateUntilBySpell[spellID]) or 0
    local globalGateUntil = tonumber(self.castResolverGlobalGateUntil) or 0
    if globalGateUntil > now and not isSpellOffGlobalCooldown(spellID) then
      ns.Debug:Verbosef(
        "CastResolver attempt_suppressed spellID=%d source=%s reason=global_gate remaining=%.2f",
        tonumber(spellID) or 0,
        tostring(sourceTag or "HOOK"),
        math.max(0, globalGateUntil - now)
      )
      logResolverOutcome({
        attemptToken = 0,
        spellID = spellID,
        attemptAt = now,
      }, "cast suppressed by gcd gate", tostring(sourceTag or "HOOK"), now)
    elseif failGateUntil > now then
      ns.Debug:Verbosef(
        "CastResolver attempt_suppressed spellID=%d source=%s reason=fail_gate remaining=%.2f",
        tonumber(spellID) or 0,
        tostring(sourceTag or "HOOK"),
        math.max(0, failGateUntil - now)
      )
      logResolverOutcome({
        attemptToken = 0,
        spellID = spellID,
        attemptAt = now,
      }, "cast suppressed by fail gate", tostring(sourceTag or "HOOK"), now)
    else
      state = openResolverState(self, spellID, sourceTag, now)
    end
  end

  self.lastRawAttempt = {
    spellID = spellID,
    source = tostring(sourceTag or "HOOK"),
    tracked = tracked == true,
    at = now,
    attemptToken = state and state.attemptToken or nil,
  }
  ns.Debug:Throttled(
    "cast-attempt-raw-" .. tostring(spellID) .. "-" .. tostring(sourceTag or "HOOK"),
    0.25,
    "Cast attempt raw spellID=%d name=%s source=%s tracked=%s",
    spellID,
    tostring(getSpellDebugName(spellID)),
    tostring(sourceTag or "HOOK"),
    tostring(tracked)
  )
end

local function getRawGlobalCooldownData()
  if not GetSpellCooldown then
    return nil
  end
  local startTime, duration, enabled = GetSpellCooldown(61304)
  startTime = tonumber(startTime) or 0
  duration = tonumber(duration) or 0

  if enabled == false or enabled == 0 then
    return nil
  end
  if not ns.AuraAPI:IsSafeNumber(startTime) or not ns.AuraAPI:IsSafeNumber(duration) then
    return nil
  end
  if startTime <= 0 or duration <= 0.05 then
    return nil
  end
  return {
    startTime = startTime,
    duration = duration,
  }
end

isSpellOffGlobalCooldown = function(spellID)
  spellID = tonumber(spellID)
  if not spellID or spellID <= 0 then
    return false
  end
  local profileOverrides = ns.db and ns.db.offGCDSpellOverrides
  if type(profileOverrides) == "table" and profileOverrides[spellID] ~= nil then
    return profileOverrides[spellID] == true
  end
  return OFF_GCD_SPELLS[spellID] == true
end

getActiveGlobalCooldownEndAt = function(now)
  local gcdData = getRawGlobalCooldownData()
  if type(gcdData) ~= "table" then
    return nil
  end

  now = tonumber(now) or GetTime()
  local startTime = tonumber(gcdData.startTime) or 0
  local duration = tonumber(gcdData.duration) or 0
  local endAt = startTime + duration
  if startTime <= 0 or duration <= 0.05 then
    return nil
  end
  if now >= (endAt - RESOLVER_GCD_REUSE_MARGIN) then
    return nil
  end
  return endAt
end

getResolverGateEndAt = function(now)
  now = tonumber(now) or GetTime()
  local gateUntil = getActiveGlobalCooldownEndAt(now)
  if gateUntil and gateUntil > now then
    return gateUntil, false
  end
  return now + RESOLVER_GCD_FALLBACK_DURATION, true
end

local function isGlobalCooldownOnlyForSpell(spellCooldown, gcdData)
  if type(spellCooldown) ~= "table" then
    return false
  end
  if type(gcdData) ~= "table" then
    return false
  end

  local cdStart = tonumber(spellCooldown.startTime) or 0
  local cdDuration = tonumber(spellCooldown.duration) or 0
  local gcdStart = tonumber(gcdData.startTime) or 0
  local gcdDuration = tonumber(gcdData.duration) or 0

  if cdStart <= 0 or gcdStart <= 0 or cdDuration <= 0 or gcdDuration <= 0 then
    return false
  end

  -- If spell cooldown overlaps almost exactly with active GCD window,
  -- this is not a reliable "spell cast success" signal for this specific spell.
  local sameStart = math.abs(cdStart - gcdStart) <= 0.08
  local sameDuration = math.abs(cdDuration - gcdDuration) <= 0.08
  return sameStart and sameDuration
end

function E:EnsureFallbackPoller()
  if self.poller then
    return
  end
  self._nextPollAt = 0
  self.poller = C_Timer.NewTicker(0.15, function()
    if not ns.db then
      return
    end
    if not (ns.state and ns.state.runtimeEventsRegistered == true) then
      local triggered = self:PollRuleCastEdges()
      if triggered then
        return
      end
      local confirmed = self:ConfirmPendingCastAttempts()
      if confirmed then
        return
      end
    end
    local now = GetTime()
    local interval = InCombatLockdown() and 0.15 or 0.35
    if now < (self._nextPollAt or 0) then
      return
    end
    self._nextPollAt = now + interval
    self:RefreshAll()
  end)
end

function E:EnsureCastHooks()
  self:RefreshHookedTriggerSet()
  if self.castHooksInstalled then
    return
  end

  if type(CastSpellByID) == "function" then
    hooksecurefunc("CastSpellByID", function(spellID)
      queueCastAttempt(E, spellID, "HOOK_CastSpellByID")
    end)
  end

  if type(CastSpellByName) == "function" then
    hooksecurefunc("CastSpellByName", function(spellName)
      local spellID = ns.Utils and ns.Utils.ResolveSpellID and ns.Utils.ResolveSpellID(spellName) or nil
      if not spellID and ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
        spellID = ns.SpellCatalog:ResolveNameToSpellID(spellName)
      end
      queueCastAttempt(E, spellID, "HOOK_CastSpellByName")
    end)
  end

  if type(UseAction) == "function" and type(GetActionInfo) == "function" then
    hooksecurefunc("UseAction", function(slot)
      local actionType, id = GetActionInfo(slot)
      if actionType == "spell" then
        queueCastAttempt(E, id, "HOOK_UseAction")
      end
    end)
  end

  if C_Spell and type(C_Spell.CastSpell) == "function" then
    hooksecurefunc(C_Spell, "CastSpell", function(spellIdentifier)
      queueCastAttempt(E, spellIdentifier, "HOOK_C_Spell.CastSpell")
    end)
  end

  self.castHooksInstalled = true
  ns.Debug:Log("Cast hooks installed (cast resolver active).")
end

function E:BuildRowsForUnit(unit)
  local rowsByGroup = {}
  local list = ns.db.watchlist[unit] or {}
  local rulesOnlyMode = ns.db and ns.db.options and ns.db.options.rulesOnlyMode == true
  local playerClassToken = getPlayerClassToken()
  local playerSpecID = getPlayerSpecID()

  for _, item in ipairs(list) do
    if isAuraLoadAllowed(item, playerClassToken, playerSpecID) then
      local directAuraTracking = unit ~= "player"
      local selectedInUnlock = isSelectedAuraInUnlock(unit, item)
      local effectiveGroupID = resolveDisplayGroupID(unit, item)
      if selectedInUnlock then
        effectiveGroupID = buildIndependentGroupID(unit, item)
        ensureIndependentGroup(effectiveGroupID, tostring(item and item.groupID or "important_procs"), item)
      end
      local aura = nil
      if directAuraTracking or not rulesOnlyMode then
        aura = ns.AuraAPI:GetAuraBySpellID(unit, item.spellID)
      end

      if ns.ProcRules and ns.ProcRules.GetSyntheticAura then
        local synthetic = ns.ProcRules:GetSyntheticAura(item.spellID)
        if synthetic then
          if not aura then
            aura = synthetic
          else
            local auraExpirationTime, auraDuration = ns.AuraAPI:GetAuraTiming(aura)
            local auraApplications = ns.AuraAPI:GetAuraApplications(aura)
            local auraFromPlayer = ns.AuraAPI:IsFromPlayerOrPet(aura)
            if not auraFromPlayer and not auraExpirationTime and not auraDuration and auraApplications <= 0 then
              aura = synthetic
            end
          end
        end
      end
      local cooldown = nil
      local cooldownRestricted = false
      if (not directAuraTracking) and (not rulesOnlyMode) and (not aura) and unit == "player" then
        cooldownRestricted = ns.AuraAPI:IsSecretCooldownsRestricted(item.spellID)
        if cooldownRestricted then
          cooldown = getEstimatedCooldown(item.spellID)
          if cooldown then
            ns.Debug:Throttled("cd-estimate-" .. tostring(item.spellID), 1.5, "Estimated cooldown row spellID=%d remaining=%.1f", tonumber(item.spellID) or 0, math.max(0, (cooldown.expirationTime or 0) - GetTime()))
          else
            ns.Debug:Throttled("cd-restricted-" .. tostring(item.spellID), 4.0, "SecretCooldowns active for spellID=%d: cooldown hidden by API in this context.", tonumber(item.spellID) or 0)
          end
        else
          cooldown = ns.AuraAPI:GetSpellCooldownData(item.spellID)
          if cooldown then
            learnCooldown(item.spellID, cooldown.duration)
            clearEstimatedCooldown(item.spellID)
            local remaining = math.max(0, (cooldown.expirationTime or 0) - GetTime())
            ns.Debug:Throttled("cd-hit-" .. tostring(item.spellID), 1.5, "Cooldown row spellID=%d remaining=%.1f", tonumber(item.spellID) or 0, remaining)
          else
            ns.Debug:Throttled("cd-miss-" .. tostring(item.spellID), 4.0, "No cooldown data spellID=%d (possible aura/proc ID).", tonumber(item.spellID) or 0)
          end
        end
      end

      local include = aura ~= nil or cooldown ~= nil
      if include and item.onlyMine then
        include = aura and ns.AuraAPI:IsFromPlayerOrPet(aura) or true
      end
      if include and item.resourceConditionEnabled == true and ns.PlayerResource then
        include = ns.PlayerResource:MatchesRange(item.resourceMinPct, item.resourceMaxPct)
      end

      if include then
        local canCompute = aura and ns.AuraAPI:CanComputeRemaining(aura) or (cooldown and cooldown.canCompute == true)
        local fallbackIcon = ns.AuraAPI:SelectBestTexture(aura and aura.icon or nil, ns.AuraAPI:GetSpellTexture(item.spellID), 136243)
        local auraExpirationTime, auraDuration = ns.AuraAPI:GetAuraTiming(aura)
        local applications = ns.AuraAPI:GetAuraApplications(aura)
        local expirationTime = auraExpirationTime or (cooldown and cooldown.expirationTime)
        local duration = auraDuration or (cooldown and cooldown.duration)
        local sourceLabel = aura and ns.AuraAPI:GetSourceLabel(aura) or ""
        rowsByGroup[effectiveGroupID] = rowsByGroup[effectiveGroupID] or {}
        rowsByGroup[effectiveGroupID][#rowsByGroup[effectiveGroupID] + 1] = {
          unit = unit,
          groupID = effectiveGroupID,
          spellID = item.spellID,
          auraInstanceID = ns.AuraAPI:GetAuraInstanceID(aura),
          icon = ns.AuraAPI:GetDisplayTextureForItem(item, aura),
          fallbackIcon = fallbackIcon,
          applications = applications,
          expirationTime = expirationTime,
          duration = duration,
          sourceLabel = sourceLabel,
          canCompute = canCompute,
          alert = item.alert ~= false,
          displayName = item.displayName or "",
          customText = item.customText or "",
          timerVisual = item.timerVisual or "icon",
          barTexture = item.barTexture or "",
          timerAnchor = item.timerAnchor or "BOTTOM",
          timerOffsetX = tonumber(item.timerOffsetX) or 0,
          timerOffsetY = tonumber(item.timerOffsetY) or -1,
          customTextAnchor = item.customTextAnchor or "TOP",
          customTextOffsetX = tonumber(item.customTextOffsetX) or 0,
          customTextOffsetY = tonumber(item.customTextOffsetY) or 2,
          resourceConditionEnabled = item.resourceConditionEnabled == true,
          resourceMinPct = tonumber(item.resourceMinPct) or 0,
          resourceMaxPct = tonumber(item.resourceMaxPct) or 100,
          lowTimeThreshold = tonumber(item.lowTimeThreshold) or 0,
          soundOnGain = item.soundOnGain or "default",
          soundOnLow = item.soundOnLow or "default",
          soundOnExpire = item.soundOnExpire or "default",
          isPlaceholder = false,
        }
      elseif selectedInUnlock or ns.TestMode:IsEnabled() or (ns.db and ns.db.locked == false) then
        local fake = ns.TestMode:BuildPlaceholder(item, unit)
        fake.groupID = effectiveGroupID
        fake.displayName = item.displayName or ""
        fake.customText = item.customText or ""
        fake.timerVisual = item.timerVisual or "icon"
        fake.barTexture = item.barTexture or ""
        fake.timerAnchor = item.timerAnchor or "BOTTOM"
        fake.timerOffsetX = tonumber(item.timerOffsetX) or 0
        fake.timerOffsetY = tonumber(item.timerOffsetY) or -1
        fake.customTextAnchor = item.customTextAnchor or "TOP"
        fake.customTextOffsetX = tonumber(item.customTextOffsetX) or 0
        fake.customTextOffsetY = tonumber(item.customTextOffsetY) or 2
        fake.resourceConditionEnabled = item.resourceConditionEnabled == true
        fake.resourceMinPct = tonumber(item.resourceMinPct) or 0
        fake.resourceMaxPct = tonumber(item.resourceMaxPct) or 100
        fake.lowTimeThreshold = tonumber(item.lowTimeThreshold) or 0
        fake.soundOnGain = item.soundOnGain or "default"
        fake.soundOnLow = item.soundOnLow or "default"
        fake.soundOnExpire = item.soundOnExpire or "default"
        fake.iconMode = item.iconMode or "spell"
        fake.customTexture = item.customTexture or ""
        fake.icon = ns.AuraAPI:GetDisplayTextureForItem(item, nil)
        fake.fallbackIcon = ns.AuraAPI:SelectBestTexture(ns.AuraAPI:GetSpellTexture(item.spellID), 136243)
        fake.isPlaceholder = true
        rowsByGroup[effectiveGroupID] = rowsByGroup[effectiveGroupID] or {}
        rowsByGroup[effectiveGroupID][#rowsByGroup[effectiveGroupID] + 1] = fake
      end
    end
  end
  return rowsByGroup
end

function E:RefreshAll()
  if not ns.db then
    return
  end

  local activeByGroup = {}
  for unit, enabled in pairs(ns.db.units) do
    if enabled then
      local rowsForUnit = self:BuildRowsForUnit(unit)
      mergeGroupRows(activeByGroup, rowsForUnit)
    end
  end

  local restrictionActive = ns.AuraAPI:IsRestrictionActive()
  local cooldownRestricted = ns.AuraAPI:IsSecretCooldownsRestricted()
  ns.state.restrictionActive = restrictionActive
  ns.state.cooldownRestrictionActive = cooldownRestricted
  ns.GroupManager:SetRestrictionState(restrictionActive)
  ns.GroupManager:Render(activeByGroup)

  if ns.Debug and ns.Debug.IsEnabled and ns.Debug:IsEnabled() then
    local groupCount = 0
    local rowCount = 0
    for _, rows in pairs(activeByGroup) do
      groupCount = groupCount + 1
      rowCount = rowCount + #rows
    end
    local now = GetTime()
    local summaryKey = string.format(
      "%d|%d|%s|%s",
      groupCount,
      rowCount,
      tostring(restrictionActive),
      tostring(cooldownRestricted)
    )
    local changed = summaryKey ~= (self.lastRefreshSummary and self.lastRefreshSummary.key or "")
    local heartbeatDue = (now - (self.lastRefreshSummary and self.lastRefreshSummary.at or 0)) >= 6.0
    if changed or heartbeatDue then
      ns.Debug:Logf(
        "RefreshAll done. groups=%d rows=%d restricted=%s cdRestricted=%s",
        groupCount,
        rowCount,
        tostring(restrictionActive),
        tostring(cooldownRestricted)
      )
      self.lastRefreshSummary = {
        key = summaryKey,
        at = now,
      }
    end
  end
end

function E:PLAYER_LOGIN()
  ns.Debug:Log("Event PLAYER_LOGIN")
  ns:Initialize()
  ns:RegisterRuntimeEvents()
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  ns.GroupManager:EnsureTicker()
  self:EnsureCastHooks()
  self:EnsureFallbackPoller()

  self:RefreshAll()

  if ns.ProfileManager:IsFirstRun() then
    ns.ConfigUI:ShowFirstRun()
  end
end

function E:PLAYER_ENTERING_WORLD()
  ns.Debug:Verbose("Event PLAYER_ENTERING_WORLD")
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  self:RefreshAll()
end

function E:PLAYER_TARGET_CHANGED()
  ns.Debug:Verbose("Event PLAYER_TARGET_CHANGED")
  if ns.Registry:UnitEnabled("target") then
    self:RefreshAll()
  end
end

function E:PLAYER_FOCUS_CHANGED()
  ns.Debug:Verbose("Event PLAYER_FOCUS_CHANGED")
  if ns.Registry:UnitEnabled("focus") then
    self:RefreshAll()
  end
end

function E:UNIT_PET(unit)
  ns.Debug:Verbosef("Event UNIT_PET unit=%s", tostring(unit))
  if unit == "player" and ns.Registry:UnitEnabled("pet") then
    self:RefreshAll()
  end
end

function E:PLAYER_REGEN_ENABLED()
  if ns.Dragger and ns.Dragger.ApplyPendingPositions then
    ns.Dragger:ApplyPendingPositions()
  end
  if not ns.db.locked and ns.GroupManager then
    ns.GroupManager:RefreshDragState()
  end
  self:RefreshAll()
end

function E:PLAYER_REGEN_DISABLED()
  self:RefreshAll()
end

function E:PLAYER_SPECIALIZATION_CHANGED(unit)
  ns.Debug:Logf("Event PLAYER_SPECIALIZATION_CHANGED unit=%s", tostring(unit))
  if unit and unit ~= "player" then
    return
  end
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  ns.ProfileManager:RefreshActiveProfile()
  ns:RebuildWatchIndex()
  self:RefreshAll()
end

function E:PLAYER_TALENT_UPDATE()
  ns.Debug:Verbose("Event PLAYER_TALENT_UPDATE")
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  self:RefreshAll()
end

function E:TRAIT_CONFIG_UPDATED()
  ns.Debug:Verbose("Event TRAIT_CONFIG_UPDATED")
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  self:RefreshAll()
end

function E:ADDON_RESTRICTION_STATE_CHANGED()
  ns.Debug:Logf(
    "Event ADDON_RESTRICTION_STATE_CHANGED auraRestricted=%s cdRestricted=%s",
    tostring(ns.AuraAPI:IsRestrictionActive()),
    tostring(ns.AuraAPI:IsSecretCooldownsRestricted())
  )
  self:RefreshAll()
end

function E:UNIT_AURA(unit, updateInfo)
  ns.Debug:Verbosef("Event UNIT_AURA unit=%s full=%s", tostring(unit), tostring(updateInfo and updateInfo.isFullUpdate))
  if not ns.Registry:UnitEnabled(unit) then
    return
  end
  if not ns.Registry:TouchesWatchlist(unit, updateInfo) then
    return
  end
  self:RefreshAll()
end

function E:UI_ERROR_MESSAGE(msgType, message)
  local now = GetTime()
  local raw = self.lastRawAttempt
  local rawSpellID = tonumber(raw and raw.spellID)
  local rawToken = tonumber(raw and raw.attemptToken)
  local affectsTrackedResolver = false

  if raw and raw.tracked == true and rawSpellID and rawToken and (now - (tonumber(raw.at) or 0)) <= RESOLVER_ATTRIBUTION_WINDOW then
    local state = self.castResolverStates and self.castResolverStates[rawSpellID] or nil
    if state and tonumber(state.attemptToken) == rawToken then
      affectsTrackedResolver = blockResolverState(self, state, "ui_error", now) == true
    end
  end

  ns.Debug:Logf(
    "Event UI_ERROR_MESSAGE type=%s affectsTracked=%s rawSpell=%s rawTracked=%s msg=%s",
    tostring(msgType),
    tostring(affectsTrackedResolver),
    tostring(raw and raw.spellID or "nil"),
    tostring(raw and raw.tracked == true),
    tostring(message)
  )
end

local function handleResourceEvent(self, unit)
  if unit and unit ~= "player" then
    return
  end
  if ns.Registry and ns.Registry.HasResourceConditions and ns.Registry:HasResourceConditions() then
    self:RefreshAll()
  end
end

function E:UNIT_POWER_UPDATE(unit)
  ns.Debug:Verbosef("Event UNIT_POWER_UPDATE unit=%s", tostring(unit))
  handleResourceEvent(self, unit)
end

function E:UNIT_MAXPOWER(unit)
  ns.Debug:Verbosef("Event UNIT_MAXPOWER unit=%s", tostring(unit))
  handleResourceEvent(self, unit)
end

function E:UNIT_DISPLAYPOWER(unit)
  ns.Debug:Verbosef("Event UNIT_DISPLAYPOWER unit=%s", tostring(unit))
  handleResourceEvent(self, unit)
end

local function handleCooldownEvent(self)
  if ns.Registry and ns.Registry:UnitEnabled("player") then
    local now = GetTime()
    if (now - (E.lastCooldownRefresh or 0)) < 0.05 then
      return
    end
    E.lastCooldownRefresh = now
    self:RefreshAll()
  end
end

function E:PollRuleCastEdges()
  if ns.state and ns.state.runtimeEventsRegistered == true then
    return false
  end

  local states = self.castResolverStates
  if type(states) ~= "table" or not next(states) then
    return false
  end

  local now = GetTime()
  local triggered = false
  local gcdData = getRawGlobalCooldownData()

  for spellID, state in pairs(states) do
    local age = now - (tonumber(state and state.attemptAt) or 0)
    if type(state) ~= "table" or age > RESOLVER_MAX_AGE then
      expireResolverState(self, state, "timeout", now)
    elseif state.status == "attempted" then
      local cd = ns.AuraAPI:GetSpellCooldownData(spellID)
      local cdStart = cd and tonumber(cd.startTime) or 0
      local cdNearAttempt = cdStart > 0 and cdStart >= ((state.attemptAt or 0) - 0.08) and cdStart <= (now + 0.05)
      if cdNearAttempt and not isGlobalCooldownOnlyForSpell(cd, gcdData) then
        if confirmResolverState(self, state, "HOOK_CD_CONFIRM", now) then
          triggered = true
        end
      else
        local gcdStart = gcdData and tonumber(gcdData.startTime) or 0
        local gcdNearAttempt = gcdStart > 0 and gcdStart >= ((state.attemptAt or 0) - 0.08) and gcdStart <= (now + 0.05)
        local blockedForAttempt = tonumber(state.lastErrorAt or 0) >= (state.attemptAt or 0)
        if gcdNearAttempt and state.restricted ~= true and state.offGCD ~= true and not blockedForAttempt then
          if confirmResolverState(self, state, "HOOK_GCD_CONFIRM", now) then
            triggered = true
          end
        end
      end
    end
  end

  return triggered
end

function E:ConfirmPendingCastAttempts()
  local states = self.castResolverStates
  if type(states) ~= "table" or not next(states) then
    return false
  end

  local now = GetTime()
  local confirmedAny = false

  for spellID, state in pairs(states) do
    local age = now - (tonumber(state and state.attemptAt) or 0)
    if type(state) ~= "table" or age > RESOLVER_MAX_AGE then
      expireResolverState(self, state, "timeout", now)
    elseif state.status == "blocked" then
      -- Blocked attempts remain invalid until superseded or expired.
    elseif state.status == "attempted" then
      local blockedForAttempt = tonumber(state.lastErrorAt or 0) >= (state.attemptAt or 0)
      if state.restricted == true
        and state.restrictedFallbackUsed ~= true
        and age >= RESOLVER_RESTRICTED_MIN_AGE
        and age <= RESOLVER_RESTRICTED_MAX_AGE
        and not blockedForAttempt
      then
        state.restrictedFallbackUsed = true
        if confirmResolverState(self, state, "HOOK_RESTRICTED_NOERROR", now) then
          confirmedAny = true
        end
      end
    end
  end

  return confirmedAny
end

processPlayerCast = function(self, spellID, sourceTag)
  spellID = tonumber(spellID)
  if not spellID then
    return
  end

  local now = GetTime()
  local last = E.lastProcessedCast[spellID] or 0
  if (now - last) < 0.05 then
    return
  end
  E.lastProcessedCast[spellID] = now

  local ruleCount = 0
  if ns.ProcRules and ns.ProcRules.byIfEventSpell and ns.ProcRules.byIfEventSpell[spellID] then
    ruleCount = #ns.ProcRules.byIfEventSpell[spellID]
  end
  ns.Debug:Throttled(
    "cast-confirm-" .. tostring(spellID),
    0.12,
    "Cast confirm spellID=%d name=%s source=%s rules=%d",
    spellID,
    tostring(getSpellDebugName(spellID)),
    tostring(sourceTag or "cast"),
    ruleCount
  )

  local procChanged = false
  if ns.ProcRules and ns.ProcRules.OnPlayerSpellCast then
    procChanged = ns.ProcRules:OnPlayerSpellCast(spellID) == true
  end

  local tracked = ns.Registry and ns.Registry.index and ns.Registry.index.player and ns.Registry.index.player[spellID] == true
  if tracked and ns.AuraAPI:IsSecretCooldownsRestricted(spellID) then
    local estimated = startEstimatedCooldown(spellID)
    if estimated then
      ns.Debug:Throttled(
        "cd-estimate-start-" .. tostring(spellID),
        1.0,
        "Start estimated cooldown spellID=%d duration=%.1f source=%s",
        spellID,
        tonumber(estimated.duration) or 0,
        tostring(sourceTag or "cast")
      )
    end
  end

  if procChanged then
    ns.Debug:Throttled(
      "proc-cast-" .. tostring(spellID),
      0.3,
      "Proc state changed spellID=%d source=%s",
      spellID,
      tostring(sourceTag or "cast")
    )
    self:RefreshAll()
    return
  end

  handleCooldownEvent(self)
end

function E:SPELL_UPDATE_COOLDOWN()
  ns.Debug:Verbose("Event SPELL_UPDATE_COOLDOWN")
  handleCooldownEvent(self)
end

function E:SPELL_UPDATE_CHARGES()
  ns.Debug:Verbose("Event SPELL_UPDATE_CHARGES")
  handleCooldownEvent(self)
end

function E:ACTIONBAR_UPDATE_COOLDOWN()
  ns.Debug:Verbose("Event ACTIONBAR_UPDATE_COOLDOWN")
  handleCooldownEvent(self)
end

function E:SPELL_UPDATE_USABLE()
  ns.Debug:Verbose("Event SPELL_UPDATE_USABLE")
  handleCooldownEvent(self)
end

function E:UNIT_SPELLCAST_SUCCEEDED(unit, _, spellID)
  ns.Debug:Verbosef("Event UNIT_SPELLCAST_SUCCEEDED unit=%s spellID=%s", tostring(unit), tostring(spellID))
  if unit == "player" then
    processPlayerCast(self, spellID, "UNIT_SPELLCAST_SUCCEEDED")
  end
end

function E:COMBAT_LOG_EVENT_UNFILTERED()
  local _, subEvent, _, sourceGUID, _, _, _, _, _, _, _, spellID = CombatLogGetCurrentEventInfo()
  if subEvent ~= "SPELL_CAST_SUCCESS" then
    return
  end
  if sourceGUID ~= UnitGUID("player") then
    return
  end
  processPlayerCast(self, spellID, "COMBAT_LOG_EVENT_UNFILTERED")
end


























