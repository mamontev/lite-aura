local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("SettingsData")

suite:case("UpdateEntry preserves instanceUID and savedPosition across repeated updates", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local key = assert(D:AddEntry(env.makeModel({
    spellInput = 2565,
    displayName = "Shield Block",
    savedPosition = {
      point = "LEFT",
      relativePoint = "LEFT",
      x = 320,
      y = 180,
    },
    barWidth = 160,
    barHeight = 22,
    barColor = "0.10,0.20,0.30",
  })))

  local entry = assert(D:ResolveEntry(key))
  local stableUID = entry.item.instanceUID
  local stablePos = env.clonePosition(entry.item.savedPosition)

  for i = 1, 24 do
    local model = D:BuildEditableModel(assert(D:ResolveEntry(key)))
    model.displayName = "Shield Block " .. tostring(i)
    model.iconWidth = 36 + i
    model.barWidth = 140 + i
    local resultKey = assert(D:UpdateEntry(key, model))
    T.equal(resultKey, key, "same-unit update should keep entry key stable")
    local updated = assert(D:ResolveEntry(key))
    T.equal(updated.item.instanceUID, stableUID, "instanceUID must remain immutable on update")
    T.same(updated.item.savedPosition, stablePos, "savedPosition must survive update")
  end
end)

suite:case("Registry rebuild preserves modern watch item fields", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local key = assert(D:AddEntry(env.makeModel({
    spellInput = 386030,
    displayName = "Brace for Impact",
    groupID = "defensive",
    timerVisual = "iconbar",
    iconWidth = 44,
    iconHeight = 45,
    barWidth = 180,
    barHeight = 20,
    showTimerText = false,
    barColor = "0.11,0.22,0.33",
    barSide = "left",
    loadClassToken = "WARRIOR",
    loadSpecIDs = { 73 },
    savedPosition = {
      point = "TOPLEFT",
      relativePoint = "TOPLEFT",
      x = 111,
      y = -222,
    },
  })))

  local before = assert(D:ResolveEntry(key))
  local stableUID = before.item.instanceUID
  ns:RebuildWatchIndex()
  local after = assert(D:ResolveEntry(key))

  T.equal(after.item.instanceUID, stableUID)
  T.same(after.item.savedPosition, before.item.savedPosition)
  T.equal(after.item.iconWidth, 44)
  T.equal(after.item.iconHeight, 45)
  T.equal(after.item.barWidth, 180)
  T.equal(after.item.barHeight, 20)
  T.equal(after.item.showTimerText, false)
  T.equal(after.item.barColor, "0.11,0.22,0.33")
  T.equal(after.item.barSide, "left")
  T.equal(after.item.loadClassToken, "WARRIOR")
  T.same(after.item.loadSpecIDs, { 73 })
end)

suite:case("Stack metadata survives watch item roundtrip across reload-style rebuild", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local key = assert(D:AddEntry(env.makeModel({
    spellInput = 260240,
    displayName = "Precise Shots",
    stackBehavior = "add",
    stackAmount = 2,
    maxStacks = 2,
    consumeBehavior = "decrement",
    castSpellIDs = { 19434, 257044 },
  })))

  local before = assert(D:ResolveEntry(key))
  T.equal(before.item.stackBehavior, "add")
  T.equal(before.item.stackAmount, 2)
  T.equal(before.item.maxStacks, 2)
  T.equal(before.item.consumeBehavior, "decrement")

  ns:RebuildWatchIndex()

  local editable = D:BuildEditableModel(assert(D:ResolveEntry(key)))
  T.equal(editable.stackBehavior, "add")
  T.equal(editable.stackAmount, 2)
  T.equal(editable.maxStacks, 2)
  T.equal(editable.consumeBehavior, "decrement")
end)

suite:case("DeleteGroup removes only the container and leaves children standalone", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local firstKey = assert(D:AddEntry(env.makeModel({ spellInput = 1001, displayName = "Alpha" })))
  local secondKey = assert(D:AddEntry(env.makeModel({ spellInput = 1002, displayName = "Beta" })))

  T.truthy(D:SetEntryGroup(firstKey, "defensive"))
  T.truthy(D:SetEntryGroup(secondKey, "defensive"))

  local groups = D:ListGroupsDetailed()
  T.equal(#groups, 1)
  T.equal(groups[1].id, "defensive")
  T.equal(groups[1].count, 2)

  local removed = D:DeleteGroup("defensive")
  T.equal(removed, 2)
  T.equal(#D:ListGroupsDetailed(), 0)
  T.equal(assert(D:ResolveEntry(firstKey)).item.groupID, "")
  T.equal(assert(D:ResolveEntry(secondKey)).item.groupID, "")
  T.equal(assert(D:ResolveEntry(firstKey)).item.groupOrder, 0)
  T.equal(assert(D:ResolveEntry(secondKey)).item.groupOrder, 0)
end)

suite:case("MoveGroupMember swaps manual order deterministically", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local firstKey = assert(D:AddEntry(env.makeModel({ spellInput = 1001, displayName = "Alpha" })))
  local secondKey = assert(D:AddEntry(env.makeModel({ spellInput = 1002, displayName = "Beta" })))
  local thirdKey = assert(D:AddEntry(env.makeModel({ spellInput = 1003, displayName = "Gamma" })))

  D:SetEntryGroup(firstKey, "ordered")
  D:SetEntryGroup(secondKey, "ordered")
  D:SetEntryGroup(thirdKey, "ordered")

  local membersBefore = D:ListGroupMembers("ordered")
  T.same({ membersBefore[1].name, membersBefore[2].name, membersBefore[3].name }, { "Alpha", "Beta", "Gamma" })
  T.truthy(D:MoveGroupMember("ordered", thirdKey, "up"))
  local membersAfter = D:ListGroupMembers("ordered")
  T.same({ membersAfter[1].name, membersAfter[2].name, membersAfter[3].name }, { "Alpha", "Gamma", "Beta" })
end)

suite:case("InstallWarriorExamples is idempotent and preserves identity", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData

  local changedFirst = D:InstallWarriorExamples()
  T.truthy(changedFirst >= 2)

  local braceFirst = assert(D:FindEntryBySpell("player", 386030, "Brace for Impact"))
  local blockFirst = assert(D:FindEntryBySpell("player", 2565, "Shield Block"))
  local braceUID = braceFirst.item.instanceUID
  local blockUID = blockFirst.item.instanceUID

  local changedSecond = D:InstallWarriorExamples()
  T.truthy(changedSecond >= 2)

  local braceSecond = assert(D:FindEntryBySpell("player", 386030, "Brace for Impact"))
  local blockSecond = assert(D:FindEntryBySpell("player", 2565, "Shield Block"))
  T.equal(braceSecond.item.instanceUID, braceUID)
  T.equal(blockSecond.item.instanceUID, blockUID)

  local braceCount, blockCount = 0, 0
  for _, entry in ipairs(D:ListEntries("")) do
    if entry.item.spellID == 386030 then
      braceCount = braceCount + 1
    elseif entry.item.spellID == 2565 then
      blockCount = blockCount + 1
    end
  end
  T.equal(braceCount, 1)
  T.equal(blockCount, 1)
end)

suite:case("Stress loop preserves unique immutable identities through update, rebuild, group, and ungroup", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local keys = {
    assert(D:AddEntry(env.makeModel({ spellInput = 1001, displayName = "Alpha" }))),
    assert(D:AddEntry(env.makeModel({ spellInput = 1002, displayName = "Beta" }))),
    assert(D:AddEntry(env.makeModel({ spellInput = 1003, displayName = "Gamma" }))),
    assert(D:AddEntry(env.makeModel({ spellInput = 1004, displayName = "Delta" }))),
  }

  local stableUIDByKey = {}
  for i = 1, #keys do
    local entry = assert(D:ResolveEntry(keys[i]))
    stableUIDByKey[keys[i]] = entry.item.instanceUID
  end

  for step = 1, 60 do
    local key = keys[((step - 1) % #keys) + 1]
    if step % 4 == 1 then
      local model = D:BuildEditableModel(assert(D:ResolveEntry(key)))
      model.displayName = model.displayName .. "_" .. tostring(step)
      model.iconWidth = 32 + (step % 8)
      model.barHeight = 16 + (step % 3)
      assert(D:UpdateEntry(key, model))
    elseif step % 4 == 2 then
      local groupID = (step % 8 == 2) and "alpha_pack" or "beta_pack"
      assert(D:SetEntryGroup(key, groupID))
    elseif step % 4 == 3 then
      local entry = assert(D:ResolveEntry(key))
      if entry.item.groupID ~= "" then
        D:MoveGroupMember(entry.item.groupID, key, ((step % 2) == 0) and "up" or "down")
      else
        D:SetEntryGroup(key, "")
      end
    else
      ns:RebuildWatchIndex()
    end

    local seen = {}
    local ordered = {}
    for _, unit in ipairs(D:GetTrackedUnits()) do
      local list = ns.db.watchlist[unit] or {}
      for i = 1, #list do
        local item = list[i]
        T.truthy(item.instanceUID and item.instanceUID ~= "", "every item must have instanceUID")
        if seen[item.instanceUID] then
          error("duplicate instanceUID after stress step " .. tostring(step) .. ": " .. tostring(item.instanceUID))
        end
        seen[item.instanceUID] = true
        ordered[#ordered + 1] = item.instanceUID
      end
    end
    T.uniqueStrings(ordered)
    for i = 1, #keys do
      local entry = assert(D:ResolveEntry(keys[i]))
      T.equal(entry.item.instanceUID, stableUIDByKey[keys[i]], "stress loop must not mutate instanceUID")
    end
  end
end)

return suite
