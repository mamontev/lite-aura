local _, ns = ...

ns.Utils = ns.Utils or {}
local U = ns.Utils

function U.Trim(s)
  if type(s) ~= "string" then
    return s
  end
  return s:match("^%s*(.-)%s*$")
end

function U.DeepCopy(value, seen)
  if type(value) ~= "table" then
    return value
  end

  seen = seen or {}
  if seen[value] then
    return seen[value]
  end

  local copy = {}
  seen[value] = copy
  for k, v in pairs(value) do
    copy[U.DeepCopy(k, seen)] = U.DeepCopy(v, seen)
  end
  return copy
end

function U.MergeMissing(dst, src)
  if type(src) ~= "table" then
    return dst
  end
  if type(dst) ~= "table" then
    dst = {}
  end

  for k, v in pairs(src) do
    if type(v) == "table" then
      dst[k] = U.MergeMissing(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end

  return dst
end

function U.TableCount(t)
  local c = 0
  if type(t) ~= "table" then
    return 0
  end
  for _ in pairs(t) do
    c = c + 1
  end
  return c
end

function U.IsArray(t)
  if type(t) ~= "table" then
    return false
  end
  local n = #t
  for k in pairs(t) do
    if type(k) ~= "number" or k % 1 ~= 0 or k < 1 or k > n then
      return false
    end
  end
  return true
end

function U.KeysSortedByNumberField(t, fieldName)
  local keys = {}
  for k in pairs(t or {}) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    local av = (type(t[a]) == "table" and tonumber(t[a][fieldName])) or 0
    local bv = (type(t[b]) == "table" and tonumber(t[b][fieldName])) or 0
    if av == bv then
      return tostring(a) < tostring(b)
    end
    return av < bv
  end)
  return keys
end

local b64chars = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"

function U.Base64Encode(input)
  if type(input) ~= "string" or input == "" then
    return ""
  end
  local binary = input:gsub(".", function(char)
    local byte = char:byte()
    local bits = {}
    for i = 8, 1, -1 do
      bits[#bits + 1] = (byte % (2 ^ i) - byte % (2 ^ (i - 1)) > 0) and "1" or "0"
    end
    return table.concat(bits)
  end) .. "0000"

  local encoded = binary:gsub("%d%d%d?%d?%d?%d?", function(bits)
    if #bits < 6 then
      return ""
    end
    local c = 0
    for i = 1, 6 do
      if bits:sub(i, i) == "1" then
        c = c + (2 ^ (6 - i))
      end
    end
    return b64chars:sub(c + 1, c + 1)
  end)

  return encoded .. ({ "", "==", "=" })[(#input % 3) + 1]
end

function U.Base64Decode(input)
  if type(input) ~= "string" or input == "" then
    return ""
  end

  local sanitized = input:gsub("%s", "")
  if sanitized:find("[^" .. b64chars .. "=]") then
    return nil, "invalid base64 character"
  end

  local binary = sanitized:gsub(".", function(char)
    if char == "=" then
      return ""
    end
    local idx = b64chars:find(char, 1, true)
    if not idx then
      return ""
    end
    local value = idx - 1
    local bits = {}
    for i = 6, 1, -1 do
      bits[#bits + 1] = (value % (2 ^ i) - value % (2 ^ (i - 1)) > 0) and "1" or "0"
    end
    return table.concat(bits)
  end)

  local decoded = binary:gsub("%d%d%d?%d?%d?%d?%d?%d?", function(bits)
    if #bits ~= 8 then
      return ""
    end
    local c = 0
    for i = 1, 8 do
      if bits:sub(i, i) == "1" then
        c = c + (2 ^ (8 - i))
      end
    end
    return string.char(c)
  end)

  return decoded
end

local function escapeJsonString(s)
  local replacements = {
    ['"'] = '\\"',
    ["\\"] = "\\\\",
    ["\b"] = "\\b",
    ["\f"] = "\\f",
    ["\n"] = "\\n",
    ["\r"] = "\\r",
    ["\t"] = "\\t",
  }
  return s:gsub('[\\"%z\1-\31]', function(ch)
    return replacements[ch] or string.format("\\u%04x", ch:byte())
  end)
end

local function encodeJson(value)
  local t = type(value)
  if t == "nil" then
    return "null"
  end
  if t == "number" then
    if value ~= value or value == math.huge or value == -math.huge then
      return "null"
    end
    return tostring(value)
  end
  if t == "boolean" then
    return value and "true" or "false"
  end
  if t == "string" then
    return '"' .. escapeJsonString(value) .. '"'
  end
  if t ~= "table" then
    return "null"
  end

  if U.IsArray(value) then
    local parts = {}
    for i = 1, #value do
      parts[#parts + 1] = encodeJson(value[i])
    end
    return "[" .. table.concat(parts, ",") .. "]"
  end

  local keys = {}
  for k in pairs(value) do
    if type(k) == "string" then
      keys[#keys + 1] = k
    end
  end
  table.sort(keys)

  local parts = {}
  for i = 1, #keys do
    local k = keys[i]
    parts[#parts + 1] = '"' .. escapeJsonString(k) .. '":' .. encodeJson(value[k])
  end
  return "{" .. table.concat(parts, ",") .. "}"
end

function U.JSONEncode(value)
  return encodeJson(value)
end

local function parser(json)
  local idx = 1
  local len = #json

  local function skipWs()
    while idx <= len do
      local c = json:sub(idx, idx)
      if c ~= " " and c ~= "\n" and c ~= "\r" and c ~= "\t" then
        break
      end
      idx = idx + 1
    end
  end

  local parseValue

  local function parseString()
    idx = idx + 1
    local out = {}
    while idx <= len do
      local c = json:sub(idx, idx)
      if c == '"' then
        idx = idx + 1
        return table.concat(out)
      end
      if c == "\\" then
        local esc = json:sub(idx + 1, idx + 1)
        if esc == '"' or esc == "\\" or esc == "/" then
          out[#out + 1] = esc
          idx = idx + 2
        elseif esc == "b" then
          out[#out + 1] = "\b"
          idx = idx + 2
        elseif esc == "f" then
          out[#out + 1] = "\f"
          idx = idx + 2
        elseif esc == "n" then
          out[#out + 1] = "\n"
          idx = idx + 2
        elseif esc == "r" then
          out[#out + 1] = "\r"
          idx = idx + 2
        elseif esc == "t" then
          out[#out + 1] = "\t"
          idx = idx + 2
        elseif esc == "u" then
          local hex = json:sub(idx + 2, idx + 5)
          if not hex:match("^[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$") then
            error("invalid unicode escape at " .. idx)
          end
          local code = tonumber(hex, 16)
          if code <= 127 then
            out[#out + 1] = string.char(code)
          else
            out[#out + 1] = "?"
          end
          idx = idx + 6
        else
          error("invalid escape at " .. idx)
        end
      else
        out[#out + 1] = c
        idx = idx + 1
      end
    end
    error("unterminated string")
  end

  local function parseNumber()
    local start = idx
    local c = json:sub(idx, idx)
    if c == "-" then
      idx = idx + 1
    end
    while idx <= len and json:sub(idx, idx):match("%d") do
      idx = idx + 1
    end
    if json:sub(idx, idx) == "." then
      idx = idx + 1
      while idx <= len and json:sub(idx, idx):match("%d") do
        idx = idx + 1
      end
    end
    local e = json:sub(idx, idx)
    if e == "e" or e == "E" then
      idx = idx + 1
      local sign = json:sub(idx, idx)
      if sign == "+" or sign == "-" then
        idx = idx + 1
      end
      while idx <= len and json:sub(idx, idx):match("%d") do
        idx = idx + 1
      end
    end
    local text = json:sub(start, idx - 1)
    local num = tonumber(text)
    if num == nil then
      error("invalid number at " .. start)
    end
    return num
  end

  local function parseArray()
    idx = idx + 1
    skipWs()
    local arr = {}
    if json:sub(idx, idx) == "]" then
      idx = idx + 1
      return arr
    end
    while true do
      arr[#arr + 1] = parseValue()
      skipWs()
      local c = json:sub(idx, idx)
      if c == "]" then
        idx = idx + 1
        return arr
      end
      if c ~= "," then
        error("expected ',' or ']' at " .. idx)
      end
      idx = idx + 1
      skipWs()
    end
  end

  local function parseObject()
    idx = idx + 1
    skipWs()
    local obj = {}
    if json:sub(idx, idx) == "}" then
      idx = idx + 1
      return obj
    end
    while true do
      if json:sub(idx, idx) ~= '"' then
        error("expected object key at " .. idx)
      end
      local key = parseString()
      skipWs()
      if json:sub(idx, idx) ~= ":" then
        error("expected ':' at " .. idx)
      end
      idx = idx + 1
      skipWs()
      obj[key] = parseValue()
      skipWs()
      local c = json:sub(idx, idx)
      if c == "}" then
        idx = idx + 1
        return obj
      end
      if c ~= "," then
        error("expected ',' or '}' at " .. idx)
      end
      idx = idx + 1
      skipWs()
    end
  end

  function parseValue()
    skipWs()
    local c = json:sub(idx, idx)
    if c == '"' then
      return parseString()
    end
    if c == "-" or c:match("%d") then
      return parseNumber()
    end
    if c == "{" then
      return parseObject()
    end
    if c == "[" then
      return parseArray()
    end
    if json:sub(idx, idx + 3) == "true" then
      idx = idx + 4
      return true
    end
    if json:sub(idx, idx + 4) == "false" then
      idx = idx + 5
      return false
    end
    if json:sub(idx, idx + 3) == "null" then
      idx = idx + 4
      return nil
    end
    error("unexpected token at " .. idx)
  end

  local ok, value = pcall(parseValue)
  if not ok then
    return nil, value
  end

  skipWs()
  if idx <= len then
    return nil, "trailing characters"
  end
  return value
end

function U.JSONDecode(input)
  if type(input) ~= "string" then
    return nil, "input is not a string"
  end
  return parser(input)
end

function U.ResolveSpellID(spellInput)
  if spellInput == nil then
    return nil
  end

  if type(spellInput) == "number" then
    return spellInput
  end

  local text = U.Trim(tostring(spellInput))
  if text == "" then
    return nil
  end

  local numeric = tonumber(text)
  if numeric then
    return numeric
  end

  if C_Spell and C_Spell.GetSpellInfo then
    local info = C_Spell.GetSpellInfo(text)
    if type(info) == "table" and info.spellID then
      return info.spellID
    end
  end

  if GetSpellInfo then
    local _, _, _, _, _, _, id = GetSpellInfo(text)
    if id then
      return id
    end
  end

  return nil
end

function U.MakeImportString(tableData)
  local json = U.JSONEncode(tableData)
  return "AL1:" .. U.Base64Encode(json)
end

function U.ParseImportString(serialized)
  if type(serialized) ~= "string" then
    return nil, "import must be a string"
  end

  local trimmed = U.Trim(serialized)
  if not trimmed:find("^AL1:") then
    return nil, "unsupported import version"
  end

  local payload = trimmed:sub(5)
  local decoded, b64err = U.Base64Decode(payload)
  if not decoded then
    return nil, "invalid base64 payload: " .. tostring(b64err)
  end

  local parsed, jerr = U.JSONDecode(decoded)
  if not parsed then
    return nil, "invalid JSON payload: " .. tostring(jerr)
  end

  return parsed
end
