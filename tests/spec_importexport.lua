local H = dofile("tests/lib/test_harness.lua")
local makeEnv = dofile("tests/lib/addon_env.lua")

local T = H.Assert
local suite = H.new("ImportExport")

suite:case("Aura export/import keeps settings and rules but assigns fresh identity", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local P = ns.ProcRules
  local X = ns.ImportExport

  local key = assert(D:AddEntry(env.makeModel({
    spellInput = 386030,
    displayName = "Brace for Impact",
    unit = "player",
    groupID = "",
    timerVisual = "iconbar",
    iconWidth = 44,
    barWidth = 172,
    barHeight = 20,
    barColor = "0.20,0.40,0.60",
    savedPosition = {
      point = "LEFT",
      relativePoint = "LEFT",
      x = 250,
      y = 120,
    },
  })))

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

  local original = assert(D:ResolveEntry(key))
  local exportString = assert(X:ExportAuraString(key))
  local result = assert(X:ImportString(exportString, { forceStandalone = true }))
  local imported = assert(D:ResolveEntry(result.auraKey))

  T.equal(imported.item.spellID, original.item.spellID)
  T.equal(imported.item.displayName, original.item.displayName)
  T.equal(imported.item.iconWidth, original.item.iconWidth)
  T.equal(imported.item.barWidth, original.item.barWidth)
  T.equal(imported.item.barHeight, original.item.barHeight)
  T.equal(imported.item.barColor, original.item.barColor)
  T.equal(imported.item.groupID, "")
  T.equal(imported.item.instanceUID ~= original.item.instanceUID, true, "import must create fresh local identity")

  local importedRules = P:GetUserRulesForAura(386030)
  T.truthy(#importedRules >= 4, "import should add rule copies instead of dropping them")
  local ids = {}
  for i = 1, #importedRules do
    ids[#ids + 1] = tostring(importedRules[i].id or "")
  end
  T.uniqueStrings(ids)
end)

suite:case("Group export/import recreates layout and members under a safe local group id", function()
  local env, ns = makeEnv()
  local D = ns.SettingsData
  local X = ns.ImportExport

  local alpha = assert(D:AddEntry(env.makeModel({ spellInput = 1001, displayName = "Alpha" })))
  local beta = assert(D:AddEntry(env.makeModel({ spellInput = 1002, displayName = "Beta" })))

  D:SetEntryGroup(alpha, "important_procs")
  D:SetEntryGroup(beta, "important_procs")
  D:UpdateGroupConfig("important_procs", {
    groupName = "Important Procs",
    groupDirection = "UP",
    groupSpacing = 7,
    groupSort = "manual",
    groupWrapAfter = 2,
    groupOffsetX = 14,
    groupOffsetY = -9,
  })
  if ns.db and ns.db.positions then
    ns.db.positions["important_procs"] = {
      point = "TOPLEFT",
      relativePoint = "TOPLEFT",
      x = 333,
      y = -222,
    }
  end

  local exportString = assert(X:ExportGroupString("important_procs"))
  local result = assert(X:ImportString(exportString))
  T.truthy(result.groupID ~= "")
  T.truthy(result.groupID ~= "important_procs", "import should avoid colliding with existing group id")

  local cfg = D:GetGroupConfig(result.groupID)
  T.equal(cfg.name, "Important Procs")
  T.equal(cfg.layout.direction, "UP")
  T.equal(cfg.layout.spacing, 7)
  T.equal(cfg.layout.sort, "manual")
  T.equal(cfg.layout.wrapAfter, 2)
  T.equal(cfg.layout.nudgeX, 14)
  T.equal(cfg.layout.nudgeY, -9)
  T.same(ns.db.positions[result.groupID], {
    point = "TOPLEFT",
    relativePoint = "TOPLEFT",
    x = 333,
    y = -222,
  })

  local members = D:ListGroupMembers(result.groupID)
  T.equal(#members, 2)
  local names = { members[1].name, members[2].name }
  table.sort(names)
  T.same(names, { "Alpha", "Beta" })
end)

return suite
