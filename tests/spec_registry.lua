return function(T, Env, root)
  T:add("registry rebuild preserves instanceUID and savedPosition", function()
    local env = Env.new(root)
    env.ns.db.watchlist.player[1] = {
      spellID = 2565,
      instanceUID = "a2565_s1",
      groupID = "",
      trackingMode = "confirmed",
      castSpellIDs = { 2565 },
      estimatedDuration = 6,
      displayName = "Shield Block",
      timerVisual = "iconbar",
      iconWidth = 44,
      barWidth = 150,
      showTimerText = false,
      barSide = "left",
      savedPosition = {
        point = "LEFT",
        relativePoint = "LEFT",
        x = 321,
        y = 111,
      },
    }

    env.ns.Registry:Rebuild(env.ns.db)
    local item = env.ns.db.watchlist.player[1]

    T:assertEqual(item.instanceUID, "a2565_s1", "registry rebuild should preserve stable identity")
    T:assertEqual(item.iconWidth, 44, "registry rebuild should preserve display fields")
    T:assertEqual(item.barWidth, 150, "registry rebuild should preserve bar width")
    T:assertFalse(item.showTimerText, "registry rebuild should preserve boolean fields")
    T:assertEqual(item.barSide, "left", "registry rebuild should preserve bar side")
    T:assertTableValue(item.savedPosition, "x", 321, "saved position x should survive rebuild")
    T:assertTableValue(item.savedPosition, "y", 111, "saved position y should survive rebuild")
  end)
end
