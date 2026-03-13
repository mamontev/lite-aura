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
E.lastRawAttempts = E.lastRawAttempts or {}
E.lastRefreshSummary = E.lastRefreshSummary or { key = "", at = 0 }
E.syntheticTargetAuras = E.syntheticTargetAuras or {}

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
local RESOLVER_GCD_REUSE_MARGIN = 0.03
local RESOLVER_GCD_FALLBACK_DURATION = 0.75
local RESOLVER_FAIL_GATE_DURATION = 0.16
local RESOLVER_UI_ERROR_WINDOW = 0.28
local RESOLVER_MAX_OPEN_ATTEMPTS_PER_SPELL = 3
local RESOLVER_CONFIRM_SCORE = 0.70
local RESOLVER_REJECT_SCORE = -0.55
local RESOLVER_SCORE_RAW_HOOK = 0.28
local RESOLVER_SCORE_RUNTIME_SUCCESS = 1.15
local RESOLVER_SCORE_RUNTIME_FAIL = -1.25
local RESOLVER_SCORE_CD_EDGE = 0.72
local RESOLVER_SCORE_GCD_EDGE = 0.42
local RESOLVER_SCORE_RESTRICTED_QUIET = 0.44

-- Conservative off-GCD overrides. We can expand this list as we validate
-- concrete spells in logs or from curated references.
local OFF_GCD_SPELLS = {
  [2565] = true,   -- Shield Block
  [23920] = true,  -- Spell Reflection
}

-- Safe synthetic target-debuff triggers for cases where Blizzard's target aura APIs
-- return no readable data in combat. These spellIDs represent confirmed player casts
-- that are known to apply the tracked debuff to the current target.
local SYNTHETIC_TARGET_TRIGGER_MAP = {
  [6343] = { [388539] = true },    -- Thunder Clap -> Rend
  [435222] = { [388539] = true },  -- Thunder Blast -> Rend
}

local SYNTHETIC_TARGET_SLOT = "__current_target__"

local function normalizeTrackingMode(item, unit)
  local mode = tostring(item and item.trackingMode or ""):lower()
  if tostring(unit or "") == "target" and mode == "estimated" then
    return "estimated"
  end
  return "confirmed"
end

local function parseSpellIDList(value)
  local out = {}
  local seen = {}
  if type(value) == "table" then
    for i = 1, #value do
      local n = tonumber(value[i])
      if n and n > 0 and not seen[n] then
        seen[n] = true
        out[#out + 1] = n
      end
    end
    return out
  end

  local text = tostring(value or "")
  for token in text:gmatch("[^,%s;]+") do
    local n = tonumber(token)
    if n and n > 0 and not seen[n] then
      seen[n] = true
      out[#out + 1] = n
    end
  end
  return out
end

local function isTrackedByCastList(sourceSpellID, castSpellIDs)
  sourceSpellID = tonumber(sourceSpellID)
  if not sourceSpellID then
    return false
  end

  local spellIDs = parseSpellIDList(castSpellIDs)
  for i = 1, #spellIDs do
    if spellIDs[i] == sourceSpellID then
      return true
    end
  end
  return false
end

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

local function resolveDisplayGroupID(unit, item)
  local sourceGroupID = tostring(item and item.groupID or "")
  local hasSharedGroup = sanitizeGroupToken(sourceGroupID) ~= ""
  if item and hasSharedGroup then
    return sanitizeGroupToken(sourceGroupID)
  end

  return buildIndependentGroupID(unit, item)
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

local function isConfigPreviewVisible()
  local ui = ns.UIV2
  return ui and ui.ConfigFrame and ui.ConfigFrame.IsShown and ui.ConfigFrame:IsShown()
end

local function isSelectedAuraPreview(unit, item)
  if not (ns.state and ns.state.selectedAura and isConfigPreviewVisible()) then
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

local function getSelectedAuraPreviewItem(unit, item)
  if not isSelectedAuraPreview(unit, item) then
    return nil
  end
  local previewItem = ns.state and ns.state.selectedAuraPreviewItem or nil
  if type(previewItem) ~= "table" then
    return nil
  end
  return previewItem
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

local function isAuraLoadAllowed(item, playerClassToken, playerSpecID, playerInCombat)
  if type(item) ~= "table" then
    return true
  end
  if item.inCombatOnly == true and playerInCombat ~= true then
    return false
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
  local targetRevision = 0
  local targetList = ns.db and ns.db.watchlist and ns.db.watchlist.target
  if type(targetList) == "table" then
    for i = 1, #targetList do
      local item = targetList[i]
      if normalizeTrackingMode(item, "target") == "estimated" then
        targetRevision = targetRevision
          + (tonumber(item and item.spellID) or 0)
          + math.floor((tonumber(item and item.estimatedDuration) or 0) * 10)
        local castIDs = parseSpellIDList(item and item.castSpellIDs)
        for j = 1, #castIDs do
          targetRevision = targetRevision + castIDs[j]
        end
      end
    end
  end

  local combinedRevision = tostring(revision) .. ":" .. tostring(targetRevision)
  if self.hookedTriggerRevision == combinedRevision and self.hookedTriggerSet then
    return
  end

  self.hookedTriggerSet = self.hookedTriggerSet or {}
  for k in pairs(self.hookedTriggerSet) do
    self.hookedTriggerSet[k] = nil
  end

  if ns.ProcRules and ns.ProcRules.GetTriggerSpellIDs then
    local ids = ns.ProcRules:GetTriggerSpellIDs()
    for i = 1, #ids do
      local spellID = tonumber(ids[i])
      if spellID and spellID > 0 then
        self.hookedTriggerSet[spellID] = true
      end
    end
  end

  if type(targetList) == "table" then
    for i = 1, #targetList do
      local item = targetList[i]
      if normalizeTrackingMode(item, "target") == "estimated" then
        local castIDs = parseSpellIDList(item.castSpellIDs)
        for j = 1, #castIDs do
          self.hookedTriggerSet[castIDs[j]] = true
        end
      end
    end
  end

  self.hookedTriggerRevision = combinedRevision
end

local function nextResolverToken(self)
  self.castResolverTokenCounter = (tonumber(self.castResolverTokenCounter) or 0) + 1
  return self.castResolverTokenCounter
end

local function getResolverStates(self)
  self.castResolverStates = self.castResolverStates or {}
  return self.castResolverStates
end

local function getAttemptList(self, spellID)
  local states = getResolverStates(self)
  states[spellID] = states[spellID] or {}
  return states[spellID]
end

local function removeAttemptFromList(list, index)
  if type(list) ~= "table" then
    return
  end
  table.remove(list, index)
end

local function cleanupAttemptLists(self)
  local states = getResolverStates(self)
  for spellID, attempts in pairs(states) do
    if type(attempts) ~= "table" or #attempts == 0 then
      states[spellID] = nil
    end
  end
end

local function recordRawAttempt(self, attempt, now)
  self.lastRawAttempt = {
    spellID = attempt and attempt.spellID or nil,
    source = tostring(attempt and attempt.sourceTag or "HOOK"),
    tracked = attempt ~= nil,
    at = now,
    attemptToken = attempt and attempt.attemptToken or nil,
  }

  self.lastRawAttempts = self.lastRawAttempts or {}
  self.lastRawAttempts[#self.lastRawAttempts + 1] = {
    spellID = attempt and attempt.spellID or nil,
    at = now,
    attemptToken = attempt and attempt.attemptToken or nil,
  }

  for i = #self.lastRawAttempts, 1, -1 do
    local row = self.lastRawAttempts[i]
    if type(row) ~= "table" or (now - (tonumber(row.at) or 0)) > RESOLVER_UI_ERROR_WINDOW then
      table.remove(self.lastRawAttempts, i)
    end
  end
end

local function getPendingAttemptByToken(self, spellID, attemptToken)
  spellID = tonumber(spellID)
  attemptToken = tonumber(attemptToken)
  if not spellID or not attemptToken then
    return nil
  end
  local attempts = getResolverStates(self)[spellID]
  if type(attempts) ~= "table" then
    return nil
  end
  for i = #attempts, 1, -1 do
    local attempt = attempts[i]
    if type(attempt) == "table"
      and attempt.status == "attempted"
      and tonumber(attempt.attemptToken) == attemptToken
    then
      return attempt, attempts, i
    end
  end
  return nil
end

local function getLatestPendingAttempt(self, spellID, now, maxAge)
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  local attempts = getResolverStates(self)[spellID]
  if type(attempts) ~= "table" then
    return nil
  end
  now = tonumber(now) or GetTime()
  maxAge = tonumber(maxAge) or RESOLVER_MAX_AGE
  for i = #attempts, 1, -1 do
    local attempt = attempts[i]
    if type(attempt) == "table" and attempt.status == "attempted" then
      local age = now - (tonumber(attempt.attemptAt) or 0)
      if age >= 0 and age <= maxAge then
        return attempt, attempts, i
      end
    end
  end
  return nil
end

local expireResolverState
local blockResolverState
local confirmResolverState
local applyConfirmedSyntheticTargetAuras
local logResolverOutcome
local processPlayerCast

local function addAttemptSignal(attempt, kind, weight, now, detail)
  if type(attempt) ~= "table" or attempt.status ~= "attempted" then
    return false
  end
  attempt.signals = attempt.signals or {}
  local key = tostring(kind or "")
  if attempt.signals[key] == true then
    return false
  end
  attempt.signals[key] = true
  attempt.score = (tonumber(attempt.score) or 0) + (tonumber(weight) or 0)
  attempt.lastSignalAt = tonumber(now) or GetTime()
  ns.Debug:Verbosef(
    "CastResolver signal token=%d spellID=%d kind=%s score=%.2f detail=%s",
    tonumber(attempt.attemptToken) or 0,
    tonumber(attempt.spellID) or 0,
    key,
    tonumber(attempt.score) or 0,
    tostring(detail or "none")
  )
  return true
end

local function shouldRejectAttempt(state)
  return type(state) == "table" and tonumber(state.score) and tonumber(state.score) <= RESOLVER_REJECT_SCORE
end

local function shouldConfirmAttempt(state)
  return type(state) == "table" and tonumber(state.score) and tonumber(state.score) >= RESOLVER_CONFIRM_SCORE
end

local function applyPositiveAttemptSignal(self, state, signalKind, weight, sourceTag, now, detail)
  if addAttemptSignal(state, signalKind, weight, now, detail) and shouldConfirmAttempt(state) then
    return confirmResolverState(self, state, sourceTag, now)
  end
  return false
end

expireResolverState = function(self, state, reason, now)
  if type(state) ~= "table" then
    return
  end
  local attempts = getResolverStates(self)[state.spellID]
  if type(attempts) ~= "table" then
    return
  end
  for i = #attempts, 1, -1 do
    if attempts[i] == state then
      ns.Debug:Logf(
        "CastResolver attempt_expire token=%d spellID=%d reason=%s age=%.2f score=%.2f",
        tonumber(state.attemptToken) or 0,
        tonumber(state.spellID) or 0,
        tostring(reason or "expired"),
        math.max(0, (tonumber(now) or GetTime()) - (tonumber(state.attemptAt) or 0)),
        tonumber(state.score) or 0
      )
      logResolverOutcome(state, "cast expired unresolved", tostring(reason or "expired"), now)
      removeAttemptFromList(attempts, i)
      if #attempts == 0 then
        getResolverStates(self)[state.spellID] = nil
      end
      return
    end
  end
end

blockResolverState = function(self, state, reason, now)
  if type(state) ~= "table" or state.status ~= "attempted" then
    return false
  end
  local attempts = getResolverStates(self)[state.spellID]
  if type(attempts) ~= "table" then
    return false
  end
  state.status = "blocked"
  state.lastErrorAt = tonumber(now) or GetTime()
  state.blockReason = tostring(reason or "ui_error")
  addAttemptSignal(state, "runtime_fail", RESOLVER_SCORE_RUNTIME_FAIL, now, state.blockReason)
  ns.Debug:Logf(
    "CastResolver attempt_block token=%d spellID=%d reason=%s age=%.2f score=%.2f",
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(state.blockReason),
    math.max(0, (tonumber(state.lastErrorAt) or 0) - (tonumber(state.attemptAt) or 0)),
    tonumber(state.score) or 0
  )
  logResolverOutcome(state, "cast failed by game", tostring(state.blockReason), now)
  self.castResolverFailGateUntilBySpell = self.castResolverFailGateUntilBySpell or {}
  self.castResolverFailGateUntilBySpell[state.spellID] = (tonumber(now) or GetTime()) + RESOLVER_FAIL_GATE_DURATION
  expireResolverState(self, state, "blocked:" .. tostring(state.blockReason), now)
  return true
end

confirmResolverState = function(self, state, sourceTag, now)
  if type(state) ~= "table" or state.status ~= "attempted" then
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
    "CastResolver attempt_confirm token=%d spellID=%d via=%s age=%.2f restricted=%s score=%.2f",
    tonumber(state.attemptToken) or 0,
    tonumber(state.spellID) or 0,
    tostring(sourceTag or state.sourceTag or "resolver"),
    math.max(0, now - (tonumber(state.attemptAt) or 0)),
    tostring(state.restricted == true),
    tonumber(state.score) or 0
  )
  logResolverOutcome(state, "cast confirmed", tostring(sourceTag or state.sourceTag or "resolver"), now)
  expireResolverState(self, state, "confirmed", now)
  processPlayerCast(self, state.spellID, sourceTag or state.sourceTag or "resolver")
  applyConfirmedSyntheticTargetAuras(self, state.spellID, sourceTag or state.sourceTag or "resolver")
  return true
end

local function openResolverState(self, spellID, sourceTag, now)
  local attempts = getAttemptList(self, spellID)
  now = tonumber(now) or GetTime()
  for i = #attempts, 1, -1 do
    local previous = attempts[i]
    local openDelta = math.abs(now - (tonumber(previous and previous.attemptAt) or 0))
    if type(previous) == "table"
      and previous.status == "attempted"
      and tostring(previous.sourceTag or "") == tostring(sourceTag or "HOOK")
      and openDelta <= RESOLVER_DUPLICATE_OPEN_WINDOW
    then
      addAttemptSignal(previous, "raw_hook_refresh", 0, now, sourceTag)
      return previous
    end
  end

  while #attempts >= RESOLVER_MAX_OPEN_ATTEMPTS_PER_SPELL do
    expireResolverState(self, attempts[1], "queue_trim", now)
    attempts = getAttemptList(self, spellID)
  end

  local token = nextResolverToken(self)
  local state = {
    spellID = spellID,
    attemptAt = now,
    sourceTag = tostring(sourceTag or "HOOK"),
    restricted = ns.AuraAPI:IsSecretCooldownsRestricted(spellID),
    offGCD = isSpellOffGlobalCooldown(spellID),
    attemptToken = token,
    lastErrorAt = 0,
    lastConfirmAt = 0,
    status = "attempted",
    blockReason = nil,
    restrictedFallbackUsed = false,
    score = 0,
    signals = {},
  }
  attempts[#attempts + 1] = state
  addAttemptSignal(state, "raw_hook", RESOLVER_SCORE_RAW_HOOK, now, sourceTag)
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
  local trackedByRules = self.hookedTriggerSet and self.hookedTriggerSet[spellID] == true
  local trackedByTargetWatch = false
  local targetList = ns.db and ns.db.watchlist and ns.db.watchlist.target
  if type(targetList) == "table" then
    for i = 1, #targetList do
      local item = targetList[i]
      if normalizeTrackingMode(item, "target") == "estimated" and isTrackedByCastList(spellID, item.castSpellIDs) then
        trackedByTargetWatch = true
        break
      end
    end
  end
  local tracked = trackedByRules or trackedByTargetWatch
  local now = GetTime()
  local state = nil
  if tracked then
    local failGateUntil = tonumber((self.castResolverFailGateUntilBySpell or {})[spellID]) or 0
    if failGateUntil > now then
      ns.Debug:Verbosef(
        "CastResolver attempt_penalty spellID=%d source=%s reason=fail_gate remaining=%.2f",
        tonumber(spellID) or 0,
        tostring(sourceTag or "HOOK"),
        math.max(0, failGateUntil - now)
      )
    end
    state = openResolverState(self, spellID, sourceTag, now)
  end

  recordRawAttempt(self, tracked and state or nil, now)
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

local function cleanupSyntheticTargetAuras(self, now)
  now = tonumber(now) or GetTime()
  self.syntheticTargetAuras = self.syntheticTargetAuras or {}
  for targetGUID, states in pairs(self.syntheticTargetAuras) do
    if type(states) == "table" then
      for spellID, state in pairs(states) do
        if type(state) ~= "table" or (state.expirationTime and state.expirationTime <= now + 0.05) then
          states[spellID] = nil
        end
      end
      if next(states) == nil then
        self.syntheticTargetAuras[targetGUID] = nil
      end
    else
      self.syntheticTargetAuras[targetGUID] = nil
    end
  end
end

local function getSyntheticTargetSlotKey()
  return SYNTHETIC_TARGET_SLOT
end

local function getSyntheticTargetAura(self, spellID)
  cleanupSyntheticTargetAuras(self, GetTime())
  spellID = tonumber(spellID)
  if not spellID then
    return nil
  end
  local targetKey = getSyntheticTargetSlotKey()
  local states = self.syntheticTargetAuras and self.syntheticTargetAuras[targetKey]
  local state = states and states[spellID]
  if type(state) ~= "table" then
    return nil
  end
  return {
    name = ns.AuraAPI:GetSpellName(spellID),
    icon = ns.AuraAPI:GetSpellTexture(spellID),
    applications = tonumber(state.applications) or 1,
    duration = tonumber(state.duration) or nil,
    expirationTime = tonumber(state.expirationTime) or nil,
    sourceUnit = "player",
    spellId = spellID,
    spellID = spellID,
    auraInstanceID = 0,
    isFromPlayerOrPlayerPet = true,
    _alStateKind = "estimated_target_debuff",
    _alStateLabel = "Estimated from your cast",
  }
end

local function applySyntheticTargetAura(self, configuredSpellID, duration, applications, sourceSpellID, sourceTag)
  configuredSpellID = tonumber(configuredSpellID)
  duration = tonumber(duration)
  if not configuredSpellID or not duration or duration <= 0 then
    return false
  end
  self.syntheticTargetAuras = self.syntheticTargetAuras or {}
  local targetKey = getSyntheticTargetSlotKey()
  self.syntheticTargetAuras[targetKey] = self.syntheticTargetAuras[targetKey] or {}
  local now = GetTime()
  local state = self.syntheticTargetAuras[targetKey][configuredSpellID] or {}
  state.applications = tonumber(applications) or math.max(1, tonumber(state.applications) or 1)
  state.duration = duration
  state.expirationTime = now + duration
  state.sourceSpellID = tonumber(sourceSpellID) or configuredSpellID
  state.sourceTag = tostring(sourceTag or "")
  state.updatedAt = now
  self.syntheticTargetAuras[targetKey][configuredSpellID] = state
  ns.Debug:Throttled(
    "synthetic-target-show-" .. tostring(configuredSpellID),
    0.25,
    "Synthetic target aura show slot=%s spellID=%d duration=%.1f source=%s",
    targetKey,
    configuredSpellID,
    duration,
    tostring(sourceTag or "")
  )
  return true
end

local function removeSyntheticTargetAura(self, configuredSpellID, reason)
  configuredSpellID = tonumber(configuredSpellID)
  if not configuredSpellID then
    return false
  end
  local targetKey = getSyntheticTargetSlotKey()
  local states = self.syntheticTargetAuras and self.syntheticTargetAuras[targetKey]
  if not states or not states[configuredSpellID] then
    return false
  end
  states[configuredSpellID] = nil
  if next(states) == nil then
    self.syntheticTargetAuras[targetKey] = nil
  end
  ns.Debug:Throttled(
    "synthetic-target-hide-" .. tostring(configuredSpellID),
    0.25,
    "Synthetic target aura hide slot=%s spellID=%d reason=%s",
    targetKey,
    configuredSpellID,
    tostring(reason or "")
  )
  return true
end

local function forEachTrackedTargetSpell(self, sourceSpellID, fn)
  sourceSpellID = tonumber(sourceSpellID)
  if not sourceSpellID or type(fn) ~= "function" then
    return
  end
  local list = ns.db and ns.db.watchlist and ns.db.watchlist.target
  if type(list) ~= "table" then
    return
  end
  for _, item in ipairs(list) do
    local configuredSpellID = tonumber(item and item.spellID)
    if configuredSpellID then
      if normalizeTrackingMode(item, "target") == "estimated" and isTrackedByCastList(sourceSpellID, item.castSpellIDs) then
        fn(item, configuredSpellID, tonumber(item.estimatedDuration) or nil, "configured")
      else
        local triggerMap = SYNTHETIC_TARGET_TRIGGER_MAP[sourceSpellID]
        if triggerMap and triggerMap[configuredSpellID] == true then
          fn(item, configuredSpellID, nil, "legacy_map")
        else
          local aliases = ns.AuraAPI:GetSpellIDAliases(configuredSpellID)
          for i = 1, #aliases do
            if tonumber(aliases[i]) == sourceSpellID then
              fn(item, configuredSpellID, nil, "alias")
              break
            end
          end
        end
      end
    end
  end
end

applyConfirmedSyntheticTargetAuras = function(self, sourceSpellID, sourceTag)
  if not UnitExists("target") then
    return
  end
  forEachTrackedTargetSpell(self, sourceSpellID, function(item, configuredSpellID, configuredDuration, matchKind)
    local duration = tonumber(configuredDuration) or ns.AuraAPI:GetSpellBaseDurationSeconds(configuredSpellID)
    if duration and duration > 0 then
      applySyntheticTargetAura(self, configuredSpellID, duration, 1, sourceSpellID, sourceTag or "resolver")
      ns.Debug:Throttled(
        "synthetic-target-config-" .. tostring(configuredSpellID) .. "-" .. tostring(sourceSpellID),
        0.25,
        "Synthetic target config match aura=%d cast=%d duration=%.1f mode=%s",
        tonumber(configuredSpellID) or 0,
        tonumber(sourceSpellID) or 0,
        tonumber(duration) or 0,
        tostring(matchKind or "resolver")
      )
    end
  end)
end

logResolverOutcome = function(state, outcome, detail, now)
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
    local triggered = self:PollRuleCastEdges()
    if triggered then
      return
    end
    local confirmed = self:ConfirmPendingCastAttempts()
    if confirmed then
      return
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
  local configPreviewVisible = isConfigPreviewVisible()
  local playerClassToken = getPlayerClassToken()
  local playerSpecID = getPlayerSpecID()
  local playerInCombat = InCombatLockdown() == true
  local unitOrderMap = { player = 1, target = 2, focus = 3, pet = 4 }

  for _, item in ipairs(list) do
    if isAuraLoadAllowed(item, playerClassToken, playerSpecID, playerInCombat) then
      local trackingMode = normalizeTrackingMode(item, unit)
      local directAuraTracking = unit ~= "player" and trackingMode ~= "estimated"
      local selectedInUnlock = isSelectedAuraInUnlock(unit, item)
      local previewItem = getSelectedAuraPreviewItem(unit, item)
      local renderItem = previewItem or item
      local selectedPreview = previewItem ~= nil
      local effectiveGroupID = resolveDisplayGroupID(unit, renderItem)
      if selectedInUnlock or selectedPreview then
        effectiveGroupID = buildIndependentGroupID(unit, renderItem)
      end
      local aura = nil
      if directAuraTracking or trackingMode == "estimated" or not rulesOnlyMode then
        if directAuraTracking then
          aura = ns.AuraAPI:GetAuraBySpellID(unit, renderItem.spellID)
        end
        if not aura and unit == "target" then
          aura = getSyntheticTargetAura(self, renderItem.spellID)
        end
        if directAuraTracking then
          ns.Debug:Throttled(
            "direct-aura-lookup-" .. tostring(unit) .. "-" .. tostring(renderItem.spellID) .. "-" .. tostring(aura ~= nil),
            1.0,
            "Direct aura lookup unit=%s spellID=%d found=%s",
              tostring(unit),
              tonumber(renderItem.spellID) or 0,
              tostring(aura ~= nil)
            )
        end
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
      if include and renderItem.onlyMine then
        include = aura and ns.AuraAPI:IsFromPlayerOrPet(aura) or true
      end
      if include and renderItem.resourceConditionEnabled == true and ns.PlayerResource then
        include = ns.PlayerResource:MatchesRange(renderItem.resourceMinPct, renderItem.resourceMaxPct)
      end

      if include then
        local canCompute = aura and ns.AuraAPI:CanComputeRemaining(aura) or (cooldown and cooldown.canCompute == true)
        local fallbackIcon = ns.AuraAPI:SelectBestTexture(aura and aura.icon or nil, ns.AuraAPI:GetSpellTexture(renderItem.spellID), 136243)
        local auraExpirationTime, auraDuration = ns.AuraAPI:GetAuraTiming(aura)
        local applications = ns.AuraAPI:GetAuraApplications(aura)
        local expirationTime = auraExpirationTime or (cooldown and cooldown.expirationTime)
        local duration = auraDuration or (cooldown and cooldown.duration)
        local sourceLabel = aura and ns.AuraAPI:GetSourceLabel(aura) or ""
        local stateKind = (aura and aura._alStateKind) or ((trackingMode == "estimated") and "estimated_target_debuff" or "confirmed_aura")
        local stateLabel = (aura and aura._alStateLabel) or ((trackingMode == "estimated") and "Estimated from your cast" or "Direct aura read")
        rowsByGroup[effectiveGroupID] = rowsByGroup[effectiveGroupID] or {}
        rowsByGroup[effectiveGroupID][#rowsByGroup[effectiveGroupID] + 1] = {
          unit = unit,
          groupID = effectiveGroupID,
          spellID = renderItem.spellID,
          auraInstanceID = ns.AuraAPI:GetAuraInstanceID(aura),
          icon = ns.AuraAPI:GetDisplayTextureForItem(renderItem, aura),
          fallbackIcon = fallbackIcon,
          applications = applications,
          expirationTime = expirationTime,
          duration = duration,
          sourceLabel = sourceLabel,
          stateKind = stateKind,
          stateLabel = stateLabel,
          trackingMode = trackingMode,
          canCompute = canCompute,
          alert = renderItem.alert ~= false,
          displayName = renderItem.displayName or "",
          customText = renderItem.customText or "",
          timerVisual = renderItem.timerVisual or "icon",
          iconWidth = tonumber(renderItem.iconWidth) or 36,
          iconHeight = tonumber(renderItem.iconHeight) or 36,
          barWidth = tonumber(renderItem.barWidth) or 94,
          barHeight = tonumber(renderItem.barHeight) or 16,
          showTimerText = renderItem.showTimerText ~= false,
          barColor = renderItem.barColor or "",
          barSide = renderItem.barSide or "right",
          barTexture = renderItem.barTexture or "",
          timerAnchor = renderItem.timerAnchor or "BOTTOM",
          timerOffsetX = tonumber(renderItem.timerOffsetX) or 0,
          timerOffsetY = tonumber(renderItem.timerOffsetY) or -1,
          customTextAnchor = renderItem.customTextAnchor or "TOP",
          customTextOffsetX = tonumber(renderItem.customTextOffsetX) or 0,
          customTextOffsetY = tonumber(renderItem.customTextOffsetY) or 2,
          resourceConditionEnabled = renderItem.resourceConditionEnabled == true,
          resourceMinPct = tonumber(renderItem.resourceMinPct) or 0,
          resourceMaxPct = tonumber(renderItem.resourceMaxPct) or 100,
          lowTimeThreshold = tonumber(renderItem.lowTimeThreshold) or 0,
          soundOnGain = renderItem.soundOnGain or "default",
          soundOnLow = renderItem.soundOnLow or "default",
          soundOnExpire = renderItem.soundOnExpire or "default",
          sortIndex = _,
          unitOrder = unitOrderMap[unit] or 99,
          isPlaceholder = false,
        }
      elseif selectedInUnlock
        or selectedPreview
        or ns.TestMode:IsEnabled()
        or ((ns.db and ns.db.locked == false) and not configPreviewVisible)
      then
        local fake = ns.TestMode:BuildPlaceholder(renderItem, unit)
        fake.groupID = effectiveGroupID
        fake.displayName = renderItem.displayName or ""
        fake.customText = renderItem.customText or ""
        fake.timerVisual = renderItem.timerVisual or "icon"
        fake.iconWidth = tonumber(renderItem.iconWidth) or 36
        fake.iconHeight = tonumber(renderItem.iconHeight) or 36
        fake.barWidth = tonumber(renderItem.barWidth) or 94
        fake.barHeight = tonumber(renderItem.barHeight) or 16
        fake.showTimerText = renderItem.showTimerText ~= false
        fake.barColor = renderItem.barColor or ""
        fake.barSide = renderItem.barSide or "right"
        fake.barTexture = renderItem.barTexture or ""
        fake.timerAnchor = renderItem.timerAnchor or "BOTTOM"
        fake.timerOffsetX = tonumber(renderItem.timerOffsetX) or 0
        fake.timerOffsetY = tonumber(renderItem.timerOffsetY) or -1
        fake.customTextAnchor = renderItem.customTextAnchor or "TOP"
        fake.customTextOffsetX = tonumber(renderItem.customTextOffsetX) or 0
        fake.customTextOffsetY = tonumber(renderItem.customTextOffsetY) or 2
        fake.resourceConditionEnabled = renderItem.resourceConditionEnabled == true
        fake.resourceMinPct = tonumber(renderItem.resourceMinPct) or 0
        fake.resourceMaxPct = tonumber(renderItem.resourceMaxPct) or 100
        fake.lowTimeThreshold = tonumber(renderItem.lowTimeThreshold) or 0
        fake.soundOnGain = renderItem.soundOnGain or "default"
        fake.soundOnLow = renderItem.soundOnLow or "default"
        fake.soundOnExpire = renderItem.soundOnExpire or "default"
        fake.sortIndex = _
        fake.unitOrder = unitOrderMap[unit] or 99
        fake.iconMode = renderItem.iconMode or "spell"
        fake.customTexture = renderItem.customTexture or ""
        fake.icon = ns.AuraAPI:GetDisplayTextureForItem(renderItem, nil)
        fake.fallbackIcon = ns.AuraAPI:SelectBestTexture(ns.AuraAPI:GetSpellTexture(renderItem.spellID), 136243)
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
  local orderedUnits = { "player", "target", "focus", "pet" }
  for i = 1, #orderedUnits do
    local unit = orderedUnits[i]
    local enabled = ns.db.units and ns.db.units[unit]
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
    if ns.UIV2 and ns.UIV2.ConfigFrame and ns.UIV2.ConfigFrame.Open then
      ns.UIV2.ConfigFrame:Open()
    elseif ns.ConfigUI and ns.ConfigUI.ShowFirstRun then
      ns.ConfigUI:ShowFirstRun()
    end
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
  self.syntheticTargetAuras = {}
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
  local affectsTrackedResolver = false

  self.lastRawAttempts = self.lastRawAttempts or {}
  for i = #self.lastRawAttempts, 1, -1 do
    local raw = self.lastRawAttempts[i]
    local rawSpellID = tonumber(raw and raw.spellID)
    local rawToken = tonumber(raw and raw.attemptToken)
    local rawAt = tonumber(raw and raw.at) or 0
    if (now - rawAt) > RESOLVER_UI_ERROR_WINDOW then
      table.remove(self.lastRawAttempts, i)
    elseif rawSpellID and rawToken then
      local attempt = getPendingAttemptByToken(self, rawSpellID, rawToken)
      if attempt then
        affectsTrackedResolver = blockResolverState(self, attempt, "ui_error", now) == true or affectsTrackedResolver
        if affectsTrackedResolver then
          break
        end
      end
    end
  end

  ns.Debug:Logf(
    "Event UI_ERROR_MESSAGE type=%s affectsTracked=%s rawSpell=%s rawTracked=%s msg=%s",
    tostring(msgType),
    tostring(affectsTrackedResolver),
    tostring(self.lastRawAttempt and self.lastRawAttempt.spellID or "nil"),
    tostring(self.lastRawAttempt and self.lastRawAttempt.tracked == true),
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

function E:UNIT_HEALTH(unit)
  if unit ~= "target" then
    return
  end
  if UnitIsDead("target") or UnitIsGhost("target") then
    local targetKey = getSyntheticTargetSlotKey()
    local states = self.syntheticTargetAuras and self.syntheticTargetAuras[targetKey]
    if type(states) == "table" then
      local changed = false
      for spellID in pairs(states) do
        changed = removeSyntheticTargetAura(self, spellID, "target_dead") or changed
      end
      if changed then
        self:RefreshAll()
      end
    end
  end
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
  local states = self.castResolverStates
  if type(states) ~= "table" or not next(states) then
    return false
  end

  local now = GetTime()
  local triggered = false
  local gcdData = getRawGlobalCooldownData()

  for spellID, attempts in pairs(states) do
    if type(attempts) ~= "table" then
      states[spellID] = nil
    else
      for i = #attempts, 1, -1 do
        local state = attempts[i]
        local age = now - (tonumber(state and state.attemptAt) or 0)
        if type(state) ~= "table" or age > RESOLVER_MAX_AGE then
          expireResolverState(self, state, "timeout", now)
        elseif state.status == "attempted" then
          local cd = ns.AuraAPI:GetSpellCooldownData(spellID)
          local cdStart = cd and tonumber(cd.startTime) or 0
          local cdNearAttempt = cdStart > 0 and cdStart >= ((state.attemptAt or 0) - 0.08) and cdStart <= (now + 0.05)
          if cdNearAttempt and not isGlobalCooldownOnlyForSpell(cd, gcdData) then
            if applyPositiveAttemptSignal(self, state, "cooldown_edge", RESOLVER_SCORE_CD_EDGE, "HOOK_CD_CONFIRM", now, cdStart) then
              triggered = true
            end
          else
            local gcdStart = gcdData and tonumber(gcdData.startTime) or 0
            local gcdNearAttempt = gcdStart > 0 and gcdStart >= ((state.attemptAt or 0) - 0.08) and gcdStart <= (now + 0.05)
            local blockedForAttempt = tonumber(state.lastErrorAt or 0) >= (state.attemptAt or 0)
            if gcdNearAttempt and state.restricted ~= true and state.offGCD ~= true and not blockedForAttempt then
              if applyPositiveAttemptSignal(self, state, "gcd_edge", RESOLVER_SCORE_GCD_EDGE, "HOOK_GCD_CONFIRM", now, gcdStart) then
                triggered = true
              end
            end
          end
          if shouldRejectAttempt(state) then
            expireResolverState(self, state, "negative_score", now)
          end
        end
      end
    end
  end

  cleanupAttemptLists(self)
  return triggered
end

function E:ConfirmPendingCastAttempts()
  local states = self.castResolverStates
  if type(states) ~= "table" or not next(states) then
    return false
  end

  local now = GetTime()
  local confirmedAny = false

  for spellID, attempts in pairs(states) do
    if type(attempts) ~= "table" then
      states[spellID] = nil
    else
      for i = #attempts, 1, -1 do
        local state = attempts[i]
        local age = now - (tonumber(state and state.attemptAt) or 0)
        if type(state) ~= "table" or age > RESOLVER_MAX_AGE then
          expireResolverState(self, state, "timeout", now)
        elseif state.status == "blocked" then
          expireResolverState(self, state, "blocked", now)
        elseif state.status == "attempted" then
          local blockedForAttempt = tonumber(state.lastErrorAt or 0) >= (state.attemptAt or 0)
          if state.restricted == true
            and state.restrictedFallbackUsed ~= true
            and age >= RESOLVER_RESTRICTED_MIN_AGE
            and age <= RESOLVER_RESTRICTED_MAX_AGE
            and not blockedForAttempt
          then
            state.restrictedFallbackUsed = true
            if applyPositiveAttemptSignal(self, state, "restricted_quiet", RESOLVER_SCORE_RESTRICTED_QUIET, "HOOK_RESTRICTED_NOERROR", now, age) then
              confirmedAny = true
            end
          elseif shouldConfirmAttempt(state) then
            if confirmResolverState(self, state, "HOOK_SCORE_CONFIRM", now) then
              confirmedAny = true
            end
          elseif shouldRejectAttempt(state) then
            expireResolverState(self, state, "negative_score", now)
          end
        end
      end
    end
  end

  cleanupAttemptLists(self)
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
    local now = GetTime()
    spellID = normalizeQueuedSpellID(spellID)
    local attempt = getLatestPendingAttempt(self, spellID, now, RESOLVER_MAX_AGE)
    if attempt and applyPositiveAttemptSignal(self, attempt, "runtime_success", RESOLVER_SCORE_RUNTIME_SUCCESS, "UNIT_SPELLCAST_SUCCEEDED", now, unit) then
      return
    end
    processPlayerCast(self, spellID, "UNIT_SPELLCAST_SUCCEEDED")
  end
end

local function handleRuntimeCastFailure(self, eventName, unit, spellID)
  ns.Debug:Verbosef("Event %s unit=%s spellID=%s", tostring(eventName), tostring(unit), tostring(spellID))
  if unit ~= "player" then
    return
  end
  local now = GetTime()
  spellID = normalizeQueuedSpellID(spellID)
  local attempt = getLatestPendingAttempt(self, spellID, now, RESOLVER_MAX_AGE)
  if attempt then
    blockResolverState(self, attempt, string.lower(tostring(eventName or "runtime_fail")), now)
  end
end

function E:UNIT_SPELLCAST_FAILED(unit, _, spellID)
  handleRuntimeCastFailure(self, "UNIT_SPELLCAST_FAILED", unit, spellID)
end

function E:UNIT_SPELLCAST_FAILED_QUIET(unit, _, spellID)
  handleRuntimeCastFailure(self, "UNIT_SPELLCAST_FAILED_QUIET", unit, spellID)
end

function E:UNIT_SPELLCAST_INTERRUPTED(unit, _, spellID)
  handleRuntimeCastFailure(self, "UNIT_SPELLCAST_INTERRUPTED", unit, spellID)
end

























