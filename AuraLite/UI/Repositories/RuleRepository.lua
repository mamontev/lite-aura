local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Repositories = ns.UIV2.Repositories or {}

local UI = ns.UIV2
local B = UI.Bindings

UI.RuleRepository = UI.RuleRepository or {}
local R = UI.RuleRepository

function R:ListRulesForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.GetUserRulesForAura then
    return {}
  end
  return ns.ProcRules:GetUserRulesForAura(auraSpellID) or {}
end

function R:GetPrimaryRuleForAura(auraSpellID)
  local rules = self:ListRulesForAura(auraSpellID)
  if #rules == 0 then
    return nil
  end

  for i = 1, #rules do
    local id = tostring(rules[i].id or "")
    if id:find("^ui2_") then
      return rules[i]
    end
  end
  return rules[1]
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

function R:DescribeRuleForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.DescribeUserRule then
    return ""
  end
  local rule = self:GetPrimaryRuleForAura(auraSpellID)
  if not rule then
    return ""
  end
  return tostring(ns.ProcRules:DescribeUserRule(rule) or "")
end

UI.Repositories.RuleRepository = R
