local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Repositories = ns.UIV2.Repositories or {}

local UI = ns.UIV2
local B = UI.Bindings

UI.RuleRepository = UI.RuleRepository or {}
local R = UI.RuleRepository

local function actionType(rule)
  local a = rule and rule.thenActions and rule.thenActions[1]
  return tostring((a and a.type) or ""):lower()
end

function R:GetPrimaryRuleForAura(auraSpellID)
  if not ns.ProcRules or not ns.ProcRules.GetUserRulesForAura then
    return nil
  end
  local rules = ns.ProcRules:GetUserRulesForAura(auraSpellID) or {}
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

  local base = string.format("ui2_%d", auraSpellID)
  ns.ProcRules:RemoveUserRule(base .. "_produce", auraSpellID)
  ns.ProcRules:RemoveUserRule(base .. "_consume", auraSpellID)

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
