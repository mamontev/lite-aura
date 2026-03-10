local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2
local B = UI.Bindings
local RuleRepo = UI.RuleRepository

UI.AuraRepository = UI.AuraRepository or {}
local R = UI.AuraRepository

R._drafts = R._drafts or {}
R._draftMeta = R._draftMeta or {}
R._newCounter = R._newCounter or 0

local function cloneShallow(tbl)
  local out = {}
  for k, v in pairs(tbl or {}) do
    if type(v) == "table" then
      local t = {}
      for k2, v2 in pairs(v) do
        t[k2] = v2
      end
      out[k] = t
    else
      out[k] = v
    end
  end
  return out
end

local function isRealMode()
  return ns.SettingsData and type(ns.SettingsData.ListEntries) == "function"
end

local function mapEntryRow(row)
  local item = row and row.item or {}
  return {
    id = tostring(row.key or ""),
    spellID = tonumber(item.spellID) or 0,
    name = (item.displayName and item.displayName ~= "") and tostring(item.displayName) or ((ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(item.spellID)) or ("Spell " .. tostring(item.spellID or "?"))),
    unit = tostring(row.unit or "player"),
    group = tostring(item.groupID or "important_procs"),
    trigger = "Rule",
    status = (tonumber(item.spellID) or 0) > 0 and "ok" or "warn",
    icon = (ns.AuraAPI and ns.AuraAPI.GetSpellTexture and ns.AuraAPI:GetSpellTexture(item.spellID)) or 134400,
  }
end

local function ensureDraftFromEntry(key)
  if R._drafts[key] then
    return R._drafts[key]
  end
  local entry = ns.SettingsData and ns.SettingsData.ResolveEntry and ns.SettingsData:ResolveEntry(key)
  local model = entry and ns.SettingsData:BuildEditableModel(entry) or nil
  if model and B and B.DraftFromEditableModel then
    local draft = B:DraftFromEditableModel(model)
    draft.id = key
    R._drafts[key] = draft
    R._draftMeta[key] = { isNew = false, sourceKey = key }
    return draft
  end
  return nil
end

function R:ListAuras(state)
  if isRealMode() then
    local filter = state and state.filters and state.filters.search or ""
    local rows = ns.SettingsData:ListEntries(filter) or {}
    local out = {}
    for i = 1, #rows do
      out[#out + 1] = mapEntryRow(rows[i])
    end

    for id, meta in pairs(self._draftMeta) do
      if meta and meta.isNew and self._drafts[id] then
        local d = self._drafts[id]
        out[#out + 1] = {
          id = id,
          spellID = tonumber(d.spellID) or 0,
          name = tostring(d.name or "New Aura"),
          unit = tostring(d.unit or "player"),
          group = tostring(d.group or "custom"),
          trigger = "Draft",
          status = "warn",
          icon = 134400,
        }
      end
    end

    table.sort(out, function(a, b)
      return tostring(a.name) < tostring(b.name)
    end)
    return out
  end

  -- Fallback local mock mode.
  local fallback = {
    { id = "aura_1278009", spellID = 1278009, name = "Phalanx", unit = "player", group = "Important Procs", trigger = "Cast", status = "ok", icon = 132341 },
    { id = "aura_871", spellID = 871, name = "Shield Wall", unit = "player", group = "Defensives", trigger = "Aura", status = "ok", icon = 132362 },
  }
  return fallback
end

function R:GetAuraDraft(auraId)
  auraId = tostring(auraId or "")
  if auraId == "" then
    return B:NewDraft("")
  end

  if self._drafts[auraId] then
    return cloneShallow(self._drafts[auraId])
  end

  if isRealMode() then
    local draft = ensureDraftFromEntry(auraId)
    if draft then
      return cloneShallow(draft)
    end
  end

  return B:NewDraft(auraId)
end

function R:CreateDraft()
  self._newCounter = (self._newCounter or 0) + 1
  local id = string.format("__new__:%d:%d", math.floor((GetTime() or 0) * 1000), self._newCounter)
  local draft = B:NewDraft(id)
  self._drafts[id] = cloneShallow(draft)
  self._draftMeta[id] = { isNew = true, sourceKey = nil }
  return cloneShallow(draft)
end

function R:DeleteAura(auraId)
  auraId = tostring(auraId or "")
  if auraId == "" then
    return false, "missing aura id"
  end

  local meta = self._draftMeta[auraId]
  if meta and meta.isNew then
    self._drafts[auraId] = nil
    self._draftMeta[auraId] = nil
    return true
  end

  if isRealMode() then
    local draft = self._drafts[auraId] or ensureDraftFromEntry(auraId)
    local auraSpellID = tonumber(draft and draft.spellID)
    if auraSpellID and auraSpellID > 0 and RuleRepo and RuleRepo.DeleteRulesForAura then
      RuleRepo:DeleteRulesForAura(auraSpellID)
    end

    if not ns.SettingsData or not ns.SettingsData.DeleteEntry then
      return false, "delete unavailable"
    end

    local removed = ns.SettingsData:DeleteEntry(auraId)
    if tonumber(removed) ~= 1 then
      return false, "delete failed"
    end
  end

  self._drafts[auraId] = nil
  self._draftMeta[auraId] = nil
  return true
end
function R:SaveDraft(draft)
  if type(draft) ~= "table" then
    return false, nil, "invalid draft"
  end

  local id = tostring(draft.id or "")
  if id == "" then
    return false, nil, "missing draft id"
  end

  if not isRealMode() then
    self._drafts[id] = cloneShallow(draft)
    return true, id
  end

  local model = B:ToSettingsDataModel(draft)
  if ns.Debug and ns.Debug.Logf then
    ns.Debug:Logf("AuraRepository SaveDraft id=%s metaSource=%s draft.unit=%s model.unit=%s spellID=%s", tostring(id), tostring((self._draftMeta[id] and self._draftMeta[id].sourceKey) or id), tostring(draft.unit or ""), tostring(model and model.unit or ""), tostring(draft.spellID or ""))
  end
  local meta = self._draftMeta[id] or { isNew = B:IsDraftID(id), sourceKey = B:IsDraftID(id) and nil or id }

  local savedKey, err
  if meta.isNew or not meta.sourceKey then
    savedKey, err = ns.SettingsData:AddEntry(model)
    if not savedKey then
      return false, nil, err or "add failed"
    end
  else
    savedKey, err = ns.SettingsData:UpdateEntry(meta.sourceKey, model)
    if not savedKey then
      return false, nil, err or "update failed"
    end
  end

  local savedDraft = cloneShallow(draft)
  savedDraft.id = savedKey
  self._drafts[savedKey] = savedDraft
  self._draftMeta[savedKey] = { isNew = false, sourceKey = savedKey }

  if savedKey ~= id then
    self._drafts[id] = nil
    self._draftMeta[id] = nil
  end

  return true, savedKey
end


