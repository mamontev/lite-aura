local _, ns = ...
local U = ns.Utils
local P = ns.PresetLibrary

ns.ProfileManager = ns.ProfileManager or {}
local M = ns.ProfileManager

local DB_VERSION = 1

local function getCharKey()
  local guid = UnitGUID("player")
  if guid and guid ~= "" then
    return guid
  end
  local name, realm = UnitName("player")
  name = name or "Unknown"
  realm = realm or GetRealmName() or "UnknownRealm"
  return name .. "-" .. realm
end

local function getSpecID()
  local idx = GetSpecialization and GetSpecialization()
  if idx and GetSpecializationInfo then
    local specID = GetSpecializationInfo(idx)
    if specID then
      return specID
    end
  end
  return 0
end

local function ensureRoot()
  AuraLiteDB = AuraLiteDB or {}
  local root = AuraLiteDB

  if type(root.version) ~= "number" then
    root.version = DB_VERSION
  end
  root.global = type(root.global) == "table" and root.global or {}
  root.char = type(root.char) == "table" and root.char or {}
  root.profiles = type(root.profiles) == "table" and root.profiles or {}

  if type(root.global.profileMode) ~= "string" then
    root.global.profileMode = "perSpec"
  end
  if root.global.firstRun == nil then
    root.global.firstRun = true
  end

  if not root.profiles.default then
    root.profiles.default = P:BuildEmptyProfile()
  else
    root.profiles.default = U.MergeMissing(root.profiles.default, P:BuildEmptyProfile())
  end

  return root
end

local function ensureCharState(root)
  local key = getCharKey()
  root.char[key] = type(root.char[key]) == "table" and root.char[key] or {}
  local char = root.char[key]
  char.specProfiles = type(char.specProfiles) == "table" and char.specProfiles or {}
  if type(char.manualProfile) ~= "string" or char.manualProfile == "" then
    char.manualProfile = "default"
  end
  return key, char
end

function M:Init()
  self.root = ensureRoot()
  self.charKey, self.char = ensureCharState(self.root)
  self:RefreshActiveProfile()
end

function M:GetCurrentRole()
  local idx = GetSpecialization and GetSpecialization()
  if idx and GetSpecializationRole then
    local role = GetSpecializationRole(idx)
    if role then
      return role
    end
  end
  return "DAMAGER"
end

function M:GetActiveProfileKey()
  local mode = self.root.global.profileMode
  if mode == "manual" then
    local manual = self.char.manualProfile
    if self.root.profiles[manual] then
      return manual
    end
    self.char.manualProfile = "default"
    return "default"
  end

  local specID = getSpecID()
  local key = self.char.specProfiles[specID]
  if type(key) ~= "string" or not self.root.profiles[key] then
    key = "default"
    self.char.specProfiles[specID] = key
  end
  return key
end

function M:RefreshActiveProfile()
  local key = self:GetActiveProfileKey()
  local profile = self.root.profiles[key]
  profile = U.MergeMissing(profile, P:BuildEmptyProfile())
  if ns.SoundManager then
    ns.SoundManager:EnsureOptionsDefaults(profile.options)
  end
  if ns.Localization then
    ns.Localization:EnsureOptionsDefaults(profile.options)
  end
  if ns.Debug then
    ns.Debug:EnsureOptionsDefaults(profile.options)
  end
  if ns.UISkin then
    ns.UISkin:EnsureOptionsDefaults(profile.options)
  end
  self.root.profiles[key] = profile

  self.activeProfileKey = key
  self.activeProfile = profile

  ns.state.profileKey = key
  ns.db = profile
  return profile
end

function M:ListProfiles()
  local keys = {}
  for key in pairs(self.root.profiles) do
    keys[#keys + 1] = key
  end
  table.sort(keys)
  return keys
end

function M:CreateProfile(key, copyFromKey)
  key = U.Trim(key or "")
  if key == "" then
    return nil, "profile name cannot be empty"
  end
  if self.root.profiles[key] then
    return nil, "profile already exists"
  end

  local source = self.root.profiles[copyFromKey or self.activeProfileKey or "default"] or P:BuildEmptyProfile()
  self.root.profiles[key] = U.DeepCopy(source)
  return key
end

function M:DeleteProfile(key)
  key = U.Trim(key or "")
  if key == "" or key == "default" then
    return nil, "cannot delete default profile"
  end
  if not self.root.profiles[key] then
    return nil, "profile does not exist"
  end

  self.root.profiles[key] = nil
  for _, char in pairs(self.root.char) do
    if char.manualProfile == key then
      char.manualProfile = "default"
    end
    for specID, mapped in pairs(char.specProfiles or {}) do
      if mapped == key then
        char.specProfiles[specID] = "default"
      end
    end
  end

  self:RefreshActiveProfile()
  return true
end

function M:SetManualProfile(key)
  key = U.Trim(key or "")
  if key == "" then
    return nil, "profile name cannot be empty"
  end
  if not self.root.profiles[key] then
    return nil, "profile does not exist"
  end

  self.root.global.profileMode = "manual"
  self.char.manualProfile = key
  self:RefreshActiveProfile()
  return true
end

function M:SetCurrentSpecProfile(key)
  key = U.Trim(key or "")
  if key == "" then
    return nil, "profile name cannot be empty"
  end
  if not self.root.profiles[key] then
    return nil, "profile does not exist"
  end

  self.root.global.profileMode = "perSpec"
  self.char.specProfiles[getSpecID()] = key
  self:RefreshActiveProfile()
  return true
end

function M:SetMode(mode)
  if mode ~= "manual" and mode ~= "perSpec" then
    return nil, "mode must be manual or perSpec"
  end
  self.root.global.profileMode = mode
  self:RefreshActiveProfile()
  return true
end

function M:ApplyRolePreset(role, replace)
  P:ApplyRolePreset(self.activeProfile, role, replace == true)
  ns:RebuildWatchIndex()
end

function M:IsFirstRun()
  return self.root.global.firstRun == true
end

function M:MarkFirstRunDone()
  self.root.global.firstRun = false
end

function M:ExportActiveProfile()
  local payload = {
    schema = 1,
    profile = self.activeProfile,
  }
  return U.MakeImportString(payload)
end

function M:ImportProfile(serialized, targetKey, replace)
  local parsed, err = U.ParseImportString(serialized)
  if not parsed then
    return nil, err
  end

  if type(parsed.profile) ~= "table" then
    return nil, "payload missing profile table"
  end

  local key = U.Trim(targetKey or "")
  if key == "" then
    key = self.activeProfileKey
  end

  if not self.root.profiles[key] then
    self.root.profiles[key] = P:BuildEmptyProfile()
  end

  local imported = U.MergeMissing(parsed.profile, P:BuildEmptyProfile())
  if replace then
    self.root.profiles[key] = U.DeepCopy(imported)
  else
    self.root.profiles[key] = U.MergeMissing(self.root.profiles[key], imported)
  end

  self:RefreshActiveProfile()
  return key
end
