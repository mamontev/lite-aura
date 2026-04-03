local H = dofile("tests/lib/test_harness.lua")

local T = H.Assert
local suite = H.new("AuraAPI")

local function loadAuraAPI()
  local ns = {}
  local chunk, err = loadfile("AuraLite/AuraAPIAdapter.lua")
  if not chunk then
    error(err, 0)
  end
  chunk(nil, ns)
  return ns.AuraAPI
end

suite:case("GetSpellCooldownData preserves duration objects when available", function()
  local auraAPI = loadAuraAPI()
  local durationObject = { kind = "cooldown_object" }

  _G.C_Spell = {
    GetSpellCooldown = function()
      return {
        startTime = 10,
        duration = 30,
        isEnabled = true,
        isActive = true,
        currentCharges = 1,
        maxCharges = 1,
      }
    end,
    GetSpellCooldownDuration = function()
      return durationObject
    end,
  }
  _G.GetSpellCooldown = function(spellID)
    if tonumber(spellID) == 61304 then
      return 0, 0, 1
    end
    return 10, 30, 1
  end
  _G.GetSpellCharges = function()
    return 1, 1, 0, 0
  end
  _G.GetTime = function()
    return 12
  end

  local data = auraAPI:GetSpellCooldownData(23922)
  T.truthy(data ~= nil)
  T.equal(data.durationObject, durationObject)
  T.equal(data.isActive, true)
  T.equal(data.isEnabled, true)
end)

suite:case("ApplyCooldownToFrame prefers duration-object API", function()
  local auraAPI = loadAuraAPI()
  local calls = {}
  local durationObject = { kind = "cooldown_object" }
  local frame = {
    SetCooldownFromDurationObject = function(_, object)
      calls[#calls + 1] = { method = "durationObject", object = object }
    end,
    SetCooldown = function(_, startTime, duration)
      calls[#calls + 1] = { method = "setCooldown", startTime = startTime, duration = duration }
    end,
  }

  local ok = auraAPI:ApplyCooldownToFrame(frame, {
    startTime = 10,
    duration = 30,
    isActive = true,
    durationObject = durationObject,
  })

  T.truthy(ok)
  T.equal(#calls, 1)
  T.equal(calls[1].method, "durationObject")
  T.equal(calls[1].object, durationObject)
end)

suite:case("Loss of control cooldown replaces normal cooldown when requested", function()
  local auraAPI = loadAuraAPI()

  _G.C_Spell = {
    GetSpellCooldown = function()
      return {
        startTime = 10,
        duration = 20,
        isEnabled = true,
        isActive = true,
      }
    end,
    GetSpellCooldownDuration = function()
      return { kind = "normal" }
    end,
    GetSpellLossOfControlCooldownInfo = function()
      return {
        startTime = 15,
        duration = 40,
        isActive = true,
        shouldReplaceNormalCooldown = true,
      }
    end,
  }
  _G.GetSpellCooldown = function(spellID)
    if tonumber(spellID) == 61304 then
      return 0, 0, 1
    end
    return 10, 20, 1
  end
  _G.GetSpellCharges = function()
    return 1, 1, 0, 0
  end

  local data = auraAPI:GetSpellCooldownData(23922)
  T.truthy(data ~= nil)
  T.equal(data.durationKind, "loss_of_control")
  T.equal(data.shouldReplaceNormalCooldown, true)
  T.equal(data.startTime, 15)
  T.equal(data.duration, 40)
end)

return suite
