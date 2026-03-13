local _, ns = ...
local U = ns.Utils

ns.SpellCatalog = ns.SpellCatalog or {}
local C = ns.SpellCatalog

C._normalized = C._normalized or nil
C._nameToID = C._nameToID or {}
C._tokenIndex = C._tokenIndex or nil
C._prefixIndex = C._prefixIndex or nil
C._searchCache = C._searchCache or {}
C._runtimeRows = C._runtimeRows or nil
C._runtimeRowsBuiltAt = C._runtimeRowsBuiltAt or 0

local function normalizeText(text)
  if type(text) ~= "string" then
    return ""
  end
  return text:lower():gsub("[_%-%./]+", " "):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tokenizeText(text)
  local out = {}
  local normalized = normalizeText(text)
  for token in normalized:gmatch("[^%s]+") do
    out[#out + 1] = token
  end
  return out
end

local function addIndexRow(index, key, row)
  if key == "" then
    return
  end
  local bucket = index[key]
  if not bucket then
    bucket = {}
    index[key] = bucket
  end
  bucket[#bucket + 1] = row
end

local function uniqueTokens(tokens)
  local out, seen = {}, {}
  for i = 1, #(tokens or {}) do
    local token = tostring(tokens[i] or "")
    if token ~= "" and not seen[token] then
      seen[token] = true
      out[#out + 1] = token
    end
  end
  return out
end

local function boundedLevenshtein(a, b, maxDistance)
  a = tostring(a or "")
  b = tostring(b or "")
  maxDistance = tonumber(maxDistance) or 2
  if a == b then
    return 0
  end
  if a == "" or b == "" then
    return math.max(#a, #b)
  end
  if math.abs(#a - #b) > maxDistance then
    return maxDistance + 1
  end

  local previous = {}
  for j = 0, #b do
    previous[j] = j
  end

  for i = 1, #a do
    local current = { [0] = i }
    local rowMin = current[0]
    local aChar = a:sub(i, i)
    for j = 1, #b do
      local cost = (aChar == b:sub(j, j)) and 0 or 1
      local deletion = previous[j] + 1
      local insertion = current[j - 1] + 1
      local substitution = previous[j - 1] + cost
      local value = math.min(deletion, insertion, substitution)
      current[j] = value
      if value < rowMin then
        rowMin = value
      end
    end
    if rowMin > maxDistance then
      return maxDistance + 1
    end
    previous = current
  end

  return previous[#b]
end

local function bestTokenSimilarity(queryToken, rowTokens)
  queryToken = normalizeText(queryToken)
  if queryToken == "" then
    return 0
  end
  local best = 0
  for i = 1, #(rowTokens or {}) do
    local rowToken = tostring(rowTokens[i] or "")
    if rowToken == queryToken then
      return 120
    end
    if rowToken:find(queryToken, 1, true) == 1 then
      if best < 88 then
        best = 88
      end
    else
      local containsAt = rowToken:find(queryToken, 1, true)
      if containsAt and #queryToken >= 5 and (#rowToken - #queryToken) <= 4 then
        if best < 28 then
          best = 28
        end
      end
      local dist = boundedLevenshtein(queryToken, rowToken, 2)
      if dist == 1 and best < 42 then
        best = 42
      elseif dist == 2 and best < 24 then
        best = 24
      end
    end
  end
  return best
end

local function scoreNumericQuery(row, normalized)
  local idText = tostring(row.id or "")
  if idText == normalized then
    return 1000
  end
  if idText:find(normalized, 1, true) == 1 then
    return 700 - math.max(0, #idText - #normalized)
  end
  if idText:find(normalized, 1, true) then
    return 420
  end
  return nil
end

local function scoreTextQuery(row, normalized, queryTokens)
  local name = tostring(row.normalized or "")
  if name == "" then
    return nil
  end

  local score = 0
  local wholeIndex = name:find(normalized, 1, true)
  local boundaryStart = false
  local boundaryEnd = false
  if wholeIndex then
    local endIndex = wholeIndex + #normalized - 1
    boundaryStart = wholeIndex == 1 or name:sub(wholeIndex - 1, wholeIndex - 1) == " "
    boundaryEnd = endIndex >= #name or name:sub(endIndex + 1, endIndex + 1) == " "
  end
  if name == normalized then
    score = score + 1200
  elseif wholeIndex == 1 then
    score = score + 820
  elseif wholeIndex and boundaryStart and boundaryEnd then
    score = score + 520
  elseif wholeIndex and (boundaryStart or boundaryEnd) then
    score = score + 180
  end

  local matchedTokens = 0
  local tokenScore = 0
  for i = 1, #(queryTokens or {}) do
    local similarity = bestTokenSimilarity(queryTokens[i], row.tokens or {})
    if similarity > 0 then
      matchedTokens = matchedTokens + 1
      tokenScore = tokenScore + similarity
    end
  end

  if matchedTokens == 0 then
    local dist = boundedLevenshtein(normalized, name, 2)
    if dist == 1 then
      score = score + 160
    elseif dist == 2 then
      score = score + 90
    else
      return nil
    end
  else
    if matchedTokens < #(queryTokens or {}) and not wholeIndex then
      return nil
    end
    score = score + tokenScore
    if matchedTokens == #(queryTokens or {}) then
      score = score + 180
    end
  end

  local lengthDelta = math.abs(#name - #normalized)
  score = score + math.max(0, 40 - lengthDelta)

  if row.fromProfile == true then
    score = score + 120
  end

  return score
end

local function addUnique(out, seen, row)
  if not row or not row.id then
    return
  end
  local key = tostring(row.id) .. "|" .. normalizeText(row.name or "")
  if seen[key] then
    return
  end
  seen[key] = true
  out[#out + 1] = row
end

local function isUsableSpellName(normalized)
  if normalized == "" then
    return false
  end
  if normalized:find("dnt", 1, true) then
    return false
  end
  if normalized:find("dummy", 1, true) then
    return false
  end
  if normalized:find("test", 1, true) then
    return false
  end
  if normalized:find("unused", 1, true) then
    return false
  end
  return true
end

function C:BuildStaticIndex()
  if self._normalized then
    return
  end

  local rows = {}
  local nameToID = {}
  local tokenIndex = {}
  local prefixIndex = {}
  for _, row in ipairs(ns.SpellCatalogData or {}) do
    local id = tonumber(row.id)
    local name = tostring(row.name or "")
    if id and name ~= "" then
      local normalized = normalizeText(name)
      if isUsableSpellName(normalized) then
      rows[#rows + 1] = {
        id = id,
        name = name,
        normalized = normalized,
        tokens = tokenizeText(normalized),
        popularity = tonumber(row.popularity) or 0,
      }
      local item = rows[#rows]
      local tokens = uniqueTokens(item.tokens)
      for i = 1, #tokens do
        local token = tokens[i]
        addIndexRow(tokenIndex, token, item)
        for length = 1, math.min(4, #token) do
          addIndexRow(prefixIndex, token:sub(1, length), item)
        end
      end
      if normalized ~= "" and not nameToID[normalized] then
        nameToID[normalized] = id
      end
      end
    end
  end

  table.sort(rows, function(a, b)
    if a.popularity ~= b.popularity then
      return a.popularity > b.popularity
    end
    if a.name == b.name then
      return a.id < b.id
    end
    return a.name < b.name
  end)

  self._normalized = rows
  self._nameToID = nameToID
  self._tokenIndex = tokenIndex
  self._prefixIndex = prefixIndex
end

function C:GatherProfileSpells()
  local out = {}
  local seenIDs = {}
  local seenRows = {}
  if not ns.db or not ns.db.watchlist then
    return out
  end

  local function addProfileSpell(spellID, unit, fromCastList)
    spellID = tonumber(spellID)
    if not spellID or spellID <= 0 or seenIDs[spellID] then
      return
    end
    local name = ns.AuraAPI:GetSpellName(spellID) or ("Spell " .. spellID)
    seenIDs[spellID] = true
    addUnique(out, seenRows, {
      id = spellID,
      name = name,
      normalized = normalizeText(name),
      tokens = tokenizeText(name),
      popularity = fromCastList and 1250000 or 999999,
      unit = unit,
      fromProfile = true,
      fromCastList = fromCastList == true,
    })
  end

  for unit, list in pairs(ns.db.watchlist) do
    for _, item in ipairs(list) do
      addProfileSpell(item.spellID, unit, false)
      if type(item.castSpellIDs) == "table" then
        for i = 1, #item.castSpellIDs do
          addProfileSpell(item.castSpellIDs[i], unit, true)
        end
      end
    end
  end

  return out
end

function C:GatherPlayerSpellbookSpells()
  local out = {}
  local seen = {}
  if not C_SpellBook or not Enum or not Enum.SpellBookSpellBank or not C_SpellBook.GetNumSpellBookSkillLines or not C_SpellBook.GetSpellBookSkillLineInfo then
    return out
  end

  local bank = Enum.SpellBookSpellBank.Player
  local lineCount = tonumber(C_SpellBook.GetNumSpellBookSkillLines()) or 0
  for lineIndex = 1, lineCount do
    local info = C_SpellBook.GetSpellBookSkillLineInfo(lineIndex)
    local offset = tonumber(info and info.itemIndexOffset) or 0
    local count = tonumber(info and info.numSpellBookItems) or 0
    for slotIndex = offset + 1, offset + count do
      local name = C_SpellBook.GetSpellBookItemName and C_SpellBook.GetSpellBookItemName(slotIndex, bank) or nil
      local itemInfo = C_SpellBook.GetSpellBookItemInfo and C_SpellBook.GetSpellBookItemInfo(slotIndex, bank) or nil
      local actionID = tonumber(itemInfo and itemInfo.actionID) or 0
      if actionID > 16777215 then
        actionID = actionID % 16777216
      end
      local spellID = actionID > 0 and actionID or nil
      if spellID and name and name ~= "" and not seen[spellID] then
        seen[spellID] = true
        out[#out + 1] = {
          id = spellID,
          name = name,
          normalized = normalizeText(name),
          tokens = tokenizeText(name),
          popularity = 1500000,
          fromSpellbook = true,
        }
      end
    end
  end

  return out
end

function C:GetRuntimeRows()
  local now = GetTime and GetTime() or 0
  if self._runtimeRows and (now - (tonumber(self._runtimeRowsBuiltAt) or 0)) < 1.0 then
    return self._runtimeRows
  end

  local rows = {}
  local profileRows = self:GatherProfileSpells()
  for i = 1, #profileRows do
    rows[#rows + 1] = profileRows[i]
  end
  local spellbookRows = self:GatherPlayerSpellbookSpells()
  for i = 1, #spellbookRows do
    rows[#rows + 1] = spellbookRows[i]
  end

  self._runtimeRows = rows
  self._runtimeRowsBuiltAt = now
  self._searchCache = {}
  return rows
end

function C:ResolveNameToSpellID(name)
  self:BuildStaticIndex()
  local n = normalizeText(name)
  if n == "" then
    return nil
  end
  return self._nameToID[n]
end

function C:Search(query, maxCount)
  self:BuildStaticIndex()
  maxCount = tonumber(maxCount) or 8
  if maxCount < 1 then
    maxCount = 1
  end
  if maxCount > 30 then
    maxCount = 30
  end

  local text = U.Trim(query or "")
  local normalized = normalizeText(text)
  if normalized == "" then
    return {}
  end
  local cacheKey = tostring(maxCount) .. "|" .. normalized
  if self._searchCache and self._searchCache[cacheKey] then
    return self._searchCache[cacheKey]
  end

  local isNumeric = tonumber(normalized) ~= nil
  local out = {}
  local seen = {}
  local runtimeRows = self:GetRuntimeRows()
  local injectedNumericExact = nil

  if isNumeric then
    local exactID = tonumber(normalized)
    if exactID then
      local name = ns.AuraAPI:GetSpellName(exactID)
      if name then
        injectedNumericExact = {
          id = exactID,
          name = name,
          normalized = normalizeText(name),
          tokens = tokenizeText(name),
          popularity = 1000000,
        }
      end
    end
  end

  local queryTokens = tokenizeText(normalized)
  local scored = {}
  local candidates = {}
  local candidateSeen = {}

  local function pushCandidate(row)
    if not row or not row.id then
      return
    end
    local key = tostring(row.id) .. "|" .. normalizeText(row.name or "")
    if candidateSeen[key] then
      return
    end
    candidateSeen[key] = true
    candidates[#candidates + 1] = row
  end

  local function addFromBuckets(index, key)
    local rows = index and index[key]
    if type(rows) ~= "table" then
      return
    end
    for i = 1, #rows do
      pushCandidate(rows[i])
    end
  end

  local function consider(row)
    if not row or not row.id then
      return
    end
    local key = tostring(row.id) .. "|" .. normalizeText(row.name or "")
    if seen[key] then
      return
    end
    local score = isNumeric and scoreNumericQuery(row, normalized) or scoreTextQuery(row, normalized, queryTokens)
    if not score or score <= 0 then
      return
    end
    scored[#scored + 1] = {
      row = row,
      score = score,
      popularity = tonumber(row.popularity) or 0,
      nameLength = #(tostring(row.normalized or "")),
    }
  end

  if injectedNumericExact then
    consider(injectedNumericExact)
  end
  for i = 1, #runtimeRows do
    pushCandidate(runtimeRows[i])
  end

  if isNumeric then
    for i = 1, #self._normalized do
      local row = self._normalized[i]
      if tostring(row.id):find(normalized, 1, true) then
        pushCandidate(row)
      end
    end
  else
    for i = 1, #queryTokens do
      local token = queryTokens[i]
      addFromBuckets(self._tokenIndex, token)
      addFromBuckets(self._prefixIndex, token:sub(1, math.min(4, #token)))
    end
    if #candidates < (maxCount * 6) then
      for i = 1, #self._normalized do
        local row = self._normalized[i]
        if row.normalized == normalized or row.normalized:find(normalized, 1, true) then
          pushCandidate(row)
        end
      end
    end
    if #candidates < (maxCount * 3) then
      for i = 1, #self._normalized do
        local row = self._normalized[i]
        local tokens = row.tokens or {}
        for j = 1, #tokens do
          local token = tokens[j]
          if token:find(queryTokens[1] or normalized, 1, true) then
            pushCandidate(row)
            break
          end
        end
      end
    end
  end

  for i = 1, #candidates do
    consider(candidates[i])
  end

  table.sort(scored, function(a, b)
    if a.score ~= b.score then
      return a.score > b.score
    end
    if a.popularity ~= b.popularity then
      return a.popularity > b.popularity
    end
    if a.nameLength ~= b.nameLength then
      return a.nameLength < b.nameLength
    end
    if a.row.name ~= b.row.name then
      return a.row.name < b.row.name
    end
    return (tonumber(a.row.id) or 0) < (tonumber(b.row.id) or 0)
  end)

  for i = 1, #scored do
    addUnique(out, seen, scored[i].row)
    if #out >= maxCount then
      break
    end
  end

  self._searchCache[cacheKey] = out
  return out
end
