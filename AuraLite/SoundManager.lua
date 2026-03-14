local _, ns = ...

ns.SoundManager = ns.SoundManager or {}
local S = ns.SoundManager

local SK = SOUNDKIT or {}
local ADDON_SOUND_BASE = "Interface\\AddOns\\AuraLite\\Media\\Sounds\\"
S.lastPlayByKey = S.lastPlayByKey or {}
S.stateThrottle = S.stateThrottle or {
  gain = 0.20,
  low = 0.80,
  expire = 0.25,
  refresh = 1.20,
  consume = 0.25,
}

S.presets = {
  raid_warning = {
    label = "Raid Warning",
    soundKit = SK.RAID_WARNING,
  },
  checkbox_on = {
    label = "Checkbox On",
    soundKit = SK.IG_MAINMENU_OPTION_CHECKBOX_ON,
  },
  checkbox_off = {
    label = "Checkbox Off",
    soundKit = SK.IG_MAINMENU_OPTION_CHECKBOX_OFF,
  },
  map_ping = {
    label = "Map Ping",
    soundKit = SK.UI_MAP_PING,
  },
  auction_window_open = {
    label = "Auction Open",
    soundKit = SK.AUCTION_WINDOW_OPEN,
  },
  soft_ping = {
    label = "Soft Ping (Addon)",
    file = ADDON_SOUND_BASE .. "soft_ping.wav",
  },
  bright_chime = {
    label = "Bright Chime (Addon)",
    file = ADDON_SOUND_BASE .. "bright_chime.wav",
  },
  urgent_alarm = {
    label = "Urgent Alarm (Addon)",
    file = ADDON_SOUND_BASE .. "urgent_alarm.wav",
  },
}

S.stateNames = {
  gain = "Gain",
  low = "Low Time",
  expire = "Expire",
}

S.defaultByState = {
  gain = "checkbox_on",
  low = "raid_warning",
  expire = "checkbox_off",
}

local function normalizeSoundPath(path)
  if type(path) ~= "string" then
    return ""
  end
  path = path:gsub("^%s+", ""):gsub("%s+$", "")
  path = path:gsub("/", "\\")
  repeat
    local before = path
    path = path:gsub("\\\\", "\\")
    if before == path then
      break
    end
  until false
  return path
end

local function safePlaySound(soundKitID, channel)
  if not soundKitID then
    return false
  end
  local ok = pcall(PlaySound, soundKitID, channel or "Master")
  return ok == true
end

local function safePlaySoundFile(path, channel)
  if type(path) ~= "string" or path == "" then
    return false
  end
  local normalized = normalizeSoundPath(path)
  if normalized == "" then
    return false
  end
  local ok, willPlay = pcall(PlaySoundFile, normalized, channel or "Master")
  if not ok then
    return false
  end
  if type(willPlay) == "boolean" then
    if willPlay then
      return true
    end
    if channel ~= "Master" then
      local okFallback, willPlayFallback = pcall(PlaySoundFile, normalized, "Master")
      return okFallback == true and (willPlayFallback == true or willPlayFallback == nil)
    end
    return false
  end
  return willPlay ~= false
end

function S:IsEnabled()
  if not ns.db or not ns.db.options then
    return false
  end

  if ns.db.options.soundEnabled == nil and ns.db.options.soundAlerts ~= nil then
    return ns.db.options.soundAlerts == true
  end

  return ns.db.options.soundEnabled == true
end

function S:GetChannel()
  if ns.db and ns.db.options and type(ns.db.options.soundChannel) == "string" and ns.db.options.soundChannel ~= "" then
    return ns.db.options.soundChannel
  end
  return "Master"
end

function S:NormalizeToken(token)
  if type(token) ~= "string" then
    return "default"
  end
  token = token:lower()
  if token == "" then
    return "default"
  end
  if token == "default" or token == "none" or token == "custom" then
    return token
  end
  if token:find("^lsm:") then
    local name = token:sub(5)
    if name ~= "" then
      return token
    end
    return "default"
  end
  if self.presets[token] then
    return token
  end
  if token:find("^file:") then
    return token
  end
  return "default"
end

function S:GetTokenLabel(token, state)
  token = self:NormalizeToken(token)
  if token == "default" then
    local fallback = self.defaultByState[state] or "raid_warning"
    local preset = self.presets[fallback]
    if preset then
      return "Default (" .. preset.label .. ")"
    end
    return "Default"
  end
  if token == "none" then
    return "None"
  end
  if token == "custom" then
    return "Custom Path"
  end
  if token:find("^lsm:") then
    local name = token:sub(5)
    if name ~= "" then
      return "LSM: " .. name
    end
  end
  local preset = self.presets[token]
  if preset then
    return preset.label
  end
  if token:find("^file:") then
    return "File Path"
  end
  return "Default"
end

function S:GetDropdownOptions(includeDefault)
  local options = {}
  if includeDefault then
    options[#options + 1] = { value = "default", label = "Default" }
  end
  options[#options + 1] = { value = "none", label = "None" }
  for key, cfg in pairs(self.presets) do
    options[#options + 1] = { value = key, label = cfg.label }
  end
  if ns.Media and ns.Media.GetSoundOptions then
    local lsmOptions = ns.Media:GetSoundOptions()
    for i = 1, #lsmOptions do
      options[#options + 1] = lsmOptions[i]
    end
  end
  options[#options + 1] = { value = "custom", label = "Custom Path (global)" }
  table.sort(options, function(a, b)
    if a.value == "default" then
      return true
    end
    if b.value == "default" then
      return false
    end
    if a.value == "none" then
      return true
    end
    if b.value == "none" then
      return false
    end
    if a.value == "custom" then
      return false
    end
    if b.value == "custom" then
      return true
    end
    return a.label < b.label
  end)
  return options
end

function S:ResolveToken(token, state)
  token = self:NormalizeToken(token)

  if token == "default" then
    local defaults = ns.db.options.defaultSounds or {}
    token = self:NormalizeToken(defaults[state] or self.defaultByState[state])
  end

  if token == "none" then
    return nil, nil
  end

  if token == "custom" then
    local custom = ns.db.options.customSounds or {}
    local path = custom[state]
    if type(path) == "string" and path ~= "" then
      return "file", path
    end
    return nil, nil
  end

  if token:find("^file:") then
    local path = normalizeSoundPath(token:sub(6))
    if path ~= "" then
      return "file", path
    end
    return nil, nil
  end

  if token:find("^lsm:") then
    local name = token:sub(5)
    if name ~= "" and ns.Media and ns.Media.Fetch then
      local path = ns.Media:Fetch("sound", name)
      if type(path) == "string" and path ~= "" then
        return "file", normalizeSoundPath(path)
      end
    end
    return nil, nil
  end

  local preset = self.presets[token]
  if preset then
    if preset.soundKit then
      return "kit", preset.soundKit
    end
    if type(preset.file) == "string" and preset.file ~= "" then
      return "file", preset.file
    end
  end

  return nil, nil
end

function S:Play(token, state)
  if not self:IsEnabled() then
    return false
  end

  local refreshPolicy = ns.db and ns.db.options and ns.db.options.soundRefreshPolicy or "first_only"
  if state == "refresh" and refreshPolicy == "first_only" then
    if ns.Debug then
      ns.Debug:Verbosef("Sound refresh suppressed by policy token=%s", tostring(token))
    end
    return false
  end

  local mode, value = self:ResolveToken(token, state)
  if not mode then
    if ns.Debug then
      ns.Debug:Verbosef("Sound skip state=%s token=%s (unresolved)", tostring(state), tostring(token))
    end
    return false
  end

  local throttleKey = tostring(state or "unknown") .. "|" .. tostring(token or "default") .. "|" .. tostring(mode) .. "|" .. tostring(value)
  local now = GetTime()
  local last = self.lastPlayByKey[throttleKey] or 0
  local minInterval = tonumber(self.stateThrottle[state]) or 0.20
  if (now - last) < minInterval then
    if ns.Debug then
      ns.Debug:Verbosef("Sound throttled state=%s token=%s dt=%.3f", tostring(state), tostring(token), now - last)
    end
    return false
  end
  self.lastPlayByKey[throttleKey] = now

  if mode == "kit" then
    local ok = safePlaySound(value, self:GetChannel())
    if ns.Debug then
      ns.Debug:Verbosef("Sound kit state=%s token=%s id=%s ok=%s", tostring(state), tostring(token), tostring(value), tostring(ok))
    end
    return ok
  end

  if mode == "file" then
    local ok = safePlaySoundFile(value, self:GetChannel())
    if ns.Debug then
      ns.Debug:Verbosef("Sound file state=%s token=%s path=%s ok=%s", tostring(state), tostring(token), tostring(value), tostring(ok))
    end
    return ok
  end

  return false
end

function S:Preview(token, state)
  local mode, value = self:ResolveToken(token, state or "gain")
  if not mode then
    return false
  end
  if mode == "kit" then
    return safePlaySound(value, self:GetChannel())
  end
  if mode == "file" then
    return safePlaySoundFile(value, self:GetChannel())
  end
  return false
end

function S:EnsureOptionsDefaults(options)
  options.soundEnabled = options.soundEnabled == true or options.soundAlerts == true
  options.soundChannel = type(options.soundChannel) == "string" and options.soundChannel or "Master"
  options.soundRefreshPolicy = type(options.soundRefreshPolicy) == "string" and options.soundRefreshPolicy or "first_only"

  options.defaultSounds = type(options.defaultSounds) == "table" and options.defaultSounds or {}
  options.customSounds = type(options.customSounds) == "table" and options.customSounds or {}

  for state, fallback in pairs(self.defaultByState) do
    options.defaultSounds[state] = self:NormalizeToken(options.defaultSounds[state] or fallback)
    local path = options.customSounds[state]
    options.customSounds[state] = type(path) == "string" and path or ""
  end
end
