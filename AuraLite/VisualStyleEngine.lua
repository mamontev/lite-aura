local _, ns = ...

ns.VisualStyle = ns.VisualStyle or {}
local VS = ns.VisualStyle

local function clamp01(value)
  value = tonumber(value) or 0
  if value < 0 then
    return 0
  end
  if value > 1 then
    return 1
  end
  return value
end

local function parseColorCSV(text)
  text = tostring(text or "")
  if text == "" then
    return nil
  end
  local out = {}
  for token in text:gmatch("[^,%s;]+") do
    local n = tonumber(token)
    if not n then
      return nil
    end
    out[#out + 1] = clamp01(n)
    if #out == 3 then
      break
    end
  end
  if #out ~= 3 then
    return nil
  end
  return out[1], out[2], out[3]
end

local function formatColorCSV(r, g, b)
  return string.format("%.2f,%.2f,%.2f", clamp01(r), clamp01(g), clamp01(b))
end

local DEFAULTS = {
  onGain = "off",
  lowTime = "warning",
  maxStacks = "gold",
  glowSpeed = 1.0,
}

local VALID = {
  onGain = {
    off = true,
    soft = true,
    burst = true,
    button = true,
    shine = true,
  },
  lowTime = {
    off = true,
    subtle = true,
    warning = true,
    intense = true,
    pixel = true,
  },
  maxStacks = {
    off = true,
    gold = true,
    heroic = true,
    button = true,
  },
}

local PRESETS = {
  onGain = {
    off = { label = "Off" },
    soft = { label = "Soft" },
    burst = { label = "Burst" },
    button = { label = "Button" },
    shine = { label = "Shine" },
  },
  lowTime = {
    off = { label = "Off" },
    subtle = { label = "Subtle" },
    warning = { label = "Warning" },
    intense = { label = "Intense" },
    pixel = { label = "Pixel" },
  },
  maxStacks = {
    off = { label = "Off" },
    gold = { label = "Gold" },
    heroic = { label = "Heroic" },
    button = { label = "Button" },
  },
}

local function normalizeBucket(bucket, fallback)
  bucket = tostring(bucket or fallback or "off"):lower()
  return bucket
end

function VS:CloneStates(states)
  states = type(states) == "table" and states or {}
  return {
    onGain = normalizeBucket(states.onGain, DEFAULTS.onGain),
    lowTime = normalizeBucket(states.lowTime, DEFAULTS.lowTime),
    maxStacks = normalizeBucket(states.maxStacks, DEFAULTS.maxStacks),
    glowSpeed = math.max(0.25, math.min(3.0, tonumber(states.glowSpeed) or DEFAULTS.glowSpeed)),
  }
end

function VS:NormalizeStates(states)
  local out = self:CloneStates(states)
  for key, valid in pairs(VALID) do
    local bucket = tostring(out[key] or DEFAULTS[key])
    if not valid[bucket] then
      out[key] = DEFAULTS[key]
    end
  end
  return out
end

function VS:GetDefaults()
  return self:CloneStates(DEFAULTS)
end

function VS:GetPresetOptions(kind)
  local raw = PRESETS[kind] or {}
  local out = {}
  for value, meta in pairs(raw) do
    out[#out + 1] = {
      value = value,
      label = tostring(meta.label or value),
    }
  end
  table.sort(out, function(a, b)
    return tostring(a.label) < tostring(b.label)
  end)
  return out
end

function VS:GetStateSummary(states)
  local normalized = self:NormalizeStates(states)
  local gain = PRESETS.onGain[normalized.onGain]
  local low = PRESETS.lowTime[normalized.lowTime]
  local maxStacks = PRESETS.maxStacks[normalized.maxStacks]
  return string.format(
    "Gain: %s | Low Time: %s | Full Charges: %s",
    tostring(gain and gain.label or normalized.onGain),
    tostring(low and low.label or normalized.lowTime),
    tostring(maxStacks and maxStacks.label or normalized.maxStacks)
  )
end

function VS:Resolve(row, runtime)
  local states = self:NormalizeStates(row and row.visualStates)
  local style = {
    scale = 1.0,
    alpha = 1.0,
    borderR = nil,
    borderG = nil,
    borderB = nil,
    borderA = nil,
    glowR = 1.0,
    glowG = 1.0,
    glowB = 1.0,
    glowAlpha = 0,
    glowStyle = "flat",
    barColor = tostring(row and row.barColor or ""),
  }

  runtime = type(runtime) == "table" and runtime or {}
  local justGained = runtime.justGained == true
  local thresholdReached = runtime.thresholdReached == true
  local isMaxStacks = runtime.isMaxStacks == true
  local pulse = tonumber(runtime.pulse or 0)

  if justGained then
    if states.onGain == "soft" then
      style.scale = 1.04
      style.glowR, style.glowG, style.glowB = 0.45, 0.82, 1.0
      style.glowAlpha = 0.16 + (pulse * 0.10)
    elseif states.onGain == "burst" then
      style.scale = 1.09
      style.glowR, style.glowG, style.glowB = 1.0, 0.80, 0.22
      style.glowAlpha = 0.28 + (pulse * 0.16)
      style.glowStyle = "button"
    elseif states.onGain == "button" then
      style.scale = 1.06
      style.glowR, style.glowG, style.glowB = 1.0, 0.74, 0.18
      style.glowAlpha = 0.24 + (pulse * 0.14)
      style.glowStyle = "button"
    elseif states.onGain == "shine" then
      style.scale = 1.03
      style.glowR, style.glowG, style.glowB = 0.65, 0.90, 1.0
      style.glowAlpha = 0.18 + (pulse * 0.12)
      style.glowStyle = "shine"
    end
  end

  if thresholdReached then
    if states.lowTime == "subtle" then
      style.barColor = formatColorCSV(1.0, 0.60, 0.22)
      style.glowR, style.glowG, style.glowB = 1.0, 0.52, 0.16
      style.glowAlpha = math.max(style.glowAlpha, 0.10 + (pulse * 0.08))
    elseif states.lowTime == "warning" then
      style.barColor = formatColorCSV(1.0, 0.30, 0.20)
      style.glowR, style.glowG, style.glowB = 1.0, 0.22, 0.16
      style.glowAlpha = math.max(style.glowAlpha, 0.20 + (pulse * 0.18))
      style.borderR, style.borderG, style.borderB, style.borderA = 1.0, 0.24, 0.16, 0.95
    elseif states.lowTime == "intense" then
      style.barColor = formatColorCSV(1.0, 0.18, 0.14)
      style.glowR, style.glowG, style.glowB = 1.0, 0.12, 0.12
      style.glowAlpha = math.max(style.glowAlpha, 0.32 + (pulse * 0.22))
      style.borderR, style.borderG, style.borderB, style.borderA = 1.0, 0.14, 0.14, 0.98
      style.scale = math.max(style.scale, 1.03)
      style.glowStyle = "button"
    elseif states.lowTime == "pixel" then
      style.barColor = formatColorCSV(1.0, 0.24, 0.24)
      style.glowR, style.glowG, style.glowB = 1.0, 0.22, 0.22
      style.glowAlpha = math.max(style.glowAlpha, 0.22 + (pulse * 0.12))
      style.borderR, style.borderG, style.borderB, style.borderA = 1.0, 0.28, 0.28, 0.98
      style.glowStyle = "pixel"
    end
  end

  if isMaxStacks then
    if states.maxStacks == "gold" then
      if style.barColor == tostring(row and row.barColor or "") then
        style.barColor = formatColorCSV(0.96, 0.82, 0.24)
      end
      style.borderR, style.borderG, style.borderB, style.borderA = 0.96, 0.82, 0.24, 0.95
      style.glowR, style.glowG, style.glowB = 0.96, 0.82, 0.24
      style.glowAlpha = math.max(style.glowAlpha, 0.16 + (pulse * 0.10))
    elseif states.maxStacks == "heroic" then
      if style.barColor == tostring(row and row.barColor or "") then
        style.barColor = formatColorCSV(1.0, 0.84, 0.30)
      end
      style.borderR, style.borderG, style.borderB, style.borderA = 1.0, 0.90, 0.40, 0.98
      style.glowR, style.glowG, style.glowB = 1.0, 0.86, 0.32
      style.glowAlpha = math.max(style.glowAlpha, 0.24 + (pulse * 0.16))
      style.scale = math.max(style.scale, 1.05)
      style.glowStyle = "shine"
    elseif states.maxStacks == "button" then
      if style.barColor == tostring(row and row.barColor or "") then
        style.barColor = formatColorCSV(0.96, 0.82, 0.24)
      end
      style.borderR, style.borderG, style.borderB, style.borderA = 0.96, 0.82, 0.24, 0.96
      style.glowR, style.glowG, style.glowB = 0.96, 0.82, 0.24
      style.glowAlpha = math.max(style.glowAlpha, 0.20 + (pulse * 0.12))
      style.glowStyle = "button"
    end
  end

  return style
end

function VS:HasMeaningfulStates(states)
  local normalized = self:NormalizeStates(states)
  return normalized.onGain ~= "off"
    or normalized.lowTime ~= "off"
    or normalized.maxStacks ~= "off"
end

function VS:ParseColorCSV(text)
  return parseColorCSV(text)
end
