local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Schemas = ns.UIV2.Schemas or {}

local Schemas = ns.UIV2.Schemas

local function loadClassOptions()
  if ns.SettingsData and ns.SettingsData.GetLoadClassOptions then
    return ns.SettingsData:GetLoadClassOptions()
  end
  return {
    { value = "", label = "Any Class" },
    { value = "WARRIOR", label = "Warrior" },
  }
end

local function loadSpecOptions(model)
  if ns.SettingsData and ns.SettingsData.GetLoadSpecMenuOptions then
    local classToken = model and model.loadClassToken or ""
    local raw = ns.SettingsData:GetLoadSpecMenuOptions(classToken)
    local flat = { { value = "", label = "Any Spec" } }
    for i = 1, #(raw or {}) do
      local row = raw[i]
      if row.value ~= nil then
        flat[#flat + 1] = { value = row.value, label = row.label }
      elseif type(row.menuList) == "table" then
        for j = 1, #row.menuList do
          local child = row.menuList[j]
          flat[#flat + 1] = { value = child.value, label = row.label .. " - " .. child.label }
        end
      end
    end
    return flat
  end
  return { { value = "", label = "Any Spec" } }
end

local function soundOptions()
  if ns.SoundManager and ns.SoundManager.GetDropdownOptions then
    return ns.SoundManager:GetDropdownOptions(true)
  end
  return {
    { value = "default", label = "Default" },
    { value = "none", label = "None" },
  }
end

Schemas.EditorTabs = {
  { key = "Trigger", label = "Trigger", fields = {
    { key = "unit", label = "Where To Track", widget = "dropdown", options = {
      { value = "player", label = "Player" },
      { value = "target", label = "Target" },
    } },
    { key = "castSpellIDs", label = "SpellIDs I Cast (CSV)", widget = "spellcsv", required = true },
    { key = "spellID", label = "Aura SpellID To Show", widget = "spellid", required = true },
    { key = "estimatedDuration", label = "Expected Duration (sec)", widget = "number", min = 1, max = 600 },
  } },
  { key = "Conditions", label = "Conditions", fields = {
    { key = "conditionLogic", label = "Condition Logic", widget = "dropdown", options = {
      { value = "all", label = "AND (all)" },
      { value = "any", label = "OR (any)" },
    } },
    { key = "talentSpellIDs", label = "Talent SpellIDs (CSV)", widget = "spellcsv" },
    { key = "requiredAuraSpellIDs", label = "Required Aura SpellIDs (CSV)", widget = "spellcsv" },
    { key = "inCombatOnly", label = "In Combat Only", widget = "checkbox" },
  } },
  { key = "Actions", label = "Actions", fields = {
    { key = "duration", label = "Timer Duration (sec)", widget = "number", min = 1, max = 120 },
  } },
  { key = "Display", label = "Display", fields = {
    { key = "name", label = "Aura Name", widget = "text" },
    { key = "group", label = "Group ID", widget = "text" },
    { key = "displayMode", label = "Display Mode", widget = "dropdown", options = {
      { value = "icon", label = "Icon" },
      { value = "bar", label = "Bar" },
      { value = "iconbar", label = "Icon + Bar" },
    } },
    { key = "iconWidth", label = "Icon Width", widget = "spinner", min = 12, max = 256, step = 2, default = 36, help = "Default: 36" },
    { key = "iconHeight", label = "Icon Height", widget = "spinner", min = 12, max = 256, step = 2, default = 36, help = "Default: 36" },
    { key = "barWidth", label = "Bar Width", widget = "spinner", min = 60, max = 512, step = 4, default = 94, help = "Default: 94" },
    { key = "barHeight", label = "Bar Height", widget = "spinner", min = 6, max = 128, step = 2, default = 16, help = "Default: 16" },
    { key = "barSide", label = "Icon Position", widget = "dropdown", options = {
      { value = "right", label = "Icon Left / Bar Right" },
      { value = "left", label = "Icon Right / Bar Left" },
    } },
    { key = "showTimerText", label = "Show Timer Text", widget = "checkbox" },
    { key = "barColor", label = "Bar Color", widget = "color" },
    { key = "lowTime", label = "Low-Time Threshold", widget = "number", min = 0, max = 60 },
  } },
  { key = "Advanced", label = "Advanced", fields = {
    { key = "ruleName", label = "Rule Name", widget = "text", required = false },
    { key = "ruleID", label = "Rule ID", widget = "text", required = false },
    { key = "soundOnShow", label = "Sound On Show", widget = "dropdown", optionsProvider = soundOptions },
    { key = "soundOnExpire", label = "Sound On Expire", widget = "dropdown", optionsProvider = soundOptions },
    { key = "loadClassToken", label = "Load: Class", widget = "dropdown", optionsProvider = loadClassOptions },
    { key = "loadSpecID", label = "Load: Spec", widget = "dropdown", optionsProvider = loadSpecOptions },
    { key = "debug", label = "Debug for this aura", widget = "checkbox" },
    { key = "notes", label = "Notes", widget = "multiline" },
  } },
}

function Schemas:GetTab(tabKey)
  for i = 1, #self.EditorTabs do
    if self.EditorTabs[i].key == tabKey then
      return self.EditorTabs[i]
    end
  end
  return self.EditorTabs[1]
end

