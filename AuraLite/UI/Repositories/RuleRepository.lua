local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Repositories = ns.UIV2.Repositories or {}

local UI = ns.UIV2
local B = UI.Bindings

UI.RuleRepository = UI.RuleRepository or {}
local R = UI.RuleRepository

local function getPrimaryScore(rule)
  local action = (type(rule.thenActions) == "table" and rule.thenActions[1] and tostring(rule.thenActions[1].type or ""):lower()) or ""
  -- Prefer produce/show rules as default editor view.
  if action == "showaura" then
    return 3
  end
  if action == "hideaura" then
    return 2
  end
  return 1
end

function R:ListRulesForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.GetUserRulesForAura then
    return {}
  end
  local rules = ns.ProcRules:GetUserRulesForAura(auraSpellID) or {}
  table.sort(rules, function(a, b)
    local sa = getPrimaryScore(a)
    local sb = getPrimaryScore(b)
    if sa ~= sb then
      return sa > sb
    end
    return tostring(a.id or "") < tostring(b.id or "")
  end)
  return rules
end

function R:GetPrimaryRuleForAura(auraSpellID)
  local rules = self:ListRulesForAura(auraSpellID)
  return rules[1]
end
function R:GetRuleForAuraByMode(auraSpellID, mode)
  local rules = self:ListRulesForAura(auraSpellID)
  local want = (tostring(mode or "produce") == "consume") and "hideaura" or "showaura"
  for i = 1, #rules do
    local action = (type(rules[i].thenActions) == "table" and rules[i].thenActions[1] and tostring(rules[i].thenActions[1].type or ""):lower()) or ""
    if action == want then
      return rules[i]
    end
  end
  return nil
end

function R:GetRulesForAuraByMode(auraSpellID, mode)
  local rules = self:ListRulesForAura(auraSpellID)
  local want = (tostring(mode or "produce") == "consume") and { hideaura = true, decrementaura = true } or { showaura = true }
  local out = {}
  for i = 1, #rules do
    local action = (type(rules[i].thenActions) == "table" and rules[i].thenActions[1] and tostring(rules[i].thenActions[1].type or ""):lower()) or ""
    if want[action] then
      out[#out + 1] = rules[i]
    end
  end
  return out
end

function R:ApplyPrimaryRuleToDraft(draft)
  local auraSpellID = tonumber(draft and draft.spellID)
  if not auraSpellID or auraSpellID <= 0 then
    return draft
  end
  local rules = self:ListRulesForAura(auraSpellID)
  if #rules > 0 and B then
    if B.ApplyRulesToDraft then
      return B:ApplyRulesToDraft(draft, rules)
    end
    if B.ApplyRuleToDraft then
      return B:ApplyRuleToDraft(draft, rules[1])
    end
  end
  return draft
end

function R:ApplyRulesForModeToDraft(draft, mode)
  local auraSpellID = tonumber(draft and draft.spellID)
  if not auraSpellID or auraSpellID <= 0 or not B then
    return draft
  end

  if tostring(mode or "produce") == "consume" then
    local rule = self:GetRuleForAuraByMode(auraSpellID, "consume")
    if rule and B.ApplyRuleToDraft then
      B:ApplyRuleToDraft(draft, rule)
      draft.consumeCastSpellIDs = tostring(draft.castSpellIDs or "")
    end
    return draft
  end

  local rules = self:GetRulesForAuraByMode(auraSpellID, "produce")
  if #rules > 0 then
    if B.ApplyRulesToDraft then
      return B:ApplyRulesToDraft(draft, rules)
    elseif B.ApplyRuleToDraft then
      return B:ApplyRuleToDraft(draft, rules[1])
    end
  end
  return draft
end

function R:DeleteRulesForAuraByMode(auraSpellID, mode)
  if not ns.ProcRules or not ns.ProcRules.RemoveUserRule then
    return 0
  end
  local rules = self:GetRulesForAuraByMode(auraSpellID, mode)
  local removed = 0
  for i = 1, #rules do
    removed = removed + (tonumber(ns.ProcRules:RemoveUserRule(rules[i].id, auraSpellID)) or 0)
  end
  return removed
end

function R:SaveRuleFromDraft(draft)
  if not ns.ProcRules or not B or not B.ToRuleModel then
    return true
  end

  local auraSpellID = tonumber(draft and draft.spellID)
  if not auraSpellID or auraSpellID <= 0 then
    return true
  end

  if (B.IsDirectAuraTracking and B:IsDirectAuraTracking(draft))
    or (B.IsEstimatedTargetDebuffTracking and B:IsEstimatedTargetDebuffTracking(draft))
  then
    self:DeleteRulesForAura(auraSpellID)
    return true
  end

  local mode = (tostring(draft and draft.actionMode or "produce") == "consume") and "consume" or "produce"
  if mode == "consume" then
    local model = B:ToRuleModel(draft, auraSpellID)
    self:DeleteRulesForAuraByMode(auraSpellID, "consume")
    if not model or #((model.castSpellIDs) or {}) == 0 then
      return true
    end
    return ns.ProcRules:AddSimpleConsumeRuleEx(model)
  end

  local models = (B.BuildProduceRuleModels and B:BuildProduceRuleModels(draft, auraSpellID)) or {}
  self:DeleteRulesForAuraByMode(auraSpellID, "produce")
  if #models == 0 then
    return true
  end

  for i = 1, #models do
    local ok, err = ns.ProcRules:AddSimpleIfRuleEx(models[i])
    if not ok then
      return false, err
    end
  end
  return true
end

function R:DeleteRulesForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.GetUserRulesForAura or not ns.ProcRules.RemoveUserRule then
    return 0
  end
  local rules = ns.ProcRules:GetUserRulesForAura(auraSpellID) or {}
  local removed = 0
  for i = 1, #rules do
    removed = removed + (tonumber(ns.ProcRules:RemoveUserRule(rules[i].id, auraSpellID)) or 0)
  end
  return removed
end
function R:DescribeRuleForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.DescribeUserRule then
    return ""
  end
  local rules = self:ListRulesForAura(auraSpellID)
  if #rules == 0 then
    return ""
  end
  local lines = {}
  for i = 1, #rules do
    lines[#lines + 1] = tostring(ns.ProcRules:DescribeUserRule(rules[i]) or "")
  end
  return table.concat(lines, "\n")
end

UI.Repositories.RuleRepository = R


