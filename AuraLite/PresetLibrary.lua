local _, ns = ...
local U = ns.Utils

ns.PresetLibrary = ns.PresetLibrary or {}
local P = ns.PresetLibrary

local function buildUnits()
  return { player = true, target = true, focus = true, pet = false }
end

local function buildOptions()
  return {
    compactMode = false,
    lowTimeGlow = true,
    lowTimeThreshold = 3,
    soundEnabled = false,
    soundChannel = "Master",
    soundRefreshPolicy = "first_only",
    defaultSounds = {
      gain = "checkbox_on",
      low = "raid_warning",
      expire = "checkbox_off",
    },
    language = "enUS",
    customSounds = {
      gain = "",
      low = "",
      expire = "",
    },
    uiTheme = "modern",
    uiTexturePath = "",
    uiWorkspace = "split",
    uiGuidedMode = true,
    rulesOnlyMode = true,
    debugEnabled = false,
    debugVerbose = false,
    showSource = true,
  }
end

function P:BuildEmptyProfile()
  return {
    locked = true,
    nextInstanceSeq = 1,
    units = buildUnits(),
    options = buildOptions(),
    groups = {},
    positions = {},
    procRules = {},
    watchlist = { player = {}, target = {}, focus = {}, pet = {} },
  }
end

local roleSamples = {
  TANK = {
    player = {
      { spellID = 22812, groupID = "", onlyMine = true, alert = true }, -- Barkskin (sample)
      { spellID = 871, groupID = "", onlyMine = true, alert = true }, -- Shield Wall (sample)
    },
    target = {
      { spellID = 589, groupID = "", onlyMine = true, alert = false }, -- SW:P (sample DoT)
    },
  },
  HEALER = {
    player = {
      { spellID = 31821, groupID = "", onlyMine = true, alert = true }, -- Aura Mastery (sample)
      { spellID = 22812, groupID = "", onlyMine = true, alert = true }, -- Barkskin (sample)
    },
    target = {
      { spellID = 34914, groupID = "", onlyMine = true, alert = false }, -- VT (sample DoT)
    },
  },
  DAMAGER = {
    player = {
      { spellID = 344179, groupID = "", onlyMine = true, alert = true }, -- Maelstrom Weapon (sample)
      { spellID = 2825, groupID = "", onlyMine = false, alert = true }, -- Bloodlust (sample)
    },
    target = {
      { spellID = 589, groupID = "", onlyMine = true, alert = false }, -- SW:P (sample DoT)
    },
  },
}

local function roleToPresetKey(role)
  if role == "TANK" then
    return "TANK"
  end
  if role == "HEALER" then
    return "HEALER"
  end
  return "DAMAGER"
end

function P:BuildRolePreset(role)
  local preset = self:BuildEmptyProfile()
  local key = roleToPresetKey(string.upper(tostring(role or "")))
  local sample = roleSamples[key]
  if sample then
    for unit, rows in pairs(sample) do
      preset.watchlist[unit] = U.DeepCopy(rows)
    end
  end
  return preset
end

function P:ApplyRolePreset(profile, role, replace)
  if type(profile) ~= "table" then
    return
  end
  local preset = self:BuildRolePreset(role)

  if replace then
    for k in pairs(profile) do
      profile[k] = nil
    end
    for k, v in pairs(preset) do
      profile[k] = U.DeepCopy(v)
    end
    return
  end

  profile.units = profile.units or buildUnits()
  profile.options = profile.options or buildOptions()
  profile.groups = profile.groups or {}
  profile.positions = profile.positions or {}
  profile.watchlist = profile.watchlist or { player = {}, target = {}, focus = {}, pet = {} }

  for unit, list in pairs(preset.watchlist) do
    profile.watchlist[unit] = profile.watchlist[unit] or {}
    for _, item in ipairs(list) do
      profile.watchlist[unit][#profile.watchlist[unit] + 1] = U.DeepCopy(item)
    end
  end
end
