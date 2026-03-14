return function(T, Env, root)
  T:add("proc rule stack add caps at max stacks", function()
    local env = Env.new(root)
    env.ns.ProcRules:Reset()
    env.ns.db.procRules = {}

    local ok = env.ns.ProcRules:AddSimpleIfRuleEx({
      id = "brace_show",
      name = "Brace for Impact",
      castSpellIDs = { 23922 },
      auraSpellID = 386030,
      duration = 16,
      conditionMode = "all",
      actionMode = "produce",
      stackBehavior = "add",
      stackAmount = 1,
      maxStacks = 5,
      timerBehavior = "reset",
    })
    T:assertTrue(ok, "rule creation should succeed")

    for _ = 1, 7 do
      env.ns.ProcRules:OnPlayerSpellCast(23922)
      env:advance(0.1)
    end

    local state = env.ns.ProcRules:GetSyntheticAura(386030)
    T:assertTrue(state ~= nil, "synthetic aura should be active")
    T:assertEqual(state.applications, 5, "stacks should cap at configured max")
  end)

  T:add("proc rule extend to cap keeps remaining time bounded", function()
    local env = Env.new(root)
    env.ns.ProcRules:Reset()
    env.ns.db.procRules = {}

    local ok = env.ns.ProcRules:AddSimpleIfRuleEx({
      id = "shield_block_show",
      name = "Shield Block",
      castSpellIDs = { 2565 },
      auraSpellID = 2565,
      duration = 6,
      conditionMode = "all",
      actionMode = "produce",
      stackBehavior = "replace",
      stackAmount = 1,
      maxStacks = 1,
      timerBehavior = "extend",
      maxDuration = 18,
    })
    T:assertTrue(ok, "rule creation should succeed")

    env.ns.ProcRules:OnPlayerSpellCast(2565)
    env:advance(1)
    env.ns.ProcRules:OnPlayerSpellCast(2565)
    env:advance(1)
    env.ns.ProcRules:OnPlayerSpellCast(2565)
    env:advance(1)
    env.ns.ProcRules:OnPlayerSpellCast(2565)

    local state = env.ns.ProcRules:GetSyntheticAura(2565)
    T:assertTrue(state ~= nil, "synthetic aura should still be active")
    T:assertNear(state.expirationTime - env.clock.now, 18, 0.01, "remaining time should be capped at maxDuration")
  end)

  T:add("decrement synthetic aura removes one stack at a time", function()
    local env = Env.new(root)
    env.ns.state.procRuleStates = {
      [386030] = {
        active = true,
        applications = 3,
        startTime = env.clock.now,
        expirationTime = env.clock.now + 10,
        duration = 10,
      },
    }

    T:assertTrue(env.ns.ProcRules:DecrementSyntheticAura(386030, 23922))
    local state1 = env.ns.ProcRules:GetSyntheticAura(386030)
    T:assertEqual(state1.applications, 2, "first decrement should remove one stack")

    T:assertTrue(env.ns.ProcRules:DecrementSyntheticAura(386030, 23922))
    local state2 = env.ns.ProcRules:GetSyntheticAura(386030)
    T:assertEqual(state2.applications, 1, "second decrement should remove one stack")

    T:assertTrue(env.ns.ProcRules:DecrementSyntheticAura(386030, 23922))
    T:assertFalse(env.ns.ProcRules:IsSyntheticAuraActive(386030), "third decrement should remove the aura")
  end)
end
