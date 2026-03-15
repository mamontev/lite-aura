local _, ns = ...
local U = ns.Utils

ns.ImportExport = ns.ImportExport or {}
local M = ns.ImportExport

local PAYLOAD_SCHEMA = 1

local function trim(text)
  if U and U.Trim then
    return U.Trim(text)
  end
  return tostring(text or "")
end

local function deepCopy(value)
  if U and U.DeepCopy then
    return U.DeepCopy(value)
  end
  if type(value) ~= "table" then
    return value
  end
  local out = {}
  for k, v in pairs(value) do
    out[deepCopy(k)] = deepCopy(v)
  end
  return out
end

local function normalizeRuleIDSeed(value)
  value = tostring(value or "rule"):lower()
  value = value:gsub("[^%w_]+", "_")
  value = value:gsub("_+", "_")
  value = value:gsub("^_+", "")
  value = value:gsub("_+$", "")
  if value == "" then
    value = "rule"
  end
  return value
end

local function getExistingRuleIDSet()
  local out = {}
  local rules = ns.ProcRules and ns.ProcRules.GetUserRules and ns.ProcRules:GetUserRules() or {}
  for i = 1, #(rules or {}) do
    out[tostring(rules[i].id or "")] = true
  end
  return out
end

local function buildUniqueRuleID(seed, used)
  seed = normalizeRuleIDSeed(seed)
  used = used or {}
  local candidate = seed
  local suffix = 2
  while used[candidate] do
    candidate = string.format("%s_%d", seed, suffix)
    suffix = suffix + 1
  end
  used[candidate] = true
  return candidate
end

local function clearModelIdentity(model)
  model = deepCopy(model or {})
  model.key = nil
  model.id = nil
  model.instanceUID = ""
  return model
end

local function importRules(rules)
  if type(rules) ~= "table" or not ns.db then
    return 0
  end
  ns.db.procRules = type(ns.db.procRules) == "table" and ns.db.procRules or {}
  local usedRuleIDs = getExistingRuleIDSet()
  local added = 0

  for i = 1, #rules do
    local rule = deepCopy(rules[i])
    if type(rule) == "table" then
      rule.id = buildUniqueRuleID(rule.id or ("import_rule_" .. tostring(i)), usedRuleIDs)
      ns.db.procRules[#ns.db.procRules + 1] = rule
      added = added + 1
    end
  end

  if added > 0 and ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  return added
end

local function buildAuraPayload(entryKey)
  if not ns.SettingsData or not ns.SettingsData.ResolveEntry or not ns.SettingsData.BuildEditableModel then
    return nil, "settings data unavailable"
  end
  local entry = ns.SettingsData:ResolveEntry(entryKey)
  if not entry then
    return nil, "aura not found"
  end
  local model = ns.SettingsData:BuildEditableModel(entry)
  if type(model) ~= "table" then
    return nil, "unable to build aura model"
  end
  model = clearModelIdentity(model)
  model.groupID = ""
  model.groupName = ""
  model.groupDirection = "RIGHT"
  model.groupSpacing = 4
  model.groupSort = "list"
  model.groupWrapAfter = 0
  model.groupOffsetX = 0
  model.groupOffsetY = 0
  model.groupOrder = 0

  local spellID = tonumber(entry.item and entry.item.spellID) or tonumber(model.spellID) or 0
  local rules = {}
  if ns.ProcRules and ns.ProcRules.GetUserRulesForAura and spellID > 0 then
    local rawRules = ns.ProcRules:GetUserRulesForAura(spellID) or {}
    for i = 1, #rawRules do
      rules[#rules + 1] = deepCopy(rawRules[i])
    end
  end

  return {
    type = "aura",
    schema = PAYLOAD_SCHEMA,
    aura = {
      model = model,
      rules = rules,
    },
  }
end

local function buildGroupPayload(groupID)
  if not ns.SettingsData or not ns.SettingsData.GetGroupConfig or not ns.SettingsData.ListGroupMembers or not ns.SettingsData.ResolveEntry or not ns.SettingsData.BuildEditableModel then
    return nil, "settings data unavailable"
  end
  groupID = tostring(groupID or "")
  if groupID == "" then
    return nil, "group not selected"
  end

  local cfg = ns.SettingsData:GetGroupConfig(groupID)
  local members = ns.SettingsData:ListGroupMembers(groupID) or {}
  local exportedMembers = {}
  for i = 1, #members do
    local entry = ns.SettingsData:ResolveEntry(members[i].key)
    if entry then
      local model = ns.SettingsData:BuildEditableModel(entry)
      if type(model) == "table" then
        local spellID = tonumber(entry.item and entry.item.spellID) or tonumber(model.spellID) or 0
        local rules = {}
        if ns.ProcRules and ns.ProcRules.GetUserRulesForAura and spellID > 0 then
          local rawRules = ns.ProcRules:GetUserRulesForAura(spellID) or {}
          for r = 1, #rawRules do
            rules[#rules + 1] = deepCopy(rawRules[r])
          end
        end
        model = clearModelIdentity(model)
        exportedMembers[#exportedMembers + 1] = {
          model = model,
          rules = rules,
        }
      end
    end
  end

  local pos = nil
  if ns.db and type(ns.db.positions) == "table" and type(ns.db.positions[groupID]) == "table" then
    pos = deepCopy(ns.db.positions[groupID])
  end

  return {
    type = "group",
    schema = PAYLOAD_SCHEMA,
    group = {
      id = groupID,
      name = tostring(cfg.name or groupID),
      direction = tostring(cfg.layout and cfg.layout.direction or "RIGHT"),
      spacing = tonumber(cfg.layout and cfg.layout.spacing) or 4,
      sort = tostring(cfg.layout and cfg.layout.sort or "list"),
      wrapAfter = tonumber(cfg.layout and cfg.layout.wrapAfter) or 0,
      offsetX = tonumber(cfg.layout and cfg.layout.nudgeX) or 0,
      offsetY = tonumber(cfg.layout and cfg.layout.nudgeY) or 0,
      position = pos,
      members = exportedMembers,
    },
  }
end

local function importAuraPayload(payload, options)
  options = type(options) == "table" and options or {}
  if not ns.SettingsData or not ns.SettingsData.AddEntry then
    return nil, "settings data unavailable"
  end
  local aura = payload and payload.aura
  local model = type(aura) == "table" and deepCopy(aura.model) or nil
  if type(model) ~= "table" then
    return nil, "missing aura payload"
  end

  model.key = nil
  model.id = nil
  model.instanceUID = ""
  model.groupOrder = 0

  if options.forceStandalone ~= false then
    model.groupID = trim(options.groupIDOverride or "")
    if model.groupID == "" then
      model.groupName = ""
      model.groupDirection = "RIGHT"
      model.groupSpacing = 4
      model.groupSort = "list"
      model.groupWrapAfter = 0
      model.groupOffsetX = 0
      model.groupOffsetY = 0
    end
  elseif trim(options.groupIDOverride or "") ~= "" then
    model.groupID = trim(options.groupIDOverride)
  end

  local key, err = ns.SettingsData:AddEntry(model)
  if not key then
    return nil, err or "failed to import aura"
  end

  importRules(aura.rules)

  if ns.RebuildWatchIndex then
    ns:RebuildWatchIndex()
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end

  return {
    kind = "aura",
    auraKey = key,
  }
end

local function importGroupPayload(payload)
  if not ns.SettingsData or not ns.SettingsData.EnsureGroup or not ns.SettingsData.UpdateGroupConfig then
    return nil, "settings data unavailable"
  end
  local group = payload and payload.group
  if type(group) ~= "table" then
    return nil, "missing group payload"
  end

  local displayName = trim(group.name)
  local requestedID = trim(group.id)
  local finalGroupID = requestedID
  if finalGroupID == "" and ns.SettingsData.SuggestGroupID then
    finalGroupID = ns.SettingsData:SuggestGroupID(displayName)
  elseif ns.db and ns.db.groups and ns.db.groups[finalGroupID] and ns.SettingsData.SuggestGroupID then
    finalGroupID = ns.SettingsData:SuggestGroupID(displayName ~= "" and displayName or finalGroupID)
  end
  finalGroupID = ns.SettingsData:EnsureGroup(finalGroupID, displayName)
  ns.SettingsData:UpdateGroupConfig(finalGroupID, {
    groupName = displayName,
    groupDirection = group.direction,
    groupSpacing = group.spacing,
    groupSort = group.sort,
    groupWrapAfter = group.wrapAfter,
    groupOffsetX = group.offsetX,
    groupOffsetY = group.offsetY,
  })

  if ns.db and type(ns.db.positions) == "table" and type(group.position) == "table" then
    ns.db.positions[finalGroupID] = deepCopy(group.position)
  end

  local importedKeys = {}
  local members = type(group.members) == "table" and group.members or {}
  for i = 1, #members do
    local aura = members[i]
    if type(aura) == "table" and type(aura.model) == "table" then
      local model = deepCopy(aura.model)
      model.key = nil
      model.id = nil
      model.instanceUID = ""
      model.groupID = finalGroupID
      model.groupName = displayName
      local key, err = ns.SettingsData:AddEntry(model)
      if not key then
        return nil, err or ("failed to import group member " .. tostring(i))
      end
      importedKeys[#importedKeys + 1] = key
      importRules(aura.rules)
    end
  end

  if ns.RebuildWatchIndex then
    ns:RebuildWatchIndex()
  end
  if ns.EventRouter and ns.EventRouter.RefreshAll then
    ns.EventRouter:RefreshAll()
  end

  return {
    kind = "group",
    groupID = finalGroupID,
    auraKeys = importedKeys,
  }
end

function M:ExportAuraString(entryKey)
  local payload, err = buildAuraPayload(entryKey)
  if not payload then
    return nil, err
  end
  return U.MakeImportString(payload)
end

function M:ExportGroupString(groupID)
  local payload, err = buildGroupPayload(groupID)
  if not payload then
    return nil, err
  end
  return U.MakeImportString(payload)
end

function M:ImportString(serialized, options)
  local parsed, err = U.ParseImportString(serialized)
  if not parsed then
    return nil, err
  end
  if tonumber(parsed.schema) ~= PAYLOAD_SCHEMA then
    return nil, "unsupported import schema"
  end

  local kind = tostring(parsed.type or "")
  if kind == "aura" then
    return importAuraPayload(parsed, options)
  end
  if kind == "group" then
    return importGroupPayload(parsed)
  end
  return nil, "unsupported import payload"
end
