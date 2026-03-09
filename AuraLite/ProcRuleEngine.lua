local _, ns = ...

ns.ProcRules = ns.ProcRules or {}
local P = ns.ProcRules
P.revision = P.revision or 0

local CONDITION_KIND = {
  istalented = 1,
  auraactive = 2,
  auramissing = 3,
  incombat = 4,
  cooldownrestricted = 5,
  legacytalenthint = 6,
}

local function normalizeSpellIDList(input)
  local out = {}
  local seen = {}

  local function push(value)
    local id = tonumber(value)
    if id and id > 0 and not seen[id] then
      seen[id] = true
      out[#out + 1] = id
    end
  end

  if type(input) == "table" then
    for i = 1, #input do
      push(input[i])
    end
  else
    push(input)
  end

  return out
end

local function makeSet(list)
  local out = {}
  if type(list) ~= "table" then
    return out
  end
  for _, value in ipairs(list) do
    local id = tonumber(value)
    if id then
      out[id] = true
    end
  end
  return out
end

local function getPlayerClassToken()
  local _, classToken = UnitClass("player")
  return classToken
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

local function buildPlayerTalentSpellSet()
  local out = {}
  if not (C_ClassTalents and C_ClassTalents.GetActiveConfigID and C_Traits) then
    return out
  end

  local okConfig, configID = pcall(C_ClassTalents.GetActiveConfigID)
  if not okConfig or not configID then
    return out
  end

  local okInfo, configInfo = pcall(C_Traits.GetConfigInfo, configID)
  if not okInfo or type(configInfo) ~= "table" or type(configInfo.treeIDs) ~= "table" then
    return out
  end

  for i = 1, #configInfo.treeIDs do
    local treeID = configInfo.treeIDs[i]
    local okNodes, nodeIDs = pcall(C_Traits.GetTreeNodes, treeID)
    if okNodes and type(nodeIDs) == "table" then
      for n = 1, #nodeIDs do
        local nodeID = nodeIDs[n]
        local okNode, nodeInfo = pcall(C_Traits.GetNodeInfo, configID, nodeID)
        if okNode and type(nodeInfo) == "table" then
          local selectedEntryID = nil
          if type(nodeInfo.activeEntry) == "table" then
            selectedEntryID = tonumber(nodeInfo.activeEntry.entryID)
          end
          if not selectedEntryID and type(nodeInfo.entryIDs) == "table" then
            for e = 1, #nodeInfo.entryIDs do
              local entryID = nodeInfo.entryIDs[e]
              local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, entryID)
              if okEntry and type(entryInfo) == "table" then
                local ranksPurchased = tonumber(entryInfo.ranksPurchased) or 0
                local activeRank = tonumber(entryInfo.activeRank) or 0
                if ranksPurchased > 0 or activeRank > 0 then
                  selectedEntryID = tonumber(entryID)
                  break
                end
              end
            end
          end

          if selectedEntryID then
            local okEntry, entryInfo = pcall(C_Traits.GetEntryInfo, configID, selectedEntryID)
            if okEntry and type(entryInfo) == "table" and entryInfo.definitionID then
              local okDef, defInfo = pcall(C_Traits.GetDefinitionInfo, entryInfo.definitionID)
              if okDef and type(defInfo) == "table" and defInfo.spellID then
                local spellID = tonumber(defInfo.spellID)
                if spellID and spellID > 0 then
                  out[spellID] = true
                end
              end
            end
          end
        end
      end
    end
  end

  return out
end

local function isPlayerSpellKnown(spellID)
  if not spellID or not IsPlayerSpell then
    if P and P.playerTalentSpellSet and P.playerTalentSpellSet[tonumber(spellID) or 0] == true then
      return true
    end
    return true
  end
  local ok, known = pcall(IsPlayerSpell, spellID)
  if not ok then
    if P and P.playerTalentSpellSet and P.playerTalentSpellSet[tonumber(spellID) or 0] == true then
      return true
    end
    return true
  end
  if known == true then
    return true
  end
  if P and P.playerTalentSpellSet and P.playerTalentSpellSet[tonumber(spellID) or 0] == true then
    return true
  end
  return false
end

local function ensureProcState()
  ns.state.procRuleStates = ns.state.procRuleStates or {}
  return ns.state.procRuleStates
end

local function ensureUserRules()
  if not ns.db then
    return {}
  end
  if type(ns.db.procRules) ~= "table" then
    ns.db.procRules = {}
  end
  return ns.db.procRules
end

local function isRulesOnlyMode()
  return ns.db and ns.db.options and ns.db.options.rulesOnlyMode == true
end

local function ensureRuleAuraTrackedOnPlayer(auraSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID or auraSpellID <= 0 then
    return
  end
  if not ns.db then
    return
  end

  ns.db.watchlist = type(ns.db.watchlist) == "table" and ns.db.watchlist or {}
  ns.db.watchlist.player = type(ns.db.watchlist.player) == "table" and ns.db.watchlist.player or {}

  local list = ns.db.watchlist.player
  for i = 1, #list do
    if tonumber(list[i].spellID) == auraSpellID then
      return
    end
  end

  local added = false
  if ns.Registry and ns.Registry.AddWatch then
    local item = ns.Registry:AddWatch("player", {
      spellID = auraSpellID,
      groupID = "important_procs",
      onlyMine = true,
      alert = true,
      timerVisual = "icon",
      lowTimeThreshold = 0,
    })
    added = item ~= nil
  end

  if not added then
    list[#list + 1] = {
      spellID = auraSpellID,
      groupID = "important_procs",
      onlyMine = true,
      alert = true,
      timerVisual = "icon",
      lowTimeThreshold = 0,
    }
    if ns.RebuildWatchIndex then
      ns:RebuildWatchIndex()
    end
  end

  if ns.Debug then
    ns.Debug:Logf("Auto-track enabled for rule aura spellID=%d on player.", auraSpellID)
  end
end

local LEGACY_RULES = {
  {
    id = "warrior_phalanx_legacy",
    auraSpellID = 1278009, -- Phalanx
    classToken = "WARRIOR",
    specIDs = { 73 }, -- Protection
    requiredPlayerSpellID = nil, -- buff aura spell may not be reported as known spell
    activateSpellIDs = { 6343 }, -- Thunder Clap
    consumeSpellIDs = { 23922, 72 }, -- Shield Slam / Shield Bash fallback
    defaultDuration = 8,
    maxStacks = 1,
    consumeMode = "clear",
  },
}

local function normalizeCondition(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local condType = tostring(raw.type or ""):lower()
  if condType == "" then
    return nil
  end
  local out = { type = condType }
  out.kind = CONDITION_KIND[condType] or 0
  out.spellID = tonumber(raw.spellID) or tonumber(raw.auraSpellID) or nil
  out.value = raw.value
  return out
end

local function normalizeAction(raw)
  if type(raw) ~= "table" then
    return nil
  end
  local actionType = tostring(raw.type or ""):lower()
  if actionType == "" then
    return nil
  end
  local out = { type = actionType }
  out.auraSpellID = tonumber(raw.auraSpellID) or tonumber(raw.spellID) or nil
  out.duration = tonumber(raw.duration) or nil
  out.stacks = tonumber(raw.stacks) or nil
  out.maxStacks = tonumber(raw.maxStacks) or nil
  local hideOnTimerEnd = raw.hideOnTimerEnd
  if hideOnTimerEnd == nil then
    hideOnTimerEnd = raw.hide_on_timer_end
  end
  if hideOnTimerEnd == nil then
    out.hideOnTimerEnd = true
  else
    out.hideOnTimerEnd = hideOnTimerEnd == true
  end
  return out
end

local function normalizeIfRule(raw, idx)
  if type(raw) ~= "table" then
    return nil
  end

  local eventSpellIDs = normalizeSpellIDList(raw.eventSpellIDs)
  if #eventSpellIDs == 0 then
    eventSpellIDs = normalizeSpellIDList(raw.eventSpellID)
  end
  if #eventSpellIDs == 0 then
    return nil
  end

  local classToken = tostring(raw.classToken or ""):upper()
  if classToken == "" or classToken == "ANY" or classToken == "*" then
    classToken = nil
  end

  local rule = {
    kind = "if",
    id = tostring(raw.id or ("if_rule_" .. tostring(idx or 0))),
    name = tostring(raw.name or ""),
    enabled = raw.enabled ~= false,
    eventSpellID = eventSpellIDs[1],
    eventSpellIDs = eventSpellIDs,
    conditionMode = (tostring(raw.conditionMode or "all"):lower() == "any") and "any" or "all",
    modeAny = (tostring(raw.conditionMode or "all"):lower() == "any"),
    classToken = classToken,
    specSet = makeSet(raw.specIDs),
    ifAll = {},
    thenActions = {},
    elseActions = {},
  }

  local rawConditions = raw.ifAll
  if type(rawConditions) ~= "table" and type(raw.ifAny) == "table" then
    rawConditions = raw.ifAny
  end

  if type(rawConditions) == "table" then
    for _, cond in ipairs(rawConditions) do
      local normalized = normalizeCondition(cond)
      if normalized then
        rule.ifAll[#rule.ifAll + 1] = normalized
      end
    end
  end

  if type(raw.thenActions) == "table" then
    for _, action in ipairs(raw.thenActions) do
      local normalized = normalizeAction(action)
      if normalized then
        rule.thenActions[#rule.thenActions + 1] = normalized
      end
    end
  end

  if type(raw.elseActions) == "table" then
    for _, action in ipairs(raw.elseActions) do
      local normalized = normalizeAction(action)
      if normalized then
        rule.elseActions[#rule.elseActions + 1] = normalized
      end
    end
  end

  -- For pure consume rules (hide/decrement only), an auraActive(self) condition is redundant:
  -- hide/decrement is idempotent and should not fail because aura presence checks become unreliable in combat.
  if #rule.thenActions > 0 and #rule.elseActions == 0 then
    local consumeAura = nil
    local consumeOnly = true
    for i = 1, #rule.thenActions do
      local action = rule.thenActions[i]
      local actionType = action and action.type or ""
      if actionType ~= "hideaura" and actionType ~= "decrementaura" then
        consumeOnly = false
        break
      end
      local sid = tonumber(action.auraSpellID)
      if not sid or sid <= 0 then
        consumeOnly = false
        break
      end
      if not consumeAura then
        consumeAura = sid
      elseif consumeAura ~= sid then
        consumeOnly = false
        break
      end
    end

    if consumeOnly and consumeAura then
      local filtered = {}
      for i = 1, #rule.ifAll do
        local cond = rule.ifAll[i]
        local isSelfAuraPresence =
          cond
          and cond.kind == CONDITION_KIND.auraactive
          and tonumber(cond.spellID) == consumeAura
        if not isSelfAuraPresence then
          filtered[#filtered + 1] = cond
        end
      end
      rule.ifAll = filtered
    end
  end

  -- Backward compatibility:
  -- Old rules often used talentSpellID = auraSpellID as a generic gate.
  -- In modern clients this is frequently not a real talent spell, so treat it as a soft hint.
  -- Applies to both show/hide/decrement actions bound to the same aura.
  if #rule.ifAll > 0 and #rule.thenActions > 0 then
    local actionAuraSet = {}
    for i = 1, #rule.thenActions do
      local action = rule.thenActions[i]
      if action and (action.type == "showaura" or action.type == "hideaura" or action.type == "decrementaura") then
        local id = tonumber(action.auraSpellID)
        if id and id > 0 then
          actionAuraSet[id] = true
        end
      end
    end
    local ownerAura = tonumber(raw.ownerAuraSpellID)
    if ownerAura and ownerAura > 0 then
      actionAuraSet[ownerAura] = true
    end
    if next(actionAuraSet) ~= nil then
      for i = 1, #rule.ifAll do
        local cond = rule.ifAll[i]
        if cond and cond.kind == CONDITION_KIND.istalented then
          local sid = tonumber(cond.spellID)
          if sid and actionAuraSet[sid] == true then
            cond.kind = CONDITION_KIND.legacytalenthint
          end
        end
      end
    end
  end

  return rule
end

local function appendSpellConditions(outConditions, conditionType, spellIDs)
  spellIDs = normalizeSpellIDList(spellIDs)
  for i = 1, #spellIDs do
    outConditions[#outConditions + 1] = {
      type = conditionType,
      spellID = spellIDs[i],
    }
  end
end

local function buildConditionsFromModel(model)
  local out = {}
  appendSpellConditions(out, "isTalented", model.talentSpellIDs or model.talentSpellID)
  appendSpellConditions(out, "auraActive", model.requiredAuraSpellIDs or model.requiredAuraSpellID)
  if model.requireInCombat == true then
    out[#out + 1] = { type = "inCombat" }
  end
  return out
end

local function getRuleAuraSpellID(rule)
  if type(rule) ~= "table" then
    return nil
  end
  local owner = tonumber(rule.ownerAuraSpellID)
  if owner and owner > 0 then
    return owner
  end
  local thenActions = type(rule.thenActions) == "table" and rule.thenActions or nil
  if thenActions then
    for i = 1, #thenActions do
      local id = tonumber(thenActions[i] and thenActions[i].auraSpellID)
      if id and id > 0 then
        return id
      end
    end
  end
  local elseActions = type(rule.elseActions) == "table" and rule.elseActions or nil
  if elseActions then
    for i = 1, #elseActions do
      local id = tonumber(elseActions[i] and elseActions[i].auraSpellID)
      if id and id > 0 then
        return id
      end
    end
  end
  return nil
end

local function getRulePrimaryActionType(rule)
  if type(rule) ~= "table" or type(rule.thenActions) ~= "table" then
    return ""
  end
  local first = rule.thenActions[1]
  return tostring(first and first.type or ""):lower()
end

function P:IsRuleEnabled(rule, classToken, specID)
  if rule.enabled == false then
    return false
  end
  if rule.classToken and classToken and rule.classToken ~= classToken then
    return false
  end
  if rule.specSet and next(rule.specSet) and (not specID or not rule.specSet[specID]) then
    return false
  end
  if rule.requiredPlayerSpellID and not isPlayerSpellKnown(rule.requiredPlayerSpellID) then
    return false
  end
  return true
end

function P:CompileRules()
  self.byLegacyActivateSpell = {}
  self.byLegacyConsumeSpell = {}
  self.byIfEventSpell = {}
  self.knownSyntheticAuras = {}
  self.triggerSpellSet = {}
  self.triggerSpellIDs = {}

  local classToken = getPlayerClassToken()
  local specID = getPlayerSpecID()

  if not isRulesOnlyMode() then
    for _, raw in ipairs(LEGACY_RULES) do
      local rule = {
        kind = "legacy",
        id = tostring(raw.id or ("legacy_" .. tostring(raw.auraSpellID))),
        auraSpellID = tonumber(raw.auraSpellID),
        classToken = raw.classToken and tostring(raw.classToken) or nil,
        specSet = makeSet(raw.specIDs),
        requiredPlayerSpellID = tonumber(raw.requiredPlayerSpellID) or nil,
        activateSet = makeSet(raw.activateSpellIDs),
        consumeSet = makeSet(raw.consumeSpellIDs),
        defaultDuration = tonumber(raw.defaultDuration) or 0,
        maxStacks = tonumber(raw.maxStacks) or 1,
        consumeMode = tostring(raw.consumeMode or "clear"):lower(),
        enabled = raw.enabled ~= false,
      }

      if rule.auraSpellID and self:IsRuleEnabled(rule, classToken, specID) then
        self.knownSyntheticAuras[rule.auraSpellID] = true
        for spellID in pairs(rule.activateSet) do
          self.byLegacyActivateSpell[spellID] = self.byLegacyActivateSpell[spellID] or {}
          self.byLegacyActivateSpell[spellID][#self.byLegacyActivateSpell[spellID] + 1] = rule
          self.triggerSpellSet[spellID] = true
        end
        for spellID in pairs(rule.consumeSet) do
          self.byLegacyConsumeSpell[spellID] = self.byLegacyConsumeSpell[spellID] or {}
          self.byLegacyConsumeSpell[spellID][#self.byLegacyConsumeSpell[spellID] + 1] = rule
          self.triggerSpellSet[spellID] = true
        end
      end
    end
  end

  local userRules = ensureUserRules()
  for idx, raw in ipairs(userRules) do
    local rule = normalizeIfRule(raw, idx)
    if rule and self:IsRuleEnabled(rule, classToken, specID) then
      for s = 1, #rule.eventSpellIDs do
        local triggerID = tonumber(rule.eventSpellIDs[s])
        if triggerID then
          self.byIfEventSpell[triggerID] = self.byIfEventSpell[triggerID] or {}
          self.byIfEventSpell[triggerID][#self.byIfEventSpell[triggerID] + 1] = rule
          self.triggerSpellSet[triggerID] = true
        end
      end

      for i = 1, #rule.thenActions do
        local auraSpellID = rule.thenActions[i].auraSpellID
        if auraSpellID then
          self.knownSyntheticAuras[auraSpellID] = true
        end
      end
      for i = 1, #rule.elseActions do
        local auraSpellID = rule.elseActions[i].auraSpellID
        if auraSpellID then
          self.knownSyntheticAuras[auraSpellID] = true
        end
      end
    end
  end

  for spellID in pairs(self.triggerSpellSet) do
    if spellID and spellID > 0 then
      self.triggerSpellIDs[#self.triggerSpellIDs + 1] = spellID
    end
  end
  table.sort(self.triggerSpellIDs)
end

function P:RefreshContext()
  self.playerTalentSpellSet = buildPlayerTalentSpellSet()
  self:CompileRules()
  self.revision = (tonumber(self.revision) or 0) + 1

  local states = ensureProcState()
  for auraSpellID in pairs(states) do
    if not self.knownSyntheticAuras[auraSpellID] then
      states[auraSpellID] = nil
    end
  end

  for auraSpellID in pairs(self.knownSyntheticAuras or {}) do
    ensureRuleAuraTrackedOnPlayer(auraSpellID)
  end

  local legacyCount = 0
  for _ in pairs(self.byLegacyActivateSpell or {}) do
    legacyCount = legacyCount + 1
  end
  local ifCount = 0
  for _, rules in pairs(self.byIfEventSpell or {}) do
    ifCount = ifCount + #rules
  end

  local talentCount = 0
  if type(self.playerTalentSpellSet) == "table" then
    for _ in pairs(self.playerTalentSpellSet) do
      talentCount = talentCount + 1
    end
  end
  ns.Debug:Verbosef("ProcRules refreshed. legacyTriggers=%d ifRules=%d talents=%d rev=%d", legacyCount, ifCount, talentCount, tonumber(self.revision) or 0)
end

function P:EnsureContext()
  if not self.byIfEventSpell or not self.byLegacyActivateSpell then
    self:RefreshContext()
  end
end

function P:ShowSyntheticAura(auraSpellID, duration, stacks, triggerSpellID, maxStacks, hideOnTimerEnd)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return false
  end

  local states = ensureProcState()
  local state = states[auraSpellID] or {}
  local wasActive = state.active == true
  local prevStacks = tonumber(state.applications) or 0
  local prevExpiration = tonumber(state.expirationTime) or 0

  local now = GetTime()
  local finalStacks = tonumber(stacks)
  if not finalStacks then
    finalStacks = math.max(1, prevStacks + 1)
  end
  if maxStacks and maxStacks > 0 and finalStacks > maxStacks then
    finalStacks = maxStacks
  end

  local finalDuration = tonumber(duration) or tonumber(state.duration) or 0
  local expirationTime = finalDuration > 0 and (now + finalDuration) or nil

  state.active = true
  state.applications = finalStacks
  state.startTime = now
  state.duration = finalDuration > 0 and finalDuration or nil
  state.expirationTime = expirationTime
  if hideOnTimerEnd == nil then
    state.hideOnTimerEnd = true
  else
    state.hideOnTimerEnd = hideOnTimerEnd == true
  end
  state.lastTriggerSpellID = tonumber(triggerSpellID) or 0
  states[auraSpellID] = state

  local changed = (not wasActive) or (prevStacks ~= finalStacks) or (math.abs((prevExpiration or 0) - (expirationTime or 0)) > 0.05)
  if changed then
    ns.Debug:Logf(
      "Proc show aura=%d trigger=%d stacks=%d duration=%.1f",
      auraSpellID,
      tonumber(triggerSpellID) or 0,
      finalStacks,
      tonumber(finalDuration) or 0
    )
  end
  return changed
end

function P:HideSyntheticAura(auraSpellID, triggerSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return false
  end
  local states = ensureProcState()
  local state = states[auraSpellID]
  if not state then
    ns.Debug:Throttled(
      "proc-hide-missing-" .. tostring(auraSpellID) .. "-" .. tostring(triggerSpellID or 0),
      0.25,
      "Proc hide requested aura=%d trigger=%d but state was not active.",
      auraSpellID,
      tonumber(triggerSpellID) or 0
    )
    return false
  end

  local now = GetTime()
  local lastTrigger = tonumber(state.lastTriggerSpellID) or 0
  local startTime = tonumber(state.startTime) or 0
  -- Guard against conflicting rules that show and hide the same aura on the same cast tick.
  if triggerSpellID and tonumber(triggerSpellID) == lastTrigger and startTime > 0 and (now - startTime) <= 0.20 then
    ns.Debug:Throttled(
      "proc-hide-suppressed-" .. tostring(auraSpellID) .. "-" .. tostring(triggerSpellID),
      0.5,
      "Suppress immediate hide aura=%d trigger=%d (same-cast conflict).",
      auraSpellID,
      tonumber(triggerSpellID) or 0
    )
    return false
  end

  states[auraSpellID] = nil
  ns.Debug:Logf("Proc hide aura=%d trigger=%d", auraSpellID, tonumber(triggerSpellID) or 0)
  return true
end

function P:DecrementSyntheticAura(auraSpellID, triggerSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return false
  end
  local states = ensureProcState()
  local state = states[auraSpellID]
  if not state then
    return false
  end

  local stacks = tonumber(state.applications) or 1
  stacks = stacks - 1
  if stacks <= 0 then
    states[auraSpellID] = nil
    ns.Debug:Logf("Proc decrement->hide aura=%d trigger=%d", auraSpellID, tonumber(triggerSpellID) or 0)
  else
    state.applications = stacks
    ns.Debug:Logf("Proc decrement aura=%d trigger=%d stacks=%d", auraSpellID, tonumber(triggerSpellID) or 0, stacks)
  end
  return true
end

function P:IsSyntheticAuraActive(auraSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return false
  end
  local states = ensureProcState()
  local state = states[auraSpellID]
  if not state or state.active ~= true then
    return false
  end
  if state.expirationTime and state.expirationTime <= GetTime() + 0.05 then
    if state.hideOnTimerEnd == false then
      state.expirationTime = nil
      state.duration = nil
      return true
    end
    states[auraSpellID] = nil
    return false
  end
  return true
end

function P:IsAuraEffectivelyActive(auraSpellID)
  if self:IsSyntheticAuraActive(auraSpellID) then
    return true
  end
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return false
  end
  local aura = ns.AuraAPI:GetAuraBySpellID("player", auraSpellID)
  if aura then
    return true
  end
  if InCombatLockdown() and ns.Debug then
    ns.Debug:Throttled(
      "aura-presence-miss-" .. tostring(auraSpellID),
      2.5,
      "Aura presence check miss in combat spellID=%d (treated as missing).",
      auraSpellID
    )
  end
  return false
end

function P:EvaluateCondition(condition)
  local condType = condition.type
  if condType == "istalented" then
    return isPlayerSpellKnown(condition.spellID)
  end
  if condType == "auraactive" then
    return self:IsAuraEffectivelyActive(condition.spellID)
  end
  if condType == "auramissing" then
    return not self:IsAuraEffectivelyActive(condition.spellID)
  end
  if condType == "incombat" then
    return InCombatLockdown() == true
  end
  if condType == "cooldownrestricted" then
    return ns.AuraAPI:IsSecretCooldownsRestricted(condition.spellID)
  end
  return false
end

function P:EvaluateConditionCached(condition, cache)
  local kind = condition.kind or 0
  local spellID = tonumber(condition.spellID) or 0

  if kind == CONDITION_KIND.istalented then
    local v = cache.talent[spellID]
    if v == nil then
      v = isPlayerSpellKnown(spellID)
      cache.talent[spellID] = v
    end
    return v
  end

  if kind == CONDITION_KIND.auraactive then
    local v = cache.aura[spellID]
    if v == nil then
      v = self:IsAuraEffectivelyActive(spellID)
      cache.aura[spellID] = v
    end
    return v
  end

  if kind == CONDITION_KIND.auramissing then
    local v = cache.aura[spellID]
    if v == nil then
      v = self:IsAuraEffectivelyActive(spellID)
      cache.aura[spellID] = v
    end
    return not v
  end

  if kind == CONDITION_KIND.incombat then
    if cache.inCombat == nil then
      cache.inCombat = InCombatLockdown() == true
    end
    return cache.inCombat
  end

  if kind == CONDITION_KIND.cooldownrestricted then
    local key = spellID > 0 and spellID or -1
    local v = cache.cooldown[key]
    if v == nil then
      v = ns.AuraAPI:IsSecretCooldownsRestricted(spellID > 0 and spellID or nil)
      cache.cooldown[key] = v
    end
    return v
  end

  if kind == CONDITION_KIND.legacytalenthint then
    return true
  end

  return self:EvaluateCondition(condition)
end

function P:ExecuteActions(actions, triggerSpellID)
  local changed = false
  if type(actions) ~= "table" then
    return false
  end
  for i = 1, #actions do
    local action = actions[i]
    if action.type == "showaura" then
      changed = self:ShowSyntheticAura(
        action.auraSpellID,
        action.duration,
        action.stacks,
        triggerSpellID,
        action.maxStacks,
        action.hideOnTimerEnd
      ) or changed
    elseif action.type == "hideaura" then
      changed = self:HideSyntheticAura(action.auraSpellID, triggerSpellID) or changed
    elseif action.type == "decrementaura" then
      changed = self:DecrementSyntheticAura(action.auraSpellID, triggerSpellID) or changed
    end
  end
  return changed
end

function P:ProcessLegacyRules(spellID)
  local changed = false
  local activateRules = self.byLegacyActivateSpell and self.byLegacyActivateSpell[spellID]
  if activateRules then
    for i = 1, #activateRules do
      local rule = activateRules[i]
      changed = self:ShowSyntheticAura(rule.auraSpellID, rule.defaultDuration, nil, spellID, rule.maxStacks, true) or changed
    end
  end

  local consumeRules = self.byLegacyConsumeSpell and self.byLegacyConsumeSpell[spellID]
  if consumeRules then
    for i = 1, #consumeRules do
      local rule = consumeRules[i]
      if rule.consumeMode == "decrement" then
        changed = self:DecrementSyntheticAura(rule.auraSpellID, spellID) or changed
      else
        changed = self:HideSyntheticAura(rule.auraSpellID, spellID) or changed
      end
    end
  end
  return changed
end

function P:ProcessIfRules(spellID)
  local changed = false
  local rules = self.byIfEventSpell and self.byIfEventSpell[spellID]
  if not rules then
    return false
  end
  local evalCache = {
    talent = {},
    aura = {},
    cooldown = {},
    inCombat = nil,
  }

  for i = 1, #rules do
    local rule = rules[i]
    local ruleID = tostring(rule.id or ("if_rule_" .. tostring(i)))
    local conditionCount = #rule.ifAll
    local modeAny = rule.modeAny == true
    local passed = true
    local failedCondType = nil
    local failedCondSpellID = nil

    if conditionCount > 0 then
      if modeAny then
        passed = false
        for j = 1, conditionCount do
          if self:EvaluateConditionCached(rule.ifAll[j], evalCache) then
            passed = true
            break
          end
        end
      else
        for j = 1, conditionCount do
          local cond = rule.ifAll[j]
          if not self:EvaluateConditionCached(cond, evalCache) then
            passed = false
            failedCondType = cond and cond.type or "unknown"
            failedCondSpellID = tonumber(cond and cond.spellID) or 0
            break
          end
        end
      end
    end

    ns.Debug:Throttled(
      "proc-rule-eval-" .. tostring(spellID) .. "-" .. ruleID,
      0.08,
      "Rule eval id=%s trigger=%d passed=%s mode=%s conds=%d fail=%s/%d",
      ruleID,
      tonumber(spellID) or 0,
      tostring(passed),
      modeAny and "OR" or "AND",
      tonumber(conditionCount) or 0,
      tostring(failedCondType or "none"),
      tonumber(failedCondSpellID) or 0
    )

    if passed then
      changed = self:ExecuteActions(rule.thenActions, spellID) or changed
      ns.Debug:Throttled(
        "proc-rule-action-then-" .. tostring(spellID) .. "-" .. ruleID,
        0.08,
        "Rule action THEN id=%s trigger=%d actions=%d changed=%s",
        ruleID,
        tonumber(spellID) or 0,
        tonumber(#(rule.thenActions or {})) or 0,
        tostring(changed)
      )
    else
      changed = self:ExecuteActions(rule.elseActions, spellID) or changed
      ns.Debug:Throttled(
        "proc-rule-action-else-" .. tostring(spellID) .. "-" .. ruleID,
        0.08,
        "Rule action ELSE id=%s trigger=%d actions=%d changed=%s",
        ruleID,
        tonumber(spellID) or 0,
        tonumber(#(rule.elseActions or {})) or 0,
        tostring(changed)
      )
    end
  end
  return changed
end

function P:OnPlayerSpellCast(spellID)
  spellID = tonumber(spellID)
  if not spellID then
    return false
  end
  self:EnsureContext()

  local changed = false
  changed = self:ProcessLegacyRules(spellID) or changed
  changed = self:ProcessIfRules(spellID) or changed
  return changed
end

function P:GetSyntheticAura(auraSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID then
    return nil
  end
  if not self:IsSyntheticAuraActive(auraSpellID) then
    return nil
  end

  local state = ensureProcState()[auraSpellID]
  if not state then
    return nil
  end

  return {
    auraInstanceID = 0,
    spellId = auraSpellID,
    icon = ns.AuraAPI:GetSpellTexture(auraSpellID),
    applications = tonumber(state.applications) or 1,
    expirationTime = state.expirationTime,
    duration = state.duration,
    sourceUnit = "player",
    isFromPlayerOrPlayerPet = true,
  }
end

function P:GetUserRules()
  return ensureUserRules()
end

function P:GetUserRulesForAura(auraSpellID)
  auraSpellID = tonumber(auraSpellID)
  if not auraSpellID or auraSpellID <= 0 then
    return {}
  end
  local all = ensureUserRules()
  local out = {}
  for i = 1, #all do
    local rule = all[i]
    if tonumber(getRuleAuraSpellID(rule)) == auraSpellID then
      out[#out + 1] = rule
    end
  end
  return out
end

function P:AddSimpleIfRuleEx(model)
  if type(model) ~= "table" then
    return nil, "invalid model"
  end

  local ruleID = tostring(model.id or "")
  local castSpellIDs = normalizeSpellIDList(model.castSpellIDs or model.castSpellID)
  local auraSpellID = tonumber(model.auraSpellID)
  local duration = tonumber(model.duration) or 0
  local conditionMode = (tostring(model.conditionMode or "all"):lower() == "any") and "any" or "all"

  if ruleID == "" or #castSpellIDs == 0 or not auraSpellID then
    return nil, "Usage: /al rule addif <id> <castSpellID> [talentSpellID] <auraSpellID> <durationSec>"
  end

  local rules = ensureUserRules()
  for i = #rules, 1, -1 do
    local sameID = tostring(rules[i].id or "") == ruleID
    local sameAura = tonumber(getRuleAuraSpellID(rules[i])) == auraSpellID
    local sameKind = getRulePrimaryActionType(rules[i]) == "showaura"
    if sameID and sameAura and sameKind then
      table.remove(rules, i)
    end
  end

  rules[#rules + 1] = {
    id = ruleID,
    name = tostring(model.name or ""),
    enabled = true,
    ownerAuraSpellID = auraSpellID,
    eventSpellID = castSpellIDs[1],
    eventSpellIDs = castSpellIDs,
    conditionMode = conditionMode,
    classToken = tostring(model.loadClassToken or ""):upper(),
    specIDs = normalizeSpellIDList(model.loadSpecIDs),
    ifAll = buildConditionsFromModel(model),
    thenActions = {
      { type = "showAura", auraSpellID = auraSpellID, duration = duration, stacks = 1, maxStacks = 1, hideOnTimerEnd = true },
    },
    elseActions = {
      { type = "hideAura", auraSpellID = auraSpellID },
    },
  }

  self:RefreshContext()
  return true
end

function P:AddSimpleConsumeRuleEx(model)
  if type(model) ~= "table" then
    return nil, "invalid model"
  end

  local ruleID = tostring(model.id or "")
  local castSpellIDs = normalizeSpellIDList(model.castSpellIDs or model.castSpellID)
  local auraSpellID = tonumber(model.auraSpellID)
  local conditionMode = (tostring(model.conditionMode or "all"):lower() == "any") and "any" or "all"
  local requiredAuraSpellIDs = normalizeSpellIDList(model.requiredAuraSpellIDs or model.requiredAuraSpellID)

  if ruleID == "" or #castSpellIDs == 0 or not auraSpellID then
    return nil, "Usage: /al rule addconsume <id> <castSpellID> <auraSpellID>"
  end

  if #requiredAuraSpellIDs == 0 then
    requiredAuraSpellIDs = { auraSpellID }
  end

  local rules = ensureUserRules()
  for i = #rules, 1, -1 do
    local sameID = tostring(rules[i].id or "") == ruleID
    local sameAura = tonumber(getRuleAuraSpellID(rules[i])) == auraSpellID
    local sameKind = getRulePrimaryActionType(rules[i]) == "hideaura"
    if sameID and sameAura and sameKind then
      table.remove(rules, i)
    end
  end

  rules[#rules + 1] = {
    id = ruleID,
    name = tostring(model.name or ""),
    enabled = true,
    ownerAuraSpellID = auraSpellID,
    eventSpellID = castSpellIDs[1],
    eventSpellIDs = castSpellIDs,
    conditionMode = conditionMode,
    classToken = tostring(model.loadClassToken or ""):upper(),
    specIDs = normalizeSpellIDList(model.loadSpecIDs),
    ifAll = buildConditionsFromModel({
      talentSpellIDs = model.talentSpellIDs or model.talentSpellID,
      requiredAuraSpellIDs = requiredAuraSpellIDs,
      requireInCombat = model.requireInCombat,
    }),
    thenActions = {
      { type = "hideAura", auraSpellID = auraSpellID },
    },
    elseActions = {},
  }

  self:RefreshContext()
  return true
end

function P:AddSimpleIfRule(ruleID, castSpellID, talentSpellID, auraSpellID, duration, conditionMode, requiredAuraSpellID, requireInCombat)
  return self:AddSimpleIfRuleEx({
    id = ruleID,
    castSpellID = castSpellID,
    talentSpellID = talentSpellID,
    auraSpellID = auraSpellID,
    duration = duration,
    conditionMode = conditionMode,
    requiredAuraSpellID = requiredAuraSpellID,
    requireInCombat = requireInCombat,
  })
end

function P:AddSimpleConsumeRule(ruleID, castSpellID, auraSpellID)
  return self:AddSimpleConsumeRuleEx({
    id = ruleID,
    castSpellID = castSpellID,
    auraSpellID = auraSpellID,
    -- Legacy slash behavior kept strict: consume only when target aura is active.
    requiredAuraSpellID = auraSpellID,
    conditionMode = "all",
  })
end

function P:RemoveUserRule(ruleID, auraSpellID)
  ruleID = tostring(ruleID or "")
  if ruleID == "" then
    return 0
  end
  auraSpellID = tonumber(auraSpellID)
  local rules = ensureUserRules()
  local removed = 0
  for i = #rules, 1, -1 do
    local sameID = tostring(rules[i].id or "") == ruleID
    local sameAura = (auraSpellID == nil) or (tonumber(getRuleAuraSpellID(rules[i])) == auraSpellID)
    if sameID and sameAura then
      table.remove(rules, i)
      removed = removed + 1
    end
  end
  if removed > 0 then
    self:RefreshContext()
  end
  return removed
end

function P:ClearUserRules(auraSpellID)
  if not ns.db then
    return 0
  end
  auraSpellID = tonumber(auraSpellID)
  if auraSpellID == nil then
    local count = #ensureUserRules()
    ns.db.procRules = {}
    self:RefreshContext()
    return count
  end

  local rules = ensureUserRules()
  local removed = 0
  for i = #rules, 1, -1 do
    if tonumber(getRuleAuraSpellID(rules[i])) == auraSpellID then
      table.remove(rules, i)
      removed = removed + 1
    end
  end
  if removed > 0 then
    self:RefreshContext()
  end
  return removed
end

function P:GetTriggerSpellIDs()
  self:EnsureContext()
  return self.triggerSpellIDs or {}
end

function P:GetRevision()
  return tonumber(self.revision) or 0
end

function P:DescribeUserRule(rule)
  if type(rule) ~= "table" then
    return "invalid"
  end
  local id = tostring(rule.id or "?")
  local name = tostring(rule.name or "")
  local eventSpellID = tonumber(rule.eventSpellID) or 0
  local eventSpellIDs = normalizeSpellIDList(rule.eventSpellIDs)
  local castLabel = tostring(eventSpellID)
  if #eventSpellIDs > 1 then
    castLabel = tostring(eventSpellIDs[1]) .. "+" .. tostring(#eventSpellIDs - 1)
  end
  local thenAction = (type(rule.thenActions) == "table" and rule.thenActions[1]) or {}
  local actionType = tostring(thenAction.type or "none")
  local auraSpellID = tonumber(thenAction.auraSpellID) or 0
  local conditionMode = (tostring(rule.conditionMode or "all"):lower() == "any") and "OR" or "AND"
  local conditionCount = type(rule.ifAll) == "table" and #rule.ifAll or 0
  local prefix = id
  if name ~= "" then
    prefix = name .. " [" .. id .. "]"
  end
  return ("%s: onCast=%s if[%s:%d] then=%s(%d)"):format(prefix, castLabel, conditionMode, conditionCount, actionType, auraSpellID)
end

function P:Reset()
  ns.state.procRuleStates = {}
end



