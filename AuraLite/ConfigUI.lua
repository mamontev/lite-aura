local _, ns = ...
local U = ns.Utils

ns.ConfigUI = ns.ConfigUI or {}
local C = ns.ConfigUI

local validUnits = { player = true, target = true, focus = true, pet = true }

function C:Message(text)
  DEFAULT_CHAT_FRAME:AddMessage("|cff66d1ffAuraLite|r: " .. tostring(text))
end

local function msg(text)
  C:Message(text)
end

local function splitWords(text)
  local out = {}
  for token in string.gmatch(text or "", "%S+") do
    out[#out + 1] = token
  end
  return out
end

local function ensureGroup(groupID)
  if ns.SettingsData and ns.SettingsData.EnsureGroup and ns.db then
    return ns.SettingsData:EnsureGroup(groupID)
  end

  groupID = tostring(groupID or ""):lower()
  if groupID == "" then
    groupID = "important_procs"
  end

  if not ns.db.groups[groupID] then
    local maxOrder = 0
    for _, cfg in pairs(ns.db.groups) do
      maxOrder = math.max(maxOrder, tonumber(cfg.order) or 0)
    end
    ns.db.groups[groupID] = {
      id = groupID,
      name = groupID:gsub("_", " "):gsub("^%l", string.upper),
      order = maxOrder + 1,
      layout = { iconSize = 36, spacing = 4, direction = "RIGHT" },
    }
    ns.db.positions[groupID] = ns.db.positions[groupID] or {
      point = "CENTER",
      relativePoint = "CENTER",
      x = 0,
      y = -72 - ((maxOrder + 1) * 52),
    }
  end

  return groupID
end

function C:EnsureGroup(groupID)
  return ensureGroup(groupID)
end

local function showExportBox(title, text)
  if not C.exportFrame then
    local frame = CreateFrame("Frame", "AuraLiteExportFrame", UIParent, "BasicFrameTemplateWithInset")
    frame:SetSize(640, 240)
    frame:SetPoint("CENTER")
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()

    frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    frame.title:SetPoint("TOP", 0, -12)

    frame.edit = CreateFrame("EditBox", nil, frame)
    frame.edit:SetMultiLine(true)
    frame.edit:SetAutoFocus(false)
    frame.edit:SetSize(600, 150)
    frame.edit:SetPoint("TOP", 0, -44)
    frame.edit:SetFontObject(ChatFontNormal)
    frame.edit:SetTextColor(1.0, 0.95, 0.80, 1.0)
    frame.edit:SetShadowColor(0, 0, 0, 0.9)
    frame.edit:SetShadowOffset(1, -1)
    frame.edit:SetTextInsets(8, 8, 8, 8)
    frame.edit:EnableMouse(true)
    frame.edit:SetScript("OnEditFocusGained", function(self)
      self:HighlightText()
    end)
    frame.edit:SetScript("OnEscapePressed", function(self)
      self:ClearFocus()
      frame:Hide()
    end)

    frame.editBG = frame:CreateTexture(nil, "BACKGROUND")
    frame.editBG:SetPoint("TOPLEFT", frame.edit, "TOPLEFT", -2, 2)
    frame.editBG:SetPoint("BOTTOMRIGHT", frame.edit, "BOTTOMRIGHT", 2, -2)
    frame.editBG:SetColorTexture(0.04, 0.08, 0.14, 0.92)

    frame.scroll = CreateFrame("ScrollFrame", nil, frame, "UIPanelScrollFrameTemplate")
    frame.scroll:SetPoint("TOPLEFT", frame.edit, "TOPLEFT", -6, 4)
    frame.scroll:SetPoint("BOTTOMRIGHT", frame.edit, "BOTTOMRIGHT", 26, -4)
    frame.scroll:SetScrollChild(frame.edit)

    frame.close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    frame.close:SetSize(100, 22)
    frame.close:SetPoint("BOTTOM", 0, 12)
    frame.close:SetText("Close")
    frame.close:SetScript("OnClick", function()
      frame:Hide()
    end)

    C.exportFrame = frame
  end

  C.exportFrame.title:SetText(title or "AuraLite")
  C.exportFrame.edit:SetText(text or "")
  C.exportFrame.edit:HighlightText()
  C.exportFrame:Show()
  C.exportFrame.edit:SetFocus()
end

local function roleFromText(text)
  text = tostring(text or ""):lower()
  if text == "tank" then
    return "TANK"
  end
  if text == "healer" then
    return "HEALER"
  end
  return "DAMAGER"
end

function C:ShowFirstRun()
  if self.firstRunFrame then
    self.firstRunFrame:Show()
    return
  end

  local frame = CreateFrame("Frame", "AuraLiteFirstRunFrame", UIParent, "BasicFrameTemplateWithInset")
  frame:SetSize(420, 250)
  frame:SetPoint("CENTER")
  frame:SetFrameStrata("DIALOG")
  frame:EnableMouse(true)
  frame:SetMovable(true)
  frame:RegisterForDrag("LeftButton")
  frame:SetScript("OnDragStart", frame.StartMoving)
  frame:SetScript("OnDragStop", frame.StopMovingOrSizing)

  frame.title = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  frame.title:SetPoint("TOP", 0, -10)
  frame.title:SetText("AuraLite First Setup")

  frame.body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  frame.body:SetPoint("TOP", 0, -44)
  frame.body:SetWidth(360)
  frame.body:SetJustifyH("LEFT")
  frame.body:SetText("Choose a starting preset. You can edit everything later with /al commands.")

  local function makeRoleButton(label, role, xOffset)
    local btn = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
    btn:SetSize(110, 28)
    btn:SetPoint("BOTTOM", xOffset, 64)
    btn:SetText(label)
    btn:SetScript("OnClick", function()
      ns.ProfileManager:ApplyRolePreset(role, true)
      ns:RebuildWatchIndex()
      ns.EventRouter:RefreshAll()
      ns.ProfileManager:MarkFirstRunDone()
      frame:Hide()
      msg("Applied " .. label .. " preset.")
    end)
    return btn
  end

  makeRoleButton("Tank", "TANK", -120)
  makeRoleButton("Healer", "HEALER", 0)
  makeRoleButton("DPS", "DAMAGER", 120)

  local close = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
  close:SetSize(140, 24)
  close:SetPoint("BOTTOM", 0, 22)
  close:SetText("Skip for now")
  close:SetScript("OnClick", function()
    ns.ProfileManager:MarkFirstRunDone()
    frame:Hide()
  end)

  self.firstRunFrame = frame
  frame:Show()
end

local function printHelp()
  msg("Commands:")
  msg("/al config | options | lock | unlock | edit | compact | sound | source | debug | status")
  msg("/al debug on|off|verbose|status|show [N]|clear|file on/off|chat on/off")
  msg("/al add <spellID> [unit] [group]")
  msg("/al addname <unit> <group> <spell name>")
  msg("/al remove <spellID> [unit]")
  msg("/al rule list|addif|addconsume|remove|clear ...")
  msg("/al taintaudit")
  msg("/al group add <groupID> [Display Name]")
  msg("/al group rename <groupID> <Display Name>")
  msg("/al group order <groupID> <number>")
  msg("/al preset <tank|healer|dps> [replace]")
  msg("/al profile list|new|use|spec|mode|delete <name>")
  msg("/al export | /al import <AL1:...>")
end

local function addWatchBySpell(spellInput, unit, groupID)
  local spellID = U.ResolveSpellID(spellInput)
  if not spellID and ns.SpellCatalog and ns.SpellCatalog.ResolveNameToSpellID then
    spellID = ns.SpellCatalog:ResolveNameToSpellID(spellInput)
  end
  if not spellID then
    msg("Spell not found: " .. tostring(spellInput))
    return
  end

  unit = tostring(unit or "player"):lower()
  if not validUnits[unit] then
    unit = "player"
  end

  groupID = ensureGroup(groupID)

  local ok, err = ns.Registry:AddWatch(unit, {
    spellID = spellID,
    groupID = groupID,
    onlyMine = unit ~= "player",
    alert = true,
    soundOnGain = "default",
    soundOnLow = "default",
    soundOnExpire = "default",
    iconMode = "spell",
    customTexture = "",
  })
  if not ok then
    msg(err or "Failed to add aura.")
    return
  end

  ns.EventRouter:RefreshAll()
  local name = ns.AuraAPI:GetSpellName(spellID) or ("spellID " .. spellID)
  msg(("Tracking %s on %s (%s)."):format(name, unit, groupID))
end

local function handleGroup(tokens, raw)
  local action = (tokens[3] or ""):lower()
  local groupID = tostring(tokens[4] or ""):lower()
  if action == "add" then
    if groupID == "" then
      msg("Usage: /al group add <groupID> [Display Name]")
      return
    end
    ensureGroup(groupID)
    local display = raw:match("^%s*group%s+add%s+%S+%s+(.+)$")
    if display and display ~= "" then
      ns.db.groups[groupID].name = display
    end
    ns.EventRouter:RefreshAll()
    msg("Group added: " .. groupID)
    return
  end

  if action == "rename" then
    if groupID == "" then
      msg("Usage: /al group rename <groupID> <Display Name>")
      return
    end
    local display = raw:match("^%s*group%s+rename%s+%S+%s+(.+)$")
    if not display or display == "" then
      msg("Display name missing.")
      return
    end
    ensureGroup(groupID)
    ns.db.groups[groupID].name = display
    ns.EventRouter:RefreshAll()
    msg("Group renamed.")
    return
  end

  if action == "order" then
    if groupID == "" then
      msg("Usage: /al group order <groupID> <number>")
      return
    end
    local order = tonumber(tokens[5])
    if not order then
      msg("Order must be a number.")
      return
    end
    ensureGroup(groupID)
    ns.db.groups[groupID].order = order
    ns.EventRouter:RefreshAll()
    msg("Group order updated.")
    return
  end

  msg("Usage: /al group add|rename|order ...")
end

local function handleRule(tokens)
  local action = tostring(tokens[2] or ""):lower()
  if not ns.ProcRules then
    msg("ProcRuleEngine not loaded.")
    return
  end

  if action == "list" then
    local rules = ns.ProcRules:GetUserRules()
    if #rules == 0 then
      msg("No custom rules.")
      return
    end
    msg("Custom rules:")
    for i = 1, #rules do
      msg(" - " .. ns.ProcRules:DescribeUserRule(rules[i]))
    end
    return
  end

  if action == "addif" then
    local ruleID = tokens[3]
    local castSpellID = tokens[4]
    local talentSpellID = nil
    local auraSpellID = nil
    local duration = nil

    if tokens[7] ~= nil then
      -- Legacy/full form: <cast> <talent> <aura> <duration>
      talentSpellID = tokens[5]
      auraSpellID = tokens[6]
      duration = tokens[7]
    else
      -- Optional talent form: <cast> <aura> <duration>
      auraSpellID = tokens[5]
      duration = tokens[6]
    end
    local ok, err = ns.ProcRules:AddSimpleIfRule(ruleID, castSpellID, talentSpellID, auraSpellID, duration)
    if not ok then
      msg(err or "Failed to add rule.")
      return
    end
    ns.EventRouter:RefreshAll()
    if talentSpellID then
      msg(("Rule %s added. if cast %s && talented %s then show %s"):format(tostring(ruleID), tostring(castSpellID), tostring(talentSpellID), tostring(auraSpellID)))
    else
      msg(("Rule %s added. if cast %s then show %s"):format(tostring(ruleID), tostring(castSpellID), tostring(auraSpellID)))
    end
    return
  end

  if action == "addconsume" then
    local ruleID = tokens[3]
    local castSpellID = tokens[4]
    local auraSpellID = tokens[5]
    local ok, err = ns.ProcRules:AddSimpleConsumeRule(ruleID, castSpellID, auraSpellID)
    if not ok then
      msg(err or "Failed to add consume rule.")
      return
    end
    ns.EventRouter:RefreshAll()
    msg(("Rule %s added. if cast %s then hide %s"):format(tostring(ruleID), tostring(castSpellID), tostring(auraSpellID)))
    return
  end

  if action == "remove" then
    local ruleID = tokens[3]
    local removed = ns.ProcRules:RemoveUserRule(ruleID)
    ns.EventRouter:RefreshAll()
    msg(("Removed %d rule(s) for id %s."):format(removed, tostring(ruleID)))
    return
  end

  if action == "clear" then
    ns.ProcRules:ClearUserRules()
    ns.EventRouter:RefreshAll()
    msg("All custom rules cleared.")
    return
  end

  msg("Usage:")
  msg("/al rule list")
  msg("/al rule addif <id> <castSpellID> [talentSpellID] <auraSpellID> <durationSec>")
  msg("/al rule addconsume <id> <castSpellID> <auraSpellID>")
  msg("/al rule remove <id>")
  msg("/al rule clear")
end

local function handleProfile(tokens)
  local action = (tokens[3] or ""):lower()
  local arg = tokens[4]

  if action == "list" then
    local keys = ns.ProfileManager:ListProfiles()
    msg("Profiles: " .. table.concat(keys, ", "))
    msg(("Mode: %s | Active: %s"):format(ns.ProfileManager.root.global.profileMode, ns.ProfileManager.activeProfileKey))
    return
  end

  if action == "new" then
    local key, err = ns.ProfileManager:CreateProfile(arg, ns.ProfileManager.activeProfileKey)
    if not key then
      msg(err)
      return
    end
    msg("Profile created: " .. key)
    return
  end

  if action == "use" then
    local ok, err = ns.ProfileManager:SetManualProfile(arg)
    if not ok then
      msg(err)
      return
    end
    ns:RebuildWatchIndex()
    if ns.ProcRules and ns.ProcRules.RefreshContext then
      ns.ProcRules:RefreshContext()
    end
    ns.EventRouter:RefreshAll()
    msg("Using manual profile: " .. ns.ProfileManager.activeProfileKey)
    return
  end

  if action == "spec" then
    local ok, err = ns.ProfileManager:SetCurrentSpecProfile(arg)
    if not ok then
      msg(err)
      return
    end
    ns:RebuildWatchIndex()
    if ns.ProcRules and ns.ProcRules.RefreshContext then
      ns.ProcRules:RefreshContext()
    end
    ns.EventRouter:RefreshAll()
    msg("Assigned profile to current spec: " .. ns.ProfileManager.activeProfileKey)
    return
  end

  if action == "mode" then
    local mode = tostring(arg or ""):lower()
    local ok, err = ns.ProfileManager:SetMode(mode)
    if not ok then
      msg(err)
      return
    end
    ns:RebuildWatchIndex()
    if ns.ProcRules and ns.ProcRules.RefreshContext then
      ns.ProcRules:RefreshContext()
    end
    ns.EventRouter:RefreshAll()
    msg("Profile mode: " .. mode)
    return
  end

  if action == "delete" then
    local ok, err = ns.ProfileManager:DeleteProfile(arg)
    if not ok then
      msg(err)
      return
    end
    ns:RebuildWatchIndex()
    if ns.ProcRules and ns.ProcRules.RefreshContext then
      ns.ProcRules:RefreshContext()
    end
    ns.EventRouter:RefreshAll()
    msg("Profile deleted.")
    return
  end

  msg("Usage: /al profile list|new|use|spec|mode|delete")
end

local function handlePreset(tokens)
  local role = roleFromText(tokens[3])
  local replace = tostring(tokens[4] or ""):lower() == "replace"
  ns.ProfileManager:ApplyRolePreset(role, replace)
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  ns.EventRouter:RefreshAll()
  msg(("Applied %s preset%s."):format(role, replace and " (replace)" or ""))
end

local function handleExport()
  local text = ns.ProfileManager:ExportActiveProfile()
  showExportBox("AuraLite Export", text)
  msg("Export string generated.")
end

local function handleImport(raw)
  local payload = raw:match("^%s*import%s+(.+)$")
  if not payload or payload == "" then
    msg("Usage: /al import <AL1:...>")
    return
  end
  local key, err = ns.ProfileManager:ImportProfile(payload, nil, true)
  if not key then
    msg("Import failed: " .. tostring(err))
    return
  end
  ns:RebuildWatchIndex()
  if ns.ProcRules and ns.ProcRules.RefreshContext then
    ns.ProcRules:RefreshContext()
  end
  ns.EventRouter:RefreshAll()
  msg("Import successful into profile: " .. key)
end

function C:HandleSlash(rawInput)
  rawInput = U.Trim(rawInput or "")
  if rawInput == "" then
    printHelp()
    return
  end

  local tokens = splitWords(rawInput)
  local cmd = (tokens[1] or ""):lower()

  if cmd == "config" or cmd == "ui" or cmd == "options" then
    if cmd == "options" and ns.OptionsIntegration and ns.OptionsIntegration.OpenBlizzardCategory then
      ns.OptionsIntegration:OpenBlizzardCategory()
      return
    end

    if ns.SettingsUI and ns.SettingsUI.Open then
      ns.SettingsUI:Open()
    else
      msg("Settings UI not loaded.")
    end
    return
  end

  if cmd == "lock" then
    ns.Dragger:SetLocked(true)
    ns.EventRouter:RefreshAll()
    msg("Locked.")
    return
  end

  if cmd == "unlock" then
    ns.Dragger:SetLocked(false)
    ns.EventRouter:RefreshAll()
    msg("Unlocked. Drag groups with left mouse.")
    return
  end

  if cmd == "edit" then
    ns.TestMode:SetEnabled(not ns.TestMode:IsEnabled())
    ns.EventRouter:RefreshAll()
    msg(ns.TestMode:IsEnabled() and "Edit mode ON." or "Edit mode OFF.")
    return
  end

  if cmd == "compact" then
    ns.db.options.compactMode = not ns.db.options.compactMode
    ns.EventRouter:RefreshAll()
    msg("Compact mode: " .. (ns.db.options.compactMode and "ON" or "OFF"))
    return
  end

  if cmd == "sound" then
    ns.db.options.soundEnabled = not ns.db.options.soundEnabled
    msg("Sound alerts: " .. (ns.db.options.soundEnabled and "ON" or "OFF"))
    return
  end

  if cmd == "source" then
    ns.db.options.showSource = not ns.db.options.showSource
    ns.EventRouter:RefreshAll()
    msg("Source labels: " .. (ns.db.options.showSource and "ON" or "OFF"))
    return
  end

  if cmd == "status" then
    msg(("Profile: %s | Mode: %s | Locked: %s | Edit: %s | Restricted: %s"):format(
      ns.ProfileManager.activeProfileKey or "unknown",
      ns.ProfileManager.root.global.profileMode,
      tostring(ns.db.locked),
      tostring(ns.state.editMode),
      tostring(ns.state.restrictionActive)
    ))
    msg(("Sounds: %s | Channel: %s"):format(
      tostring(ns.db.options.soundEnabled),
      tostring(ns.db.options.soundChannel or "Master")
    ))
    msg(("Debug: %s | Verbose: %s"):format(
      tostring(ns.db.options.debugEnabled),
      tostring(ns.db.options.debugVerbose)
    ))
    return
  end

  if cmd == "taintaudit" then
    if ns.Debug and ns.Debug.PrintTaintAuditChecklist then
      ns.Debug:PrintTaintAuditChecklist()
    else
      msg("Debug manager not available.")
    end
    return
  end

  if cmd == "debug" then
    local arg = tostring(tokens[2] or ""):lower()
    if arg == "on" then
      ns.Debug:SetEnabled(true)
      msg("Debug: ON")
      return
    end
    if arg == "off" then
      ns.Debug:SetEnabled(false)
      msg("Debug: OFF")
      return
    end
    if arg == "verbose" then
      ns.Debug:SetEnabled(true)
      ns.Debug:SetVerbose(not ns.db.options.debugVerbose)
      msg("Debug verbose: " .. (ns.db.options.debugVerbose and "ON" or "OFF"))
      return
    end
    if arg == "status" then
      msg(("Debug: %s | Verbose: %s | Chat: %s | File(SV): %s | Entries: %d"):format(
        tostring(ns.db.options.debugEnabled),
        tostring(ns.db.options.debugVerbose),
        tostring(ns.db.options.debugToChat ~= false),
        tostring(ns.db.options.debugToSaved == true),
        tonumber(ns.Debug:GetSavedLogCount()) or 0
      ))
      return
    end
    if arg == "show" then
      local limit = tonumber(tokens[3]) or 300
      if limit < 1 then
        limit = 1
      end
      if limit > 2000 then
        limit = 2000
      end
      local text = ns.Debug:GetSavedLogText(limit)
      if text == "" then
        text = "(no debug log entries)"
      end
      showExportBox("AuraLite Debug Log", text)
      msg(("Debug log opened (%d lines)."):format(limit))
      return
    end
    if arg == "clear" then
      local removed = ns.Debug:ClearSavedLog()
      msg(("Debug log cleared: %d entries removed."):format(tonumber(removed) or 0))
      return
    end
    if arg == "file" then
      local v = tostring(tokens[3] or ""):lower()
      if v == "on" then
        ns.Debug:SetSavedOutput(true)
        msg("Debug file(SavedVariables): ON")
      elseif v == "off" then
        ns.Debug:SetSavedOutput(false)
        msg("Debug file(SavedVariables): OFF")
      else
        msg("Usage: /al debug file on|off")
      end
      return
    end
    if arg == "chat" then
      local v = tostring(tokens[3] or ""):lower()
      if v == "on" then
        ns.Debug:SetChatOutput(true)
        msg("Debug chat output: ON")
      elseif v == "off" then
        ns.Debug:SetChatOutput(false)
        msg("Debug chat output: OFF")
      else
        msg("Usage: /al debug chat on|off")
      end
      return
    end

    local enabled = ns.Debug:Toggle()
    msg("Debug: " .. (enabled and "ON" or "OFF"))
    return
  end

  if cmd == "add" then
    addWatchBySpell(tokens[2], tokens[3], tokens[4])
    return
  end

  if cmd == "addname" then
    local unit = tokens[2] or "player"
    local groupID = tokens[3] or "important_procs"
    local spellName = rawInput:match("^%s*addname%s+%S+%s+%S+%s+(.+)$")
    if not spellName then
      msg("Usage: /al addname <unit> <group> <spell name>")
      return
    end
    addWatchBySpell(spellName, unit, groupID)
    return
  end

  if cmd == "remove" then
    local spellID = tonumber(tokens[2])
    local unit = tokens[3] or "player"
    if not spellID then
      msg("Usage: /al remove <spellID> [unit]")
      return
    end
    if not validUnits[unit] then
      unit = "player"
    end
    local removed = ns.Registry:RemoveWatch(unit, spellID)
    ns.EventRouter:RefreshAll()
    msg(("Removed %d entries for spell %d on %s."):format(removed, spellID, unit))
    return
  end

  if cmd == "rule" then
    handleRule(tokens)
    return
  end

  if cmd == "group" then
    handleGroup(tokens, rawInput)
    return
  end

  if cmd == "preset" then
    handlePreset(tokens)
    return
  end

  if cmd == "profile" then
    handleProfile(tokens)
    return
  end

  if cmd == "export" then
    handleExport()
    return
  end

  if cmd == "import" then
    handleImport(rawInput)
    return
  end

  if cmd == "firstrun" then
    self:ShowFirstRun()
    return
  end

  printHelp()
end
