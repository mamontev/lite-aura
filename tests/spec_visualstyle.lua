local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("VisualStyle")

suite:case("NormalizeStates falls back to safe defaults", function()
  local _, ns = makeEnv()
  local VS = ns.VisualStyle

  local normalized = VS:NormalizeStates({
    onGain = "???",
    lowTime = "warning",
    maxStacks = "nope",
  })

  T.equal(normalized.onGain, "off")
  T.equal(normalized.lowTime, "warning")
  T.equal(normalized.maxStacks, "gold")
end)

suite:case("Resolve prefers low-time urgency while preserving heroic full-charge emphasis", function()
  local _, ns = makeEnv()
  local VS = ns.VisualStyle

  local style = VS:Resolve({
    barColor = "",
    visualStates = {
      onGain = "burst",
      lowTime = "intense",
      maxStacks = "heroic",
    },
  }, {
    justGained = true,
    thresholdReached = true,
    isMaxStacks = true,
    pulse = 0.5,
  })

  T.truthy((tonumber(style.scale) or 1) >= 1.05)
  T.equal(style.barColor, "1.00,0.18,0.14")
  T.truthy((tonumber(style.glowAlpha) or 0) > 0.2)
  T.equal(style.borderR, 1.0)
end)

return suite
