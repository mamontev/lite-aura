local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2
local E = UI.Events

UI.State = UI.State or {}
local S = UI.State

S._data = S._data or {
  selectedAuraId = nil,
  activeTab = "Tracking",
  dirty = false,
  filters = {
    search = "",
    unit = "all",
    group = "all",
  },
  preview = {
    playing = false,
    startedAt = 0,
    duration = 0,
  },
}

local function shallowCopy(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    out[k] = v
  end
  return out
end

function S:Get()
  local snap = shallowCopy(self._data)
  snap.filters = shallowCopy(self._data.filters)
  snap.preview = shallowCopy(self._data.preview)
  return snap
end

function S:SetSelectedAura(auraId, source)
  if self._data.selectedAuraId == auraId then
    return
  end
  self._data.selectedAuraId = auraId
  if E then
    E:Emit(E.Names.AURA_SELECTED, { auraId = auraId, source = source or "unknown" })
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end

function S:SetActiveTab(tabKey)
  tabKey = tostring(tabKey or "Tracking")
  if self._data.activeTab == tabKey then
    return
  end
  self._data.activeTab = tabKey
  if E then
    E:Emit(E.Names.TAB_CHANGED, { tab = tabKey })
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end

function S:SetDirty(isDirty)
  local nextValue = isDirty == true
  if self._data.dirty == nextValue then
    return
  end
  self._data.dirty = nextValue
  if E then
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end

function S:SetFilter(key, value)
  if type(key) ~= "string" or key == "" then
    return
  end
  local current = self._data.filters[key]
  if current == value then
    return
  end
  self._data.filters[key] = value
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = key, value = value, filters = shallowCopy(self._data.filters) })
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end

function S:ResetFilters()
  self._data.filters.search = ""
  self._data.filters.unit = "all"
  self._data.filters.group = "all"
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "*", value = nil, filters = shallowCopy(self._data.filters) })
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end

function S:SetPreview(playing, duration)
  self._data.preview.playing = playing == true
  self._data.preview.duration = tonumber(duration) or 0
  self._data.preview.startedAt = GetTime() or 0
  if E then
    E:Emit(E.Names.STATE_CHANGED, self:Get())
  end
end
