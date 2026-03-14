local Harness = {}
Harness.__index = Harness

local function formatValue(value, depth, seen)
  depth = depth or 0
  seen = seen or {}
  local valueType = type(value)
  if valueType == "string" then
    return string.format("%q", value)
  end
  if valueType ~= "table" then
    return tostring(value)
  end
  if seen[value] then
    return "<cycle>"
  end
  seen[value] = true
  if depth >= 2 then
    return "{...}"
  end
  local parts = {}
  for k, v in pairs(value) do
    parts[#parts + 1] = string.format("%s=%s", tostring(k), formatValue(v, depth + 1, seen))
  end
  table.sort(parts)
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function fail(message, level)
  error(message or "assertion failed", (level or 1) + 1)
end

function Harness.new(name)
  return setmetatable({
    name = name or "suite",
    cases = {},
  }, Harness)
end

function Harness:case(name, fn)
  self.cases[#self.cases + 1] = {
    name = name,
    fn = fn,
  }
end

function Harness:run()
  local passed, failed = 0, 0
  local results = {}
  for i = 1, #self.cases do
    local case = self.cases[i]
    local ok, err = pcall(case.fn)
    if ok then
      passed = passed + 1
      results[#results + 1] = {
        ok = true,
        name = case.name,
      }
    else
      failed = failed + 1
      results[#results + 1] = {
        ok = false,
        name = case.name,
        err = err,
      }
    end
  end
  return {
    suite = self.name,
    passed = passed,
    failed = failed,
    results = results,
  }
end

local Assert = {}

function Assert.equal(actual, expected, message)
  if actual ~= expected then
    fail(message or string.format("expected %s, got %s", formatValue(expected), formatValue(actual)), 2)
  end
end

function Assert.truthy(value, message)
  if not value then
    fail(message or string.format("expected truthy value, got %s", formatValue(value)), 2)
  end
end

function Assert.falsy(value, message)
  if value then
    fail(message or string.format("expected falsy value, got %s", formatValue(value)), 2)
  end
end

function Assert.approx(actual, expected, epsilon, message)
  epsilon = tonumber(epsilon) or 0.0001
  if math.abs((tonumber(actual) or 0) - (tonumber(expected) or 0)) > epsilon then
    fail(message or string.format("expected %s ~= %s (eps=%s)", formatValue(actual), formatValue(expected), tostring(epsilon)), 2)
  end
end

function Assert.same(actual, expected, message)
  local function deepEqual(a, b, seen)
    if a == b then
      return true
    end
    if type(a) ~= type(b) then
      return false
    end
    if type(a) ~= "table" then
      return false
    end
    seen = seen or {}
    if seen[a] and seen[a] == b then
      return true
    end
    seen[a] = b
    for k, v in pairs(a) do
      if not deepEqual(v, b[k], seen) then
        return false
      end
    end
    for k in pairs(b) do
      if a[k] == nil then
        return false
      end
    end
    return true
  end

  if not deepEqual(actual, expected) then
    fail(message or string.format("expected %s, got %s", formatValue(expected), formatValue(actual)), 2)
  end
end

function Assert.uniqueStrings(list, message)
  local seen = {}
  for i = 1, #list do
    local value = tostring(list[i] or "")
    if seen[value] then
      fail(message or ("duplicate value: " .. value), 2)
    end
    seen[value] = true
  end
end

return {
  new = Harness.new,
  Assert = Assert,
}
