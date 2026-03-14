local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("ProcRules")

suite:case("Stacking show rule caps at max stacks and decrement consume hides at zero", function()
  local env, ns = makeEnv()
  local P = ns.ProcRules

  assert(P:AddSimpleIfRuleEx({
    id = "brace_show",
    castSpellIDs = { 23922 },
    auraSpellID = 386030,
    duration = 16,
    stackBehavior = "add",
    stackAmount = 1,
    maxStacks = 5,
    timerBehavior = "reset",
  }))
  assert(P:AddSimpleConsumeRuleEx({
    id = "brace_consume",
    castSpellIDs = { 6572 },
    auraSpellID = 386030,
    consumeBehavior = "decrement",
  }))

  for _ = 1, 6 do
    T.truthy(P:OnPlayerSpellCast(23922))
    env.advance(0.25)
  end

  local aura = assert(P:GetSyntheticAura(386030))
  T.equal(aura.applications, 5)
  T.approx((aura.expirationTime or 0) - env.now, 16, 0.3)

  for expectedStacks = 4, 1, -1 do
    T.truthy(P:OnPlayerSpellCast(6572))
    aura = assert(P:GetSyntheticAura(386030))
    T.equal(aura.applications, expectedStacks)
  end

  T.truthy(P:OnPlayerSpellCast(6572))
  T.falsy(P:GetSyntheticAura(386030))
end)

suite:case("Extend-to-cap rule increases remaining time but never exceeds cap", function()
  local env, ns = makeEnv()
  local P = ns.ProcRules

  assert(P:AddSimpleIfRuleEx({
    id = "shield_block_extend",
    castSpellIDs = { 2565 },
    auraSpellID = 2565,
    duration = 6,
    stackBehavior = "replace",
    stackAmount = 1,
    maxStacks = 1,
    timerBehavior = "extend",
    maxDuration = 18,
  }))

  T.truthy(P:OnPlayerSpellCast(2565))
  local aura = assert(P:GetSyntheticAura(2565))
  T.approx((aura.expirationTime or 0) - env.now, 6, 0.2)

  env.advance(2)
  T.truthy(P:OnPlayerSpellCast(2565))
  aura = assert(P:GetSyntheticAura(2565))
  T.approx((aura.expirationTime or 0) - env.now, 10, 0.2)

  env.advance(1)
  T.truthy(P:OnPlayerSpellCast(2565))
  aura = assert(P:GetSyntheticAura(2565))
  T.approx((aura.expirationTime or 0) - env.now, 15, 0.2)

  env.advance(1)
  T.truthy(P:OnPlayerSpellCast(2565))
  aura = assert(P:GetSyntheticAura(2565))
  T.approx((aura.expirationTime or 0) - env.now, 18, 0.2)

  env.advance(2)
  T.truthy(P:OnPlayerSpellCast(2565))
  aura = assert(P:GetSyntheticAura(2565))
  T.approx((aura.expirationTime or 0) - env.now, 18, 0.2)
end)

suite:case("Keep timer behavior preserves current remaining time", function()
  local env, ns = makeEnv()
  local P = ns.ProcRules

  T.truthy(P:ShowSyntheticAura(1278009, {
    duration = 8,
    stackBehavior = "replace",
    stackAmount = 1,
    timerBehavior = "reset",
  }, 6343))

  env.advance(3)
  local before = assert(P:GetSyntheticAura(1278009))
  local remainingBefore = (before.expirationTime or 0) - env.now

  P:ShowSyntheticAura(1278009, {
    duration = 8,
    stackBehavior = "replace",
    stackAmount = 1,
    timerBehavior = "keep",
  }, 6343)

  local after = assert(P:GetSyntheticAura(1278009))
  local remainingAfter = (after.expirationTime or 0) - env.now
  T.approx(remainingAfter, remainingBefore, 0.05)
end)

suite:case("Synthetic aura expires on boundary and clears state", function()
  local env, ns = makeEnv()
  local P = ns.ProcRules

  T.truthy(P:ShowSyntheticAura(772, {
    duration = 5,
    stackBehavior = "replace",
    stackAmount = 1,
    timerBehavior = "reset",
    hideOnTimerEnd = true,
  }, 435222))

  T.truthy(P:IsSyntheticAuraActive(772))
  env.advance(5.2)
  T.falsy(P:IsSyntheticAuraActive(772))
  T.falsy(P:GetSyntheticAura(772))
end)

return suite
