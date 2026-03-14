local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
local UI = ns.UIV2

UI.Events = UI.Events or {}
local E = UI.Events

E._listeners = E._listeners or {}
E.Names = E.Names or {
  AURA_SELECTED = "UI_AURA_SELECTED",
  FILTER_CHANGED = "UI_FILTER_CHANGED",
  NEW_AURA = "UI_NEW_AURA",
  STATE_CHANGED = "UI_STATE_CHANGED",
  TAB_CHANGED = "UI_TAB_CHANGED",
  VALIDATION_CHANGED = "UI_VALIDATION_CHANGED",
  OPEN_GLOBAL_PANEL = "UI_OPEN_GLOBAL_PANEL",
  OPEN_IMPORT_PANEL = "UI_OPEN_IMPORT_PANEL",
  OPEN_GROUPS_PANEL = "UI_OPEN_GROUPS_PANEL",
  SIMULATE_TRIGGER = "UI_SIMULATE_TRIGGER",
}

local function dispatchError(err)
  local handler = geterrorhandler and geterrorhandler()
  if handler then
    handler(err)
  end
end

function E:On(eventName, callback)
  if type(eventName) ~= "string" or eventName == "" or type(callback) ~= "function" then
    return function() end
  end

  local list = self._listeners[eventName]
  if not list then
    list = {}
    self._listeners[eventName] = list
  end
  list[#list + 1] = callback

  return function()
    E:Off(eventName, callback)
  end
end

function E:Off(eventName, callback)
  local list = self._listeners[eventName]
  if not list then
    return
  end
  for i = #list, 1, -1 do
    if list[i] == callback then
      table.remove(list, i)
    end
  end
end

function E:Emit(eventName, payload)
  local list = self._listeners[eventName]
  if not list or #list == 0 then
    return
  end

  local snapshot = {}
  for i = 1, #list do
    snapshot[i] = list[i]
  end

  for i = 1, #snapshot do
    local ok, err = pcall(snapshot[i], payload)
    if not ok then
      dispatchError(err)
    end
  end
end

function E:Clear(eventName)
  if eventName then
    self._listeners[eventName] = nil
    return
  end
  self._listeners = {}
end
