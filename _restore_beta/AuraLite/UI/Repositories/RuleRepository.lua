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

function R:ApplyPrimaryRuleToDraft(draft)
  local auraSpellID = tonumber(draft and draft.spellID)
  if not auraSpellID or auraSpellID <= 0 then
    return draft
  end
  local rule = self:GetPrimaryRuleForAura(auraSpellID)
  if rule and B and B.ApplyRuleToDraft then
    return B:ApplyRuleToDraft(draft, rule)
  end
  return draft
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

  local model = B:ToRuleModel(draft, auraSpellID)
  if not model or #((model.castSpellIDs) or {}) == 0 then
    return true
  end

  ns.ProcRules:RemoveUserRule(model.id, auraSpellID)

  if model.actionMode == "consume" then
    return ns.ProcRules:AddSimpleConsumeRuleEx(model)
  end
  return ns.ProcRules:AddSimpleIfRuleEx(model)
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


