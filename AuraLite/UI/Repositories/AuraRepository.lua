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

local function hydrateDraftWithRule(draft)
  if type(draft) ~= "table" then
    return draft
  end
  if RuleRepo and RuleRepo.ApplyPrimaryRuleToDraft then
    RuleRepo:ApplyPrimaryRuleToDraft(draft)
  end
  return draft
end

local function mapEntryRow(row)
  local item = row and row.item or {}
  local trackingMode = tostring(item.trackingMode or "")
  local triggerLabel = "Rule"
  if tostring(row.unit or "player") == "target" then
    triggerLabel = (trackingMode == "estimated") and "Estimated from your cast" or "Confirmed read"
  end
  return {
    id = tostring(row.key or ""),
    spellID = tonumber(item.spellID) or 0,
    name = (item.displayName and item.displayName ~= "") and tostring(item.displayName) or ((ns.AuraAPI and ns.AuraAPI.GetSpellName and ns.AuraAPI:GetSpellName(item.spellID)) or ("Spell " .. tostring(item.spellID or "?"))),
    unit = tostring(row.unit or "player"),
    group = tostring(item.groupID or ""),
    trigger = triggerLabel,
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
    draft._sourceKey = key
    hydrateDraftWithRule(draft)
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
    local cached = cloneShallow(self._drafts[auraId])
    cached.id = cached.id ~= "" and cached.id or auraId
    cached._sourceKey = cached._sourceKey or auraId
    return hydrateDraftWithRule(cached)
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
  draft._sourceKey = nil
  self._drafts[id] = cloneShallow(draft)
  self._draftMeta[id] = { isNew = true, sourceKey = nil }
  return cloneShallow(draft)
end

function R:EnsureDraftID(draft)
  if type(draft) ~= "table" then
    return nil
  end

  local id = tostring(draft.id or draft._sourceKey or "")
  if id ~= "" then
    draft.id = id
    return id
  end

  self._newCounter = (self._newCounter or 0) + 1
  id = string.format("__new__:%d:%d", math.floor((GetTime() or 0) * 1000), self._newCounter)
  draft.id = id
  draft._sourceKey = nil

  if ns.Debug and ns.Debug.Logf then
    ns.Debug:Logf("AuraRepository generated missing draft id=%s name=%s spellID=%s", tostring(id), tostring(draft.name or ""), tostring(draft.spellID or ""))
  end

  self._draftMeta[id] = self._draftMeta[id] or { isNew = true, sourceKey = nil }
  return id
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

  local draft = self._drafts[auraId] or ensureDraftFromEntry(auraId)
  local auraSpellID = tonumber(draft and draft.spellID)
  local instanceUID = tostring(draft and draft.instanceUID or "")

  if isRealMode() then
    if auraSpellID and auraSpellID > 0 and RuleRepo and RuleRepo.DeleteRulesForAura then
      RuleRepo:DeleteRulesForAura(auraSpellID)
    end

    if not ns.SettingsData or not ns.SettingsData.DeleteEntry then
      return false, "delete unavailable"
    end

    local removed = ns.SettingsData:DeleteEntry(auraId)
    if ns.SettingsData.DeleteEntriesByInstanceUID and instanceUID ~= "" then
      removed = (tonumber(removed) or 0) + (tonumber(ns.SettingsData:DeleteEntriesByInstanceUID(instanceUID, auraSpellID)) or 0)
    end
    if ns.SettingsData.DeleteMatchingEntries and draft then
      removed = (tonumber(removed) or 0) + (tonumber(ns.SettingsData:DeleteMatchingEntries(tostring(draft.unit or "player"), draft)) or 0)
    end
    if ns.SettingsData.CleanupOrphanAuraGroups then
      ns.SettingsData:CleanupOrphanAuraGroups()
    end

    if auraSpellID and auraSpellID > 0 and ns.state and type(ns.state.procRuleStates) == "table" then
      ns.state.procRuleStates[auraSpellID] = nil
    end

    if tonumber(removed) < 1 then
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

  local id = tostring(self:EnsureDraftID(draft) or "")
  if id == "" then
    return false, nil, "missing draft id"
  end

  if isRealMode() and not B:IsDraftID(id) then
    local sourceKey = tostring(draft._sourceKey or id)
    local existingEntry = ns.SettingsData and ns.SettingsData.ResolveEntry and ns.SettingsData:ResolveEntry(sourceKey)
    local existingUID = existingEntry and existingEntry.item and tostring(existingEntry.item.instanceUID or "") or ""
    if existingUID ~= "" then
      draft.instanceUID = existingUID
    end
  end

  if not isRealMode() then
    self._drafts[id] = cloneShallow(draft)
    return true, id
  end

  local model = B:ToSettingsDataModel(draft)
  if isRealMode() and not B:IsDraftID(id) then
    local sourceKey = tostring(draft._sourceKey or id)
    local existingEntry = ns.SettingsData and ns.SettingsData.ResolveEntry and ns.SettingsData:ResolveEntry(sourceKey)
    local existingUID = existingEntry and existingEntry.item and tostring(existingEntry.item.instanceUID or "") or ""
    if existingUID ~= "" then
      model.instanceUID = existingUID
    end
  end
  local sourceKey = tostring(draft._sourceKey or id)
  local meta = self._draftMeta[id] or self._draftMeta[sourceKey] or { isNew = B:IsDraftID(id), sourceKey = B:IsDraftID(id) and nil or sourceKey }

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

  local groupID = tostring(model.groupID or "")
  if groupID ~= "" and ns.SettingsData and ns.SettingsData.UpdateGroupConfig then
    ns.SettingsData:UpdateGroupConfig(groupID, model)
  end

  local savedDraft = cloneShallow(draft)
  local savedEntry = ns.SettingsData and ns.SettingsData.ResolveEntry and ns.SettingsData:ResolveEntry(savedKey)
  if savedEntry and savedEntry.item and tostring(savedEntry.item.instanceUID or "") ~= "" then
    savedDraft.instanceUID = tostring(savedEntry.item.instanceUID)
  elseif model and tostring(model.instanceUID or "") ~= "" then
    savedDraft.instanceUID = tostring(model.instanceUID)
  end
  savedDraft.id = savedKey
  savedDraft._sourceKey = savedKey
  self._drafts[savedKey] = savedDraft
  self._draftMeta[savedKey] = { isNew = false, sourceKey = savedKey }

  if savedKey ~= id then
    self._drafts[id] = nil
    self._draftMeta[id] = nil
  end

  return true, savedKey
end

function R:DuplicateAura(auraId)
  auraId = tostring(auraId or "")
  if auraId == "" then
    return false, nil, "missing aura id"
  end

  local source = self:GetAuraDraft(auraId)
  if type(source) ~= "table" then
    return false, nil, "source aura not found"
  end

  local clone = cloneShallow(source)
  clone.id = nil
  clone._sourceKey = nil
  clone.instanceUID = ""
  local baseName = tostring(clone.name or clone.displayName or "Aura")
  if baseName == "" then
    baseName = "Aura"
  end
  clone.name = baseName .. " Copy"
  clone.displayName = clone.name

  return self:SaveDraft(clone)
end

function R:ExportAura(auraId)
  auraId = tostring(auraId or "")
  if auraId == "" or not ns.ImportExport or not ns.ImportExport.ExportAuraString then
    return nil, "export unavailable"
  end
  return ns.ImportExport:ExportAuraString(auraId)
end

function R:ImportAura(serialized)
  if not ns.ImportExport or not ns.ImportExport.ImportString then
    return false, nil, "import unavailable"
  end
  local result, err = ns.ImportExport:ImportString(serialized, { forceStandalone = true })
  if not result then
    return false, nil, err
  end
  return true, result.auraKey
end


