local specFiles = {
  "tests/spec_settingsdata.lua",
  "tests/spec_procrules.lua",
  "tests/spec_importexport.lua",
  "tests/spec_release_gate.lua",
}

local function loadSpec(path)
  local chunk, err = loadfile(path)
  if not chunk then
    error(err, 0)
  end
  return chunk()
end

local totalPassed, totalFailed = 0, 0

for i = 1, #specFiles do
  local suite = loadSpec(specFiles[i])
  local result = suite:run()
  io.write(string.format("[TEST] %s: %d passed, %d failed\n", result.suite, result.passed, result.failed))
  totalPassed = totalPassed + result.passed
  totalFailed = totalFailed + result.failed
  for j = 1, #result.results do
    local item = result.results[j]
    if not item.ok then
      io.write(string.format("  [FAIL] %s\n%s\n", item.name, tostring(item.err)))
    end
  end
end

io.write(string.format("[TEST] total: %d passed, %d failed\n", totalPassed, totalFailed))
if totalFailed > 0 then
  os.exit(1)
end
