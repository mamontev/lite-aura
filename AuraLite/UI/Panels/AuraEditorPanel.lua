local _, ns = ...

ns.UIV2 = ns.UIV2 or {}
ns.UIV2.Panels = ns.UIV2.Panels or {}

local UI = ns.UIV2
local Panels = UI.Panels
local E = UI.Events
local S = UI.State
local V = UI.ValidationBus
local Schemas = UI.Schemas
local Repo = UI.AuraRepository
local RuleRepo = UI.RuleRepository
local FieldFactory = UI.FieldFactory
local Widgets = UI.Widgets or {}

local AuraEditorPanel = {}
AuraEditorPanel.__index = AuraEditorPanel

local function createBackdrop(frame)
  frame:SetBackdrop({
    bgFile = "Interface/Tooltips/UI-Tooltip-Background",
    edgeFile = "Interface/Tooltips/UI-Tooltip-Border",
    edgeSize = 12,
    insets = { left = 2, right = 2, top = 2, bottom = 2 },
  })
  frame:SetBackdropColor(0.03, 0.08, 0.18, 0.72)
  frame:SetBackdropBorderColor(0.12, 0.50, 0.82, 0.90)
end

local function setTabVisual(btn, active)
  if not btn then
    return
  end
  if active then
    btn:SetNormalFontObject("GameFontNormal")
    btn:SetTextColor(1.0, 0.85, 0.2)
  else
    btn:SetNormalFontObject("GameFontHighlight")
    btn:SetTextColor(0.8, 0.88, 1.0)
  end
end

function AuraEditorPanel:ValidateDraft()
  local issues = {}
  if not self.draft then
    V:SetStatus("warn", "No aura selected.")
    return
  end

  if tostring(self.draft.name or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "name", message = "Aura name is empty." }
  end

  local sid = tonumber(self.draft.spellID)
  if not sid or sid <= 0 then
    issues[#issues + 1] = { severity = "error", path = "spellID", message = "Aura SpellID is required." }
  end

  if tostring(self.draft.triggerType or "cast") == "cast" and tostring(self.draft.castSpellIDs or "") == "" then
    issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "WHEN cast list is empty." }
  end

  if #issues == 0 then
    V:SetStatus("ok", "Aura draft looks valid.")
  else
    V:SetEntries(issues)
  end
end

function AuraEditorPanel:UpdateHeader()
  if not self.draft then
    self.titleText:SetText("Aura Editor")
    self.subtitle:SetText("Select an aura from the list or create a new one.")
    return
  end
  self.titleText:SetText(string.format("Aura Editor - %s", tostring(self.draft.name or "New Aura")))
  self.subtitle:SetText(string.format("SpellID: %s | Unit: %s | Group: %s", tostring(self.draft.spellID or "?"), tostring(self.draft.unit or "player"), tostring(self.draft.group or "-")))
end

function AuraEditorPanel:LoadAura(auraId)
  self.draft = Repo:GetAuraDraft(auraId)
  if RuleRepo and RuleRepo.ApplyPrimaryRuleToDraft then
    self.draft = RuleRepo:ApplyPrimaryRuleToDraft(self.draft)
  end
  self.currentAuraId = self.draft and self.draft.id or auraId

  self:UpdateHeader()
  local tab = (S and S.Get and S:Get().activeTab) or "Trigger"
  self:RenderTab(tab)
  self:ValidateDraft()
end

function AuraEditorPanel:OnFieldChanged(key, value)
  if not self.draft then
    return
  end

  self.draft[key] = value

  if key == "loadClassToken" and (self.currentTab == "Advanced" or self.currentTab == "Conditions") then
    self:RenderTab(self.currentTab)
  end

  if S and S.SetDirty then
    S:SetDirty(true)
  end

  self:UpdateHeader()
  self:ValidateDraft()

  if self.ruleBuilder then
    self.ruleBuilder:SetDraft(self.draft)
  end
  if self.conditionTree then
    self.conditionTree:SetDraft(self.draft)
  end

  if E then
    E:Emit(E.Names.STATE_CHANGED, S and S:Get() or nil)
  end
end

function AuraEditorPanel:ClearTabContent()
  for i = 1, #(self.fieldWidgets or {}) do
    local w = self.fieldWidgets[i]
    if w then
      w:Hide()
      w:SetParent(nil)
    end
  end
  self.fieldWidgets = {}

  if self.ruleBuilder and self.ruleBuilder.frame then
    self.ruleBuilder.frame:Hide()
    self.ruleBuilder.frame:SetParent(nil)
  end
  self.ruleBuilder = nil

  if self.conditionTree and self.conditionTree.frame then
    self.conditionTree.frame:Hide()
    self.conditionTree.frame:SetParent(nil)
  end
  self.conditionTree = nil
end

function AuraEditorPanel:RenderGenericFields(tab, yStart)
  local y = yStart
  for i = 1, #(tab.fields or {}) do
    local field = tab.fields[i]
    local widget = FieldFactory:CreateField(self.content, field, self.draft, function(fKey, fValue)
      self:OnFieldChanged(fKey, fValue)
    end)
    widget:SetPoint("TOPLEFT", 16, y)
    widget:SetPoint("RIGHT", -24, 0)
    widget:Show()
    y = y - widget:GetHeight() - 8
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
  end
  return y
end

function AuraEditorPanel:RenderTab(tabKey)
  self.currentTab = tabKey
  self:ClearTabContent()

  if not self.content or not self.draft then
    return
  end

  local tab = Schemas and Schemas:GetTab(tabKey) or nil
  if not tab then
    return
  end

  for key, btn in pairs(self.tabs or {}) do
    setTabVisual(btn, key == tabKey)
  end

  local y = -12

  if tabKey == "Trigger" and Widgets.RuleBuilderWidget and Widgets.RuleBuilderWidget.Create then
    self.ruleBuilder = Widgets.RuleBuilderWidget:Create(self.content, function()
      if S and S.SetDirty then
        S:SetDirty(true)
      end
      self:ValidateDraft()
      self:RenderTab("Trigger")
    end)
    self.ruleBuilder.frame:SetPoint("TOPLEFT", 12, y)
    self.ruleBuilder.frame:SetPoint("RIGHT", -14, 0)
    self.ruleBuilder.frame:Show()
    self.ruleBuilder:SetDraft(self.draft)
    y = y - self.ruleBuilder.frame:GetHeight() - 10

    local descFrame = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
    createBackdrop(descFrame)
    descFrame:SetHeight(56)
    descFrame:SetPoint("TOPLEFT", 12, y)
    descFrame:SetPoint("RIGHT", -14, 0)

    local lbl = descFrame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    lbl:SetPoint("TOPLEFT", 10, -8)
    lbl:SetText("Persisted rule")

    local text = descFrame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    text:SetPoint("TOPLEFT", 10, -26)
    text:SetPoint("RIGHT", -10, 0)
    text:SetJustifyH("LEFT")

    local desc = ""
    local sid = tonumber(self.draft.spellID)
    if sid and sid > 0 and RuleRepo and RuleRepo.DescribeRuleForAura then
      desc = RuleRepo:DescribeRuleForAura(sid)
    end
    text:SetText(desc ~= "" and desc or "No persisted rule yet. Save aura to apply trigger rule.")

    self.fieldWidgets[#self.fieldWidgets + 1] = descFrame
    y = y - 64
  elseif tabKey == "Conditions" and Widgets.ConditionTreeWidget and Widgets.ConditionTreeWidget.Create then
    self.conditionTree = Widgets.ConditionTreeWidget:Create(self.content, function()
      if S and S.SetDirty then
        S:SetDirty(true)
      end
      self:ValidateDraft()
      self:UpdateHeader()
    end)
    self.conditionTree.frame:SetPoint("TOPLEFT", 12, y)
    self.conditionTree.frame:SetPoint("RIGHT", -14, 0)
    self.conditionTree.frame:Show()
    self.conditionTree:SetDraft(self.draft)
    y = y - self.conditionTree.frame:GetHeight() - 10
  end

  if tabKey ~= "Conditions" then
    y = self:RenderGenericFields(tab, y)
  end

  self.content:SetHeight(math.max(360, -y + 20))
  self:ValidateDraft()
end

function AuraEditorPanel:SelectTab(tabKey)
  if S and S.SetActiveTab then
    S:SetActiveTab(tabKey)
  end
  self:RenderTab(tabKey)
end

function AuraEditorPanel:SaveCurrent()
  if not self.draft then
    return
  end

  local ok, savedId, err = Repo:SaveDraft(self.draft)
  if not ok then
    V:SetStatus("error", tostring(err or "Save failed"))
    return
  end

  self.draft.id = savedId or self.draft.id

  if RuleRepo and RuleRepo.SaveRuleFromDraft then
    local rok, rerr = RuleRepo:SaveRuleFromDraft(self.draft)
    if rok ~= true and rerr then
      V:Push("warn", "rule", tostring(rerr))
    end
  end

  if S and S.SetDirty then
    S:SetDirty(false)
  end
  if S and S.SetSelectedAura and savedId then
    S:SetSelectedAura(savedId, "save")
  end

  self:ValidateDraft()
  if E then
    E:Emit(E.Names.FILTER_CHANGED, { key = "save", value = savedId })
  end
end

function AuraEditorPanel:Create(parent)
  local o = setmetatable({}, self)
  o.fieldWidgets = {}
  o.currentTab = "Trigger"

  o.frame = CreateFrame("Frame", nil, parent, "BackdropTemplate")
  o.frame:SetAllPoints()
  createBackdrop(o.frame)

  o.titleText = o.frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  o.titleText:SetPoint("TOPLEFT", 12, -10)
  o.titleText:SetText("Aura Editor")

  o.subtitle = o.frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  o.subtitle:SetPoint("TOPLEFT", 12, -28)
  o.subtitle:SetPoint("RIGHT", -14, 0)
  o.subtitle:SetJustifyH("LEFT")
  o.subtitle:SetText("Select an aura from the list or create a new one.")

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 10, -48)
  o.tabStrip:SetPoint("TOPRIGHT", -10, -48)
  o.tabStrip:SetHeight(26)

  o.tabs = {}
  local x = 0
  for i = 1, #(Schemas and Schemas.EditorTabs or {}) do
    local tab = Schemas.EditorTabs[i]
    local btn = CreateFrame("Button", nil, o.tabStrip, "UIPanelButtonTemplate")
    btn:SetSize(96, 22)
    btn:SetPoint("TOPLEFT", x, 0)
    btn:SetText(tab.label or tab.key)
    btn:SetScript("OnClick", function()
      o:SelectTab(tab.key)
    end)
    o.tabs[tab.key] = btn
    x = x + 100
  end

  o.scroll = CreateFrame("ScrollFrame", nil, o.frame, "UIPanelScrollFrameTemplate")
  o.scroll:SetPoint("TOPLEFT", 8, -76)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 48)

  o.content = CreateFrame("Frame", nil, o.scroll)
  o.content:SetSize(1, 1)
  o.scroll:SetScrollChild(o.content)

  o.status = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.status:SetPoint("BOTTOMLEFT", 12, 30)
  o.status:SetPoint("RIGHT", -12, 0)
  o.status:SetJustifyH("LEFT")
  o.status:SetText("Ready")

  o.btnSave = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSave:SetSize(110, 24)
  o.btnSave:SetPoint("BOTTOMLEFT", 10, 8)
  o.btnSave:SetText("Save Aura")
  o.btnSave:SetScript("OnClick", function()
    o:SaveCurrent()
  end)

  o.btnReset = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnReset:SetSize(110, 24)
  o.btnReset:SetPoint("LEFT", o.btnSave, "RIGHT", 8, 0)
  o.btnReset:SetText("Reset")
  o.btnReset:SetScript("OnClick", function()
    o:LoadAura(o.currentAuraId)
  end)

  if E then
    E:On(E.Names.AURA_SELECTED, function(payload)
      o:LoadAura(payload and payload.auraId or nil)
    end)

    E:On(E.Names.NEW_AURA, function()
      local draft = Repo:CreateDraft()
      if S and S.SetSelectedAura then
        S:SetSelectedAura(draft.id, "new")
      end
      o:LoadAura(draft.id)
    end)

    E:On(E.Names.STATE_CHANGED, function(state)
      if not state or not o.status then
        return
      end
      local dirtyTag = state.dirty and "Dirty" or "Saved"
      o.status:SetText(dirtyTag .. " | Tab: " .. tostring(state.activeTab or "Trigger"))
    end)
  end

  if V then
    V:Subscribe(function(snapshot)
      if not o.status then
        return
      end
      local status = snapshot and snapshot.status or "ok"
      local entries = snapshot and snapshot.entries or {}
      local msg = (#entries > 0 and entries[1].message) or "Ready"
      if status == "error" then
        o.status:SetTextColor(1, 0.35, 0.35)
      elseif status == "warn" then
        o.status:SetTextColor(1, 0.82, 0.2)
      else
        o.status:SetTextColor(0.30, 1.0, 0.5)
      end
      o.status:SetText(msg)
    end)
  end

  o:LoadAura(nil)
  return o
end

Panels.AuraEditorPanel = AuraEditorPanel
