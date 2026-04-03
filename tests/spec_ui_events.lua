local H = dofile("tests/lib/test_harness.lua")

local T = H.Assert
local suite = H.new("UIEvents")

local function loadUIEvents(ns)
  local chunk, err = loadfile("AuraLite/UI/UIEvents.lua")
  if not chunk then
    error(err, 0)
  end
  chunk(nil, ns)
  return ns.UIV2.Events
end

suite:case("Nested emits are queued instead of recursing", function()
  local ns = {
    UIV2 = {},
  }
  local E = loadUIEvents(ns)
  local order = {}

  E:On(E.Names.AURA_SELECTED, function(payload)
    order[#order + 1] = "select:" .. tostring(payload and payload.auraId or "nil")
    if payload and payload.auraId == "root" then
      E:Emit(E.Names.AURA_SELECTED, { auraId = "child" })
    end
  end)

  E:Emit(E.Names.AURA_SELECTED, { auraId = "root" })

  T.equal(#order, 2)
  T.equal(order[1], "select:root")
  T.equal(order[2], "select:child")
  T.falsy(E._isDispatching)
end)

suite:case("normalizeTrackingMode tolerates non-scalar values", function()
  local ns = {
    UIV2 = {},
  }
  local chunk, err = loadfile("AuraLite/UI/UIBindings.lua")
  if not chunk then
    error(err, 0)
  end
  chunk(nil, ns)

  local draft = ns.UIV2.Bindings:DraftFromEditableModel({
    key = "aura_test",
    spellID = 23922,
    unit = { bad = true },
    trackingMode = {},
    castSpellIDs = {},
  })

  T.truthy(draft ~= nil)
  T.equal(draft.unit, "player")
  T.equal(draft.trackingMode, "confirmed")
end)

return suite
