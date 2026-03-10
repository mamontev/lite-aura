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
    { key = "unit", label = "Track Aura On", widget = "dropdown", options = {
      { value = "player", label = "Player" },
      { value = "target", label = "Target" },
    } },
    { key = "ruleName", label = "Rule Name", widget = "text", required = false },
    { key = "ruleID", label = "Rule ID", widget = "text", required = false },
    { key = "castSpellIDs", label = "WHEN Cast SpellIDs (CSV)", widget = "spellcsv", required = true },
    { key = "spellID", label = "THEN Aura SpellID", widget = "spellid", required = true },
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
    { key = "actionMode", label = "THEN Action", widget = "dropdown", options = {
      { value = "produce", label = "Produce/Show Aura" },
      { value = "consume", label = "Consume/Hide Aura" },
    } },
    { key = "duration", label = "Duration (sec)", widget = "number", min = 1, max = 120 },
  } },
  { key = "Display", label = "Display", fields = {
    { key = "name", label = "Aura Name", widget = "text" },
    { key = "group", label = "Group ID", widget = "text" },
    { key = "displayMode", label = "Display Mode", widget = "dropdown", options = {
      { value = "icon", label = "Icon" },
      { value = "bar", label = "Bar" },
      { value = "iconbar", label = "Icon + Bar" },
    } },
    { key = "lowTime", label = "Low-Time Threshold", widget = "number", min = 0, max = 60 },
  } },
  { key = "Sound", label = "Sound", fields = {
    { key = "soundOnShow", label = "Sound On Show", widget = "dropdown", optionsProvider = soundOptions },
    { key = "soundOnExpire", label = "Sound On Expire", widget = "dropdown", optionsProvider = soundOptions },
  } },
  { key = "Advanced", label = "Advanced", fields = {
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

