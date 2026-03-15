local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("RuleRepository")

local function loadUIFile(path, ns)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err, 0)
  end
  return chunk(nil, ns)
end

suite:case("Multiple produce triggers save as separate rules with per-trigger stack amounts", function()
  local _, ns = makeEnv()
  ns.UIV2 = ns.UIV2 or {}
  ns.UIV2.Repositories = ns.UIV2.Repositories or {}
  ns.UIV2.Bindings = ns.UIV2.Bindings or {}

  loadUIFile("AuraLite/UI/UIBindings.lua", ns)
  loadUIFile("AuraLite/UI/Repositories/RuleRepository.lua", ns)

  local B = ns.UIV2.Bindings
  local R = ns.UIV2.RuleRepository
  local P = ns.ProcRules

  local draft = B:NewDraft("player:precise")
  draft.name = "Precise Shots"
  draft.spellID = "257622"
  draft.unit = "player"
  draft.actionMode = "produce"
  draft.duration = 12
  draft.stackBehavior = "add"
  draft.maxStacks = 2
  draft.produceTriggers = {
    { spellID = 19434, stackAmount = 2 },
    { spellID = 257044, stackAmount = 1 },
  }

  local ok, err = R:SaveRuleFromDraft(draft)
  T.truthy(ok, tostring(err or "save failed"))

  local rules = P:GetUserRulesForAura(257622)
  T.equal(#rules, 2)

  local byTrigger = {}
  for i = 1, #rules do
    local rule = rules[i]
    local spellID = tonumber(rule.eventSpellIDs and rule.eventSpellIDs[1])
    local action = rule.thenActions and rule.thenActions[1] or {}
    byTrigger[spellID] = {
      id = tostring(rule.id or ""),
      stackAmount = tonumber(action.stackAmount or action.stacks) or 0,
      maxStacks = tonumber(action.maxStacks) or 0,
    }
  end

  T.equal(byTrigger[19434].stackAmount, 2)
  T.equal(byTrigger[19434].maxStacks, 2)
  T.equal(byTrigger[257044].stackAmount, 1)
  T.equal(byTrigger[257044].maxStacks, 2)
end)

suite:case("Save workflow preserves multiple produce triggers after draft refresh", function()
  local _, ns = makeEnv()
  ns.UIV2 = ns.UIV2 or {}
  ns.UIV2.Repositories = ns.UIV2.Repositories or {}
  ns.UIV2.Bindings = ns.UIV2.Bindings or {}

  loadUIFile("AuraLite/UI/UIBindings.lua", ns)
  loadUIFile("AuraLite/UI/Repositories/RuleRepository.lua", ns)
  loadUIFile("AuraLite/UI/Repositories/AuraRepository.lua", ns)

  local B = ns.UIV2.Bindings
  local RuleRepo = ns.UIV2.RuleRepository
  local AuraRepo = ns.UIV2.AuraRepository

  local draft = AuraRepo:CreateDraft()
  draft.name = "Precise Shots"
  draft.spellID = "260240"
  draft.unit = "player"
  draft.actionMode = "produce"
  draft.duration = 12
  draft.stackBehavior = "add"
  draft.maxStacks = 2
  draft.produceTriggers = {
    { spellID = 19434, stackAmount = 2 },
    { spellID = 257044, stackAmount = 1 },
  }

  local ok, savedKey, err = AuraRepo:SaveDraft(draft)
  T.truthy(ok, tostring(err or "draft save failed"))

  local persisted = ns.Utils.DeepCopy(draft)
  persisted.id = savedKey
  persisted._sourceKey = savedKey
  local entry = ns.SettingsData:ResolveEntry(savedKey)
  persisted.instanceUID = entry and entry.item and tostring(entry.item.instanceUID or "") or ""

  local rok, rerr = RuleRepo:SaveRuleFromDraft(persisted)
  T.truthy(rok, tostring(rerr or "rule save failed"))

  local refreshed = AuraRepo:GetAuraDraft(savedKey)
  local triggers = B:GetProduceTriggers(refreshed)
  T.equal(#triggers, 2)
  T.equal(tonumber(triggers[1].spellID), 19434)
  T.equal(tonumber(triggers[1].stackAmount), 2)
  T.equal(tonumber(triggers[2].spellID), 257044)
  T.equal(tonumber(triggers[2].stackAmount), 1)
end)

suite:case("Repository reload preserves per-trigger stack amounts and duration", function()
  local _, ns = makeEnv()
  ns.UIV2 = ns.UIV2 or {}
  ns.UIV2.Repositories = ns.UIV2.Repositories or {}
  ns.UIV2.Bindings = ns.UIV2.Bindings or {}

  loadUIFile("AuraLite/UI/UIBindings.lua", ns)
  loadUIFile("AuraLite/UI/Repositories/RuleRepository.lua", ns)
  loadUIFile("AuraLite/UI/Repositories/AuraRepository.lua", ns)

  local B = ns.UIV2.Bindings
  local RuleRepo = ns.UIV2.RuleRepository
  local AuraRepo = ns.UIV2.AuraRepository

  local draft = AuraRepo:CreateDraft()
  draft.name = "Precise Shots"
  draft.spellID = "260240"
  draft.unit = "player"
  draft.actionMode = "produce"
  draft.duration = 15
  draft.stackBehavior = "add"
  draft.maxStacks = 2
  draft.produceTriggers = {
    { spellID = 19434, stackAmount = 2 },
    { spellID = 257044, stackAmount = 1 },
  }

  local ok, savedKey, err = AuraRepo:SaveDraft(draft)
  T.truthy(ok, tostring(err or "draft save failed"))

  local persisted = ns.Utils.DeepCopy(draft)
  persisted.id = savedKey
  persisted._sourceKey = savedKey
  local entry = ns.SettingsData:ResolveEntry(savedKey)
  persisted.instanceUID = entry and entry.item and tostring(entry.item.instanceUID or "") or ""

  local rok, rerr = RuleRepo:SaveRuleFromDraft(persisted)
  T.truthy(rok, tostring(rerr or "rule save failed"))

  AuraRepo._drafts = {}
  AuraRepo._draftMeta = {}

  local reloaded = AuraRepo:GetAuraDraft(savedKey)
  local triggers = B:GetProduceTriggers(reloaded)
  T.equal(tonumber(reloaded.duration), 15)
  T.equal(#triggers, 2)
  T.equal(tonumber(triggers[1].spellID), 19434)
  T.equal(tonumber(triggers[1].stackAmount), 2)
  T.equal(tonumber(triggers[2].spellID), 257044)
  T.equal(tonumber(triggers[2].stackAmount), 1)
end)

return suite
