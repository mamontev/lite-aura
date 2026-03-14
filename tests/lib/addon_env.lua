local function makeSpellCatalog()
  local byID = {
    [23922] = { name = "Shield Slam", texture = "Interface\\Icons\\INV_Shield_05" },
    [2565] = { name = "Shield Block", texture = "Interface\\Icons\\Ability_Defend" },
    [386030] = { name = "Brace for Impact", texture = "Interface\\Icons\\Ability_Warrior_ShieldBreak" },
    [6343] = { name = "Thunder Clap", texture = "Interface\\Icons\\Spell_Nature_ThunderClap" },
    [435222] = { name = "Thunder Blast", texture = "Interface\\Icons\\Ability_Warrior_Shockwave" },
    [772] = { name = "Rend", texture = "Interface\\Icons\\Ability_Gouge" },
    [1278009] = { name = "Phalanx", texture = "Interface\\Icons\\INV_Shield_06" },
    [6572] = { name = "Revenge", texture = "Interface\\Icons\\Ability_Warrior_Revenge" },
    [1001] = { name = "Alpha", texture = "Interface\\Icons\\INV_Misc_QuestionMark" },
    [1002] = { name = "Beta", texture = "Interface\\Icons\\INV_Misc_QuestionMark" },
    [1003] = { name = "Gamma", texture = "Interface\\Icons\\INV_Misc_QuestionMark" },
    [1004] = { name = "Delta", texture = "Interface\\Icons\\INV_Misc_QuestionMark" },
  }
  local byName = {}
  for spellID, info in pairs(byID) do
    byName[info.name:lower()] = spellID
  end
  return {
    byID = byID,
    byName = byName,
  }
end

local function noop()
end

local function clonePosition(pos)
  if type(pos) ~= "table" then
    return nil
  end
  return {
    point = tostring(pos.point or "CENTER"),
    relativePoint = tostring(pos.relativePoint or "CENTER"),
    x = tonumber(pos.x) or 0,
    y = tonumber(pos.y) or 0,
  }
end

local function loadAddonFile(path, ns)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err, 0)
  end
  return chunk(nil, ns)
end

return function()
  local env = {
    now = 100,
    inCombat = false,
    knownSpells = {
      [23922] = true,
      [2565] = true,
      [386030] = true,
      [6343] = true,
      [435222] = true,
      [772] = true,
      [1278009] = true,
      [6572] = true,
      [1001] = true,
      [1002] = true,
      [1003] = true,
      [1004] = true,
    },
    auraByUnit = {},
    refreshCount = 0,
  }

  local spells = makeSpellCatalog()

  function env.advance(seconds)
    env.now = env.now + (tonumber(seconds) or 0)
  end

  function env.setAura(unit, spellID, aura)
    env.auraByUnit[unit] = env.auraByUnit[unit] or {}
    env.auraByUnit[unit][tonumber(spellID)] = aura
  end

  _G.GetTime = function()
    return env.now
  end

  _G.InCombatLockdown = function()
    return env.inCombat == true
  end

  _G.UnitClass = function(unit)
    if unit == "player" then
      return "Warrior", "WARRIOR"
    end
    return "Unknown", "UNKNOWN"
  end

  _G.GetSpecialization = function()
    return 3
  end

  _G.GetSpecializationInfo = function(specIndex)
    if specIndex == 3 then
      return 73
    end
    return nil
  end

  _G.IsPlayerSpell = function(spellID)
    return env.knownSpells[tonumber(spellID)] == true
  end

  _G.C_ClassTalents = nil
  _G.C_Traits = nil
  _G.C_Spell = {
    GetSpellInfo = function(input)
      local spellID = tonumber(input)
      if not spellID then
        spellID = spells.byName[tostring(input or ""):lower()]
      end
      if not spellID then
        return nil
      end
      local info = spells.byID[spellID]
      if not info then
        return { spellID = spellID, name = "Spell " .. tostring(spellID) }
      end
      return {
        spellID = spellID,
        name = info.name,
        iconID = info.texture,
      }
    end,
  }

  local ns = {
    name = "AuraLite",
    state = {},
    db = {
      watchlist = {
        player = {},
        target = {},
        focus = {},
        pet = {},
      },
      groups = {},
      positions = {},
      procRules = {},
      options = {
        rulesOnlyMode = true,
      },
      nextInstanceSeq = 1,
    },
  }

  ns.Debug = {
    Log = noop,
    Logf = noop,
    Verbosef = noop,
    Throttled = noop,
  }

  ns.SoundManager = {
    NormalizeToken = function(_, token)
      local text = tostring(token or "")
      if text == "" then
        return "default"
      end
      return text
    end,
  }

  ns.AuraAPI = {
    ResolveCustomTexturePath = function(_, path)
      return tostring(path or "")
    end,
    ResolveBarTexturePath = function(_, path)
      return tostring(path or "")
    end,
    GetSpellName = function(_, spellID)
      local info = spells.byID[tonumber(spellID)]
      return info and info.name or ("Spell " .. tostring(spellID or "?"))
    end,
    GetSpellTexture = function(_, spellID)
      local info = spells.byID[tonumber(spellID)]
      return info and info.texture or "Interface\\Icons\\INV_Misc_QuestionMark"
    end,
    GetAuraBySpellID = function(_, unit, spellID)
      local unitAuras = env.auraByUnit[unit]
      return unitAuras and unitAuras[tonumber(spellID)] or nil
    end,
    IsSecretCooldownsRestricted = function()
      return false
    end,
  }

  ns.SpellCatalog = {
    ResolveNameToSpellID = function(_, name)
      return spells.byName[tostring(name or ""):lower()]
    end,
  }

  ns.EventRouter = {
    RefreshAll = function()
      env.refreshCount = env.refreshCount + 1
    end,
  }

  ns.GroupManager = {
    layoutSigByGroup = {},
    frames = {},
  }

  ns.Dragger = {
    pendingPositions = {},
  }

  loadAddonFile("AuraLite/Utils.lua", ns)
  loadAddonFile("AuraLite/AuraWatchlistRegistry.lua", ns)
  loadAddonFile("AuraLite/SettingsData.lua", ns)
  loadAddonFile("AuraLite/ProcRuleEngine.lua", ns)
  loadAddonFile("AuraLite/ImportExport.lua", ns)

  function ns:RebuildWatchIndex()
    self.Registry:Rebuild(self.db)
  end

  ns:RebuildWatchIndex()

  function env.makeModel(overrides)
    local model = ns.SettingsData:BuildDefaultCreateModel()
    model.spellInput = 23922
    model.unit = "player"
    model.displayName = "Shield Slam"
    if type(overrides) == "table" then
      for k, v in pairs(overrides) do
        model[k] = v
      end
    end
    return model
  end

  function env.getEntry(key)
    return ns.SettingsData:ResolveEntry(key)
  end

  function env.getEntryBySpell(unit, spellID, displayName)
    return ns.SettingsData:FindEntryBySpell(unit, spellID, displayName)
  end

  function env.getSynthetic(auraSpellID)
    return ns.ProcRules:GetSyntheticAura(auraSpellID)
  end

  function env.clonePosition(pos)
    return clonePosition(pos)
  end

  return env, ns
end
