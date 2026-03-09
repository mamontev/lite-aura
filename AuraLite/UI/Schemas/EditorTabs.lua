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
    local flat = {}
    for i = 1, #(raw or {}) do
      local row = raw[i]
      if row.value ~= nil then
        flat[#flat + 1] = { value = row.value, label = row.label }
      elseif type(row.menuList) == "table" then
        for j = 1, #row.menuList do
          flat[#flat + 1] = { value = row.menuList[j].value, label = row.label .. " - " .. row.menuList[j].label }
        end
      end
    end
    return flat
  end
  return { { value = "", label = "Any Spec" } }
end

Schemas.EditorTabs = {
  { key = "Trigger", label = "Trigger", fields = {
    { key = "name", label = "Aura Name", widget = "text", required = true },
    { key = "spellID", label = "Aura Spell ID", widget = "text", required = true },
    { key = "castSpellIDs", label = "Cast SpellIDs (CSV)", widget = "text" },
    { key = "triggerType", label = "Trigger Type", widget = "dropdown", options = {
      { value = "cast", label = "Cast Spell" },
      { value = "aura", label = "Aura Present" },
      { value = "rule", label = "Custom Rule" },
    } },
    { key = "unit", label = "Unit", widget = "dropdown", options = {
      { value = "player", label = "Player" },
      { value = "target", label = "Target" },
    } },
  } },
  { key = "Conditions", label = "Conditions", fields = {
    { key = "conditionLogic", label = "Condition Logic", widget = "dropdown", options = {
      { value = "all", label = "AND (all)" },
      { value = "any", label = "OR (any)" },
    } },
    { key = "loadClassToken", label = "Load Class", widget = "dropdown", optionsProvider = loadClassOptions },
    { key = "loadSpecID", label = "Load Spec", widget = "dropdown", optionsProvider = loadSpecOptions },
    { key = "inCombatOnly", label = "In Combat Only", widget = "checkbox" },
    { key = "notes", label = "Condition Notes", widget = "multiline" },
  } },
  { key = "Actions", label = "Actions", fields = {
    { key = "actionMode", label = "Action", widget = "dropdown", options = {
      { value = "produce", label = "Produce Aura" },
      { value = "consume", label = "Consume Aura" },
    } },
    { key = "duration", label = "Duration (sec)", widget = "number", min = 1, max = 60 },
  } },
  { key = "Display", label = "Display", fields = {
    { key = "displayMode", label = "Display Mode", widget = "dropdown", options = {
      { value = "icon", label = "Icon" },
      { value = "bar", label = "Bar" },
      { value = "iconbar", label = "Icon + Bar" },
    } },
    { key = "lowTime", label = "Low Time Threshold", widget = "number", min = 0, max = 20 },
  } },
  { key = "Sound", label = "Sound", fields = {
    { key = "soundOnShow", label = "On Show", widget = "dropdown", options = {
      { value = "default", label = "Default" },
      { value = "none", label = "None" },
    } },
    { key = "soundOnExpire", label = "On Expire", widget = "dropdown", options = {
      { value = "default", label = "Default" },
      { value = "none", label = "None" },
    } },
  } },
  { key = "Advanced", label = "Advanced", fields = {
    { key = "group", label = "Group", widget = "text" },
    { key = "debug", label = "Enable Debug", widget = "checkbox" },
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
