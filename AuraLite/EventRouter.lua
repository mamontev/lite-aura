local _, ns = ...
ns.EventRouter = ns.EventRouter or {}
local E = ns.EventRouter
E.lastProcessedCast = E.lastProcessedCast or {}
E.lastCooldownRefresh = E.lastCooldownRefresh or 0
E.ruleCastPollState = E.ruleCastPollState or {}
E.pendingCastAttempts = E.pendingCastAttempts or {}
E.hookedTriggerSet = E.hookedTriggerSet or {}
E.hookedTriggerRevision = E.hookedTriggerRevision or -1
E.lastUiErrorAt = E.lastUiErrorAt or 0
E.lastRawAttempt = E.lastRawAttempt or nil
E.lastRefreshSummary = E.lastRefreshSummary or { key = "", at = 0 }
local processPlayerCast

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

local function queueCastAttempt(self, spellID, sourceTag)
  spellID = normalizeQueuedSpellID(spellID)
  if not spellID or spellID <= 0 then
    return
  end

  self:RefreshHookedTriggerSet()
  local tracked = self.hookedTriggerSet and self.hookedTriggerSet[spellID] == true
  self.lastRawAttempt = {
    spellID = spellID,
    source = tostring(sourceTag or "HOOK"),
    tracked = tracked == true,
    at = GetTime(),
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
  if not tracked then
    return
  end

  local queue = self.pendingCastAttempts or {}
  self.pendingCastAttempts = queue
  local now = GetTime()
  local last = queue[#queue]
  if last and last.spellID == spellID and (now - (last.at or 0)) < 0.05 then
    ns.Debug:Verbosef("Skip duplicate cast attempt spellID=%d source=%s", spellID, tostring(sourceTag or "HOOK"))
    return
  end
  if #queue >= 20 then
    table.remove(queue, 1)
  end

  queue[#queue + 1] = {
    spellID = spellID,
    at = now,
    source = tostring(sourceTag or "HOOK"),
    restricted = ns.AuraAPI:IsSecretCooldownsRestricted(spellID),
  }
  ns.Debug:Logf(
    "Cast attempt queued spellID=%d name=%s source=%s q=%d restricted=%s",
    spellID,
    tostring(getSpellDebugName(spellID)),
    tostring(sourceTag or "HOOK"),
    #queue,
    tostring(ns.AuraAPI:IsSecretCooldownsRestricted(spellID))
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
      local confirmed = self:ConfirmPendingCastAttempts()
      if confirmed then
        return
      end
      local triggered = self:PollRuleCastEdges()
      if triggered then
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
  ns.Debug:Log("Cast hooks installed (attempt queue + confirmation).")
end

function E:BuildRowsForUnit(unit)
  local rowsByGroup = {}
  local list = ns.db.watchlist[unit] or {}
  local rulesOnlyMode = ns.db and ns.db.options and ns.db.options.rulesOnlyMode == true

  for _, item in ipairs(list) do
    local aura = nil
    if not rulesOnlyMode then
      aura = ns.AuraAPI:GetAuraBySpellID(unit, item.spellID)
    end

    if ns.ProcRules and ns.ProcRules.GetSyntheticAura then
      local synthetic = ns.ProcRules:GetSyntheticAura(item.spellID)
      if synthetic then
        if not aura then
          aura = synthetic
        else
          -- If aura exists but all key fields are hidden/secret, prefer deterministic synthetic state.
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
    if (not rulesOnlyMode) and (not aura) and unit == "player" then
      cooldownRestricted = ns.AuraAPI:IsSecretCooldownsRestricted(item.spellID)
      if cooldownRestricted then
        cooldown = getEstimatedCooldown(item.spellID)
        if cooldown then
          ns.Debug:Throttled(
            "cd-estimate-" .. tostring(item.spellID),
            1.5,
            "Estimated cooldown row spellID=%d remaining=%.1f",
            tonumber(item.spellID) or 0,
            math.max(0, (cooldown.expirationTime or 0) - GetTime())
          )
        else
          ns.Debug:Throttled(
            "cd-restricted-" .. tostring(item.spellID),
            4.0,
            "SecretCooldowns active for spellID=%d: cooldown hidden by API in this context.",
            tonumber(item.spellID) or 0
          )
        end
      else
        cooldown = ns.AuraAPI:GetSpellCooldownData(item.spellID)
        if cooldown then
          learnCooldown(item.spellID, cooldown.duration)
          clearEstimatedCooldown(item.spellID)
          local remaining = math.max(0, (cooldown.expirationTime or 0) - GetTime())
          ns.Debug:Throttled(
            "cd-hit-" .. tostring(item.spellID),
            1.5,
            "Cooldown row spellID=%d remaining=%.1f",
            tonumber(item.spellID) or 0,
            remaining
          )
        else
          ns.Debug:Throttled(
            "cd-miss-" .. tostring(item.spellID),
            4.0,
            "No cooldown data spellID=%d (possible aura/proc ID).",
            tonumber(item.spellID) or 0
          )
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
      local fallbackIcon = ns.AuraAPI:SelectBestTexture(
        aura and aura.icon or nil,
        ns.AuraAPI:GetSpellTexture(item.spellID),
        136243
      )
      local auraExpirationTime, auraDuration = ns.AuraAPI:GetAuraTiming(aura)
      local applications = ns.AuraAPI:GetAuraApplications(aura)
      local expirationTime = auraExpirationTime or (cooldown and cooldown.expirationTime)
      local duration = auraDuration or (cooldown and cooldown.duration)
      local sourceLabel = aura and ns.AuraAPI:GetSourceLabel(aura) or ""
      rowsByGroup[item.groupID] = rowsByGroup[item.groupID] or {}
      rowsByGroup[item.groupID][#rowsByGroup[item.groupID] + 1] = {
        unit = unit,
        groupID = item.groupID,
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
    elseif ns.TestMode:IsEnabled() then
      local fake = ns.TestMode:BuildPlaceholder(item, unit)
      fake.groupID = item.groupID
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
      rowsByGroup[item.groupID] = rowsByGroup[item.groupID] or {}
      rowsByGroup[item.groupID][#rowsByGroup[item.groupID] + 1] = fake
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

  local affectsTrackedQueue = true
  local raw = self.lastRawAttempt
  if raw and (now - (tonumber(raw.at) or 0)) <= 0.25 and raw.tracked == false then
    affectsTrackedQueue = false
  end

  if affectsTrackedQueue then
    self.lastUiErrorAt = now
  end

  ns.Debug:Logf(
    "Event UI_ERROR_MESSAGE type=%s affectsTracked=%s rawSpell=%s rawTracked=%s msg=%s",
    tostring(msgType),
    tostring(affectsTrackedQueue),
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
  if not ns.ProcRules or not ns.ProcRules.GetTriggerSpellIDs then
    return false
  end

  local queue = self.pendingCastAttempts
  if type(queue) ~= "table" or #queue == 0 then
    return false
  end

  local now = GetTime()
  local pendingBySpell = {}
  for i = #queue, 1, -1 do
    local attempt = queue[i]
    local age = now - (tonumber(attempt and attempt.at) or 0)
    if not attempt or age > 1.20 then
      table.remove(queue, i)
    elseif age <= 0.70 then
      local sid = tonumber(attempt.spellID)
      if sid and sid > 0 then
        pendingBySpell[sid] = true
      end
    end
  end
  if not next(pendingBySpell) then
    return false
  end

  self:RefreshHookedTriggerSet()
  local triggered = false
  self.ruleCastPollState = self.ruleCastPollState or {}
  local gcdData = getRawGlobalCooldownData()

  for spellID in pairs(pendingBySpell) do
    if self.hookedTriggerSet and self.hookedTriggerSet[spellID] then
      local state = self.ruleCastPollState[spellID]
      if not state then
        state = { onCd = false, startTime = 0, lastFire = 0 }
        self.ruleCastPollState[spellID] = state
      end

      local cd = ns.AuraAPI:GetSpellCooldownData(spellID)
      local onCd = cd ~= nil
      local gcdOnly = onCd and isGlobalCooldownOnlyForSpell(cd, gcdData)
      if gcdOnly then
        onCd = false
      end
      local startTime = onCd and (tonumber(cd.startTime) or 0) or 0
      local nearStart = onCd and startTime > 0 and (now - startTime) >= -0.05 and (now - startTime) <= 0.45
      local startedNow = onCd and (not state.onCd) and nearStart
      local restarted = onCd and state.onCd and startTime > ((state.startTime or 0) + 0.05) and nearStart
      local fire = startedNow or restarted

      state.onCd = onCd
      state.startTime = startTime

      if fire and (now - (state.lastFire or 0)) > 0.25 then
        state.lastFire = now
        processPlayerCast(self, spellID, "POLL_COOLDOWN_EDGE")
        for i = #queue, 1, -1 do
          if tonumber(queue[i] and queue[i].spellID) == spellID then
            table.remove(queue, i)
          end
        end
        triggered = true
      end
    end
  end

  return triggered
end

function E:ConfirmPendingCastAttempts()
  local queue = self.pendingCastAttempts
  if type(queue) ~= "table" or #queue == 0 then
    return false
  end

  local now = GetTime()
  local confirmedAny = false

  local gcd = getRawGlobalCooldownData()

  for i = #queue, 1, -1 do
    local attempt = queue[i]
    local age = now - (tonumber(attempt and attempt.at) or 0)
    if not attempt or age > 1.20 then
      table.remove(queue, i)
    else
      local confirmed = false
      local sourceTag = nil

      local cd = ns.AuraAPI:GetSpellCooldownData(attempt.spellID)
      if cd then
        local startTime = tonumber(cd.startTime) or 0
        if startTime > 0 and startTime >= ((attempt.at or 0) - 0.08) and startTime <= (now + 0.05) then
          confirmed = true
          sourceTag = "HOOK_CD_CONFIRM"
        end
      end

      if (not confirmed) and gcd then
        local gcdStart = tonumber(gcd.startTime) or 0
        if gcdStart > 0 and gcdStart >= ((attempt.at or 0) - 0.08) and gcdStart <= (now + 0.05) then
          confirmed = true
          sourceTag = "HOOK_GCD_CONFIRM"
        end
      end

      if (not confirmed)
        and InCombatLockdown()
        and attempt.restricted == true
        and age >= 0.08
        and age <= 0.55
      then
        local lastErrAt = tonumber(self.lastUiErrorAt) or 0
        local hasRecentError = lastErrAt >= ((attempt.at or 0) - 0.02)
        if not hasRecentError then
          confirmed = true
          sourceTag = "HOOK_RESTRICTED_NOERROR"
        end
      end

      if confirmed then
        ns.Debug:Logf(
          "Cast attempt confirmed spellID=%d name=%s via=%s age=%.2f restricted=%s",
          tonumber(attempt.spellID) or 0,
          tostring(getSpellDebugName(attempt.spellID)),
          tostring(sourceTag or attempt.source or "HOOK_CONFIRM"),
          tonumber(age) or 0,
          tostring(attempt.restricted == true)
        )
        processPlayerCast(self, attempt.spellID, sourceTag or attempt.source or "HOOK_CONFIRM")
        table.remove(queue, i)
        confirmedAny = true
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
