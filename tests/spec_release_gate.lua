local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("ReleaseGate")

suite:case("Cross-unit update preserves identity and carries savedPosition", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local key = assert(D:AddEntry(env.makeModel({
    spellInput = 772,
    unit = "player",
    trackingMode = "confirmed",
    displayName = "Rend",
    savedPosition = {
      point = "RIGHT",
      relativePoint = "RIGHT",
      x = -240,
      y = 95,
    },
  })))

  local original = assert(D:ResolveEntry(key))
  local stableUID = original.item.instanceUID
  local stablePos = env.clonePosition(original.item.savedPosition)

  local model = D:BuildEditableModel(original)
  model.unit = "target"
  model.trackingMode = "estimated"
  model.castSpellIDs = { 435222 }
  local movedKey = assert(D:UpdateEntry(key, model))

  local moved = assert(D:ResolveEntry(movedKey))
  T.equal(moved.unit, "target")
  T.equal(moved.item.instanceUID, stableUID)
  T.same(moved.item.savedPosition, stablePos)
end)

suite:case("Randomized stateful operations preserve identity uniqueness and group invariants", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData

  math.randomseed(424242)

  local spellPool = { 1001, 1002, 1003, 1004, 23922, 2565, 386030, 772 }
  local units = { "player", "target", "focus" }
  local activeKeys = {}
  local nextLabel = 1

  local function addOne()
    local spellID = spellPool[math.random(#spellPool)]
    local unit = units[math.random(#units)]
    local label = "Rnd" .. tostring(nextLabel)
    nextLabel = nextLabel + 1
    local key = assert(D:AddEntry(env.makeModel({
      spellInput = spellID,
      unit = unit,
      displayName = label,
      trackingMode = (unit == "target") and "estimated" or "confirmed",
      castSpellIDs = (unit == "target") and { 435222 } or {},
      savedPosition = {
        point = "CENTER",
        relativePoint = "CENTER",
        x = math.random(-300, 300),
        y = math.random(-200, 200),
      },
    })))
    activeKeys[#activeKeys + 1] = key
  end

  for _ = 1, 5 do
    addOne()
  end

  local stableUID = {}

  local function snapshotInvariants()
    local seenUID = {}
    local seenKeys = {}
    for _, unit in ipairs(D:GetTrackedUnits()) do
      local list = ns.db.watchlist[unit] or {}
      for index = 1, #list do
        local key = unit .. ":" .. index
        local item = list[index]
        T.truthy(item.instanceUID and item.instanceUID ~= "", "instanceUID required")
        if seenUID[item.instanceUID] then
          error("duplicate instanceUID: " .. tostring(item.instanceUID))
        end
        seenUID[item.instanceUID] = true
        seenKeys[key] = true
        if stableUID[key] == nil then
          stableUID[key] = item.instanceUID
        end
      end
    end

    for i = #activeKeys, 1, -1 do
      if not seenKeys[activeKeys[i]] then
        table.remove(activeKeys, i)
      end
    end

    for i = 1, #activeKeys do
      local entry = D:ResolveEntry(activeKeys[i])
      if entry then
        local uid = stableUID[activeKeys[i]]
        if uid then
          T.equal(entry.item.instanceUID, uid, "existing key must keep same identity")
        else
          stableUID[activeKeys[i]] = entry.item.instanceUID
        end
      end
    end
  end

  snapshotInvariants()

  for step = 1, 120 do
    local op = math.random(6)
    if op == 1 and #activeKeys < 10 then
      addOne()
    elseif op == 2 and #activeKeys > 0 then
      local key = activeKeys[math.random(#activeKeys)]
      local entry = D:ResolveEntry(key)
      if entry then
        local model = D:BuildEditableModel(entry)
        model.displayName = model.displayName .. "_u" .. tostring(step)
        model.barWidth = 90 + math.random(0, 40)
        local nextKey = assert(D:UpdateEntry(key, model))
        stableUID[nextKey] = stableUID[key] or entry.item.instanceUID
        if nextKey ~= key then
          stableUID[key] = nil
          for i = 1, #activeKeys do
            if activeKeys[i] == key then
              activeKeys[i] = nextKey
              break
            end
          end
        end
      end
    elseif op == 3 and #activeKeys > 0 then
      local key = activeKeys[math.random(#activeKeys)]
      local groupID = (math.random(2) == 1) and "g_alpha" or "g_beta"
      D:SetEntryGroup(key, groupID)
    elseif op == 4 and #activeKeys > 0 then
      local key = activeKeys[math.random(#activeKeys)]
      D:SetEntryGroup(key, "")
    elseif op == 5 then
      ns:RebuildWatchIndex()
    elseif op == 6 and #activeKeys > 1 then
      local key = activeKeys[math.random(#activeKeys)]
      local entry = D:ResolveEntry(key)
      if entry and entry.item.groupID ~= "" then
        D:MoveGroupMember(entry.item.groupID, key, (math.random(2) == 1) and "up" or "down")
      end
    end
    snapshotInvariants()
  end
end)

return suite
