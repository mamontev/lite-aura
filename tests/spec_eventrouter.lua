local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("EventRouter")

suite:case("Restricted fallback does not confirm while same spell is still casting", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 19434
  env.knownSpells[spellID] = true
  env.setPlayerCasting(spellID)

  E.castResolverStates = {
    [spellID] = {
      {
        spellID = spellID,
        attemptAt = env.now - 0.20,
        sourceTag = "HOOK_UseAction",
        restricted = true,
        offGCD = false,
        attemptToken = 1,
        lastErrorAt = 0,
        lastConfirmAt = 0,
        status = "attempted",
        blockReason = nil,
        restrictedFallbackUsed = false,
        score = 0,
        signals = {},
      },
    },
  }

  local confirmed = E:ConfirmPendingCastAttempts()
  T.falsy(confirmed)
  local attempts = E.castResolverStates[spellID]
  T.truthy(type(attempts) == "table" and #attempts == 1)
  T.equal(attempts[1].status, "attempted")
  T.falsy(attempts[1].restrictedFallbackUsed)
end)

suite:case("Restricted fallback does not confirm cast-time spells before success", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 19434
  env.knownSpells[spellID] = true
  env.setPlayerCasting(nil)

  E.castResolverStates = {
    [spellID] = {
      {
        spellID = spellID,
        attemptAt = env.now - 0.20,
        sourceTag = "HOOK_UseAction",
        restricted = true,
        offGCD = false,
        attemptToken = 2,
        lastErrorAt = 0,
        lastConfirmAt = 0,
        status = "attempted",
        blockReason = nil,
        restrictedFallbackUsed = false,
        score = 0,
        signals = {},
      },
    },
  }

  local confirmed = E:ConfirmPendingCastAttempts()
  T.falsy(confirmed)
  local attempts = E.castResolverStates[spellID]
  T.truthy(type(attempts) == "table" and #attempts == 1)
  T.equal(attempts[1].status, "attempted")
  T.falsy(attempts[1].restrictedFallbackUsed)
end)

suite:case("Cooldown edge does not confirm cast-time spells before success", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 19434
  env.knownSpells[spellID] = true
  env.now = 100
  E.playerCastInFlight = {
    [spellID] = true,
  }
  E.castResolverStates = {
    [spellID] = {
      {
        spellID = spellID,
        attemptAt = env.now - 0.04,
        sourceTag = "HOOK_UseAction",
        restricted = false,
        offGCD = false,
        attemptToken = 3,
        lastErrorAt = 0,
        lastConfirmAt = 0,
        status = "attempted",
        blockReason = nil,
        restrictedFallbackUsed = false,
        score = 0,
        signals = {},
      },
    },
  }

  ns.AuraAPI.GetSpellCooldownData = function(_, queriedSpellID)
    if tonumber(queriedSpellID) == spellID then
      return {
        startTime = env.now - 0.02,
        duration = 12,
        expirationTime = env.now + 11.98,
        canCompute = true,
      }
    end
    return nil
  end

  local triggered = E:PollRuleCastEdges()
  T.falsy(triggered)
  local attempts = E.castResolverStates[spellID]
  T.truthy(type(attempts) == "table" and #attempts == 1)
  T.equal(attempts[1].status, "attempted")
end)

suite:case("PLAYER_LOGIN does not auto-open config on first run", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter
  local opened = 0

  ns.Initialize = function()
  end
  ns.RegisterRuntimeEvents = function()
  end
  ns.GroupManager = ns.GroupManager or {}
  ns.GroupManager.EnsureTicker = function()
  end
  E.EnsureCastHooks = function()
  end
  E.EnsureFallbackPoller = function()
  end
  E.RefreshAll = function()
    env.refreshCount = env.refreshCount + 1
  end

  ns.ProfileManager = {
    IsFirstRun = function()
      return true
    end,
  }
  ns.UIV2 = {
    ConfigFrame = {
      Open = function()
        opened = opened + 1
      end,
    },
  }
  ns.ConfigUI = {
    ShowFirstRun = function()
      opened = opened + 1
    end,
  }

  E:PLAYER_LOGIN()
  T.equal(opened, 0)
  T.equal(env.refreshCount, 1)
end)

suite:case("Explicit cooldown tracking rows render even with rules-only mode enabled", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  ns.db.options.rulesOnlyMode = true
  env.setCooldown(23922, {
    startTime = env.now - 1,
    duration = 12,
    expirationTime = env.now + 11,
    canCompute = true,
  })

  table.insert(ns.db.watchlist.player, {
    spellID = 23922,
    displayName = "Shield Slam",
    unit = "player",
    trackingMode = "cooldown",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
  })

  local rowsByGroup = E:BuildRowsForUnit("player")
  local found = nil
  for _, rows in pairs(rowsByGroup or {}) do
    for i = 1, #rows do
      if tonumber(rows[i].spellID) == 23922 then
        found = rows[i]
        break
      end
    end
  end

  T.truthy(found ~= nil)
  T.equal(found.stateKind, "cooldown")
  T.equal(found.stateLabel, "Spell cooldown")
end)

suite:case("Unknown proc aura IDs do not render proxy GCD cooldown rows", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 46968
  ns.TestMode = {
    IsEnabled = function()
      return false
    end,
    BuildPlaceholder = function(_, item)
      return {
        spellID = item.spellID,
      }
    end,
  }
  _G.GetSpellCooldown = function(queriedSpellID)
    queriedSpellID = tonumber(queriedSpellID)
    if queriedSpellID == 61304 or queriedSpellID == spellID then
      return env.now - 0.1, 1.5, 1
    end
    return 0, 0, 1
  end

  ns.AuraAPI.GetSpellCooldownData = function(_, queriedSpellID)
    if tonumber(queriedSpellID) == spellID then
      return {
        startTime = env.now - 0.1,
        duration = 1.5,
        expirationTime = env.now + 1.4,
        canCompute = true,
      }
    end
    return nil
  end

  table.insert(ns.db.watchlist.player, {
    spellID = spellID,
    displayName = "Shockwave Proc",
    unit = "player",
    trackingMode = "cooldown",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
  })

  local rowsByGroup = E:BuildRowsForUnit("player")
  local found = false
  for _, rows in pairs(rowsByGroup or {}) do
    for i = 1, #rows do
      if tonumber(rows[i].spellID) == spellID then
        found = true
        break
      end
    end
  end

  T.falsy(found)
end)

suite:case("Known cooldown spells do not light up from GCD-shaped proxy cooldown data", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 46968
  env.knownSpells[spellID] = true

  ns.TestMode = {
    IsEnabled = function()
      return false
    end,
    BuildPlaceholder = function(_, item)
      return {
        spellID = item.spellID,
      }
    end,
  }

  _G.GetSpellCooldown = function(queriedSpellID)
    queriedSpellID = tonumber(queriedSpellID)
    if queriedSpellID == 61304 or queriedSpellID == spellID then
      return env.now - 0.1, 1.5, 1
    end
    return 0, 0, 1
  end

  ns.AuraAPI.GetSpellCooldownData = function(_, queriedSpellID)
    if tonumber(queriedSpellID) == spellID then
      return {
        startTime = env.now - 0.1,
        duration = 1.5,
        expirationTime = env.now + 1.4,
        canCompute = true,
      }
    end
    return nil
  end

  table.insert(ns.db.watchlist.player, {
    spellID = spellID,
    displayName = "Shockwave",
    unit = "player",
    trackingMode = "cooldown",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
  })

  local rowsByGroup = E:BuildRowsForUnit("player")
  local found = false
  for _, rows in pairs(rowsByGroup or {}) do
    for i = 1, #rows do
      if tonumber(rows[i].spellID) == spellID then
        found = true
        break
      end
    end
  end

  T.falsy(found)
end)

suite:case("Known cooldown spells do not light up after a different recent cast", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  local spellID = 46968
  local otherSpellID = 372608
  env.knownSpells[spellID] = true
  env.knownSpells[otherSpellID] = true

  ns.TestMode = {
    IsEnabled = function()
      return false
    end,
    BuildPlaceholder = function(_, item)
      return {
        spellID = item.spellID,
      }
    end,
  }

  E.lastAnyProcessedCast = {
    spellID = otherSpellID,
    at = env.now - 0.05,
  }

  _G.GetSpellCooldown = function(queriedSpellID)
    queriedSpellID = tonumber(queriedSpellID)
    if queriedSpellID == 61304 then
      return 0, 0, 1
    end
    if queriedSpellID == spellID then
      return env.now - 0.1, 1.5, 1
    end
    return 0, 0, 1
  end

  ns.AuraAPI.GetSpellCooldownData = function(_, queriedSpellID)
    if tonumber(queriedSpellID) == spellID then
      return {
        startTime = env.now - 0.1,
        duration = 1.5,
        expirationTime = env.now + 1.4,
        canCompute = true,
      }
    end
    return nil
  end

  table.insert(ns.db.watchlist.player, {
    spellID = spellID,
    displayName = "Shockwave",
    unit = "player",
    trackingMode = "cooldown",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
  })

  local rowsByGroup = E:BuildRowsForUnit("player")
  local found = false
  for _, rows in pairs(rowsByGroup or {}) do
    for i = 1, #rows do
      if tonumber(rows[i].spellID) == spellID then
        found = true
        break
      end
    end
  end

  T.falsy(found)
end)

suite:case("Cooldown tracking does not create placeholder rows in config preview mode", function()
  local env, ns = makeEnv()
  local E = ns.EventRouter

  ns.TestMode = {
    IsEnabled = function()
      return true
    end,
    BuildPlaceholder = function(_, item)
      return {
        spellID = item.spellID,
      }
    end,
  }

  ns.UIV2 = {
    ConfigFrame = {
      IsShown = function()
        return true
      end,
    },
  }

  table.insert(ns.db.watchlist.player, {
    spellID = 46968,
    displayName = "Shockwave",
    unit = "player",
    trackingMode = "cooldown",
    timerVisual = "icon",
    iconWidth = 36,
    iconHeight = 36,
    barWidth = 94,
    barHeight = 16,
    showTimerText = true,
  })

  local rowsByGroup = E:BuildRowsForUnit("player")
  local found = false
  for _, rows in pairs(rowsByGroup or {}) do
    for i = 1, #rows do
      if tonumber(rows[i].spellID) == 46968 then
        found = true
        break
      end
    end
  end

  T.falsy(found)
end)

return suite
