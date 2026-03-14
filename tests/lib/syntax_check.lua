local M = {}

local function listLuaFiles(root)
  local files = {}
  local escapedRoot = tostring(root or ""):gsub("'", "''")
  local command = string.format([[powershell -NoProfile -Command "Get-ChildItem -Path '%s' -Recurse -File -Filter *.lua | ForEach-Object { $_.FullName }"]], escapedRoot)
  local pipe = io.popen(command, "r")
  if not pipe then
    return files, "unable to enumerate lua files"
  end
  for line in pipe:lines() do
    local path = tostring(line or ""):gsub("\r", "")
    if path ~= "" then
      files[#files + 1] = path
    end
  end
  pipe:close()
  table.sort(files)
  return files
end

function M.run(root)
  local files, err = listLuaFiles(root)
  if not files then
    return nil, err
  end

  local results = {
    root = root,
    checked = 0,
    failed = 0,
    errors = {},
  }

  for i = 1, #files do
    local path = files[i]
    local chunk, loadErr = loadfile(path)
    results.checked = results.checked + 1
    if not chunk then
      results.failed = results.failed + 1
      results.errors[#results.errors + 1] = {
        path = path,
        err = loadErr,
      }
    end
  end

  return results
end

return M
