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
  frame:SetBackdropColor(0.03, 0.06, 0.12, 0.75)
  frame:SetBackdropBorderColor(0.11, 0.46, 0.75, 0.85)
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
    issues[#issues + 1] = { severity = "warn", path = "castSpellIDs", message = "Cast SpellIDs empty: fallback to aura spellID." }
  end

  if #issues == 0 then
    V:SetStatus("ok", "Aura draft looks valid.")
  else
    V:SetEntries(issues)
  end
end

function AuraEditorPanel:LoadAura(auraId)
  self.draft = Repo:GetAuraDraft(auraId)
  if RuleRepo and RuleRepo.ApplyPrimaryRuleToDraft then
    self.draft = RuleRepo:ApplyPrimaryRuleToDraft(self.draft)
  end
  self.currentAuraId = self.draft and self.draft.id or auraId

  if self.titleText then
    self.titleText:SetText(string.format("Aura Editor - %s", tostring((self.draft and self.draft.name) or "New Aura")))
  end

  local tab = (S and S.Get and S:Get().activeTab) or "Trigger"
  self:RenderTab(tab)
  self:ValidateDraft()
end

function AuraEditorPanel:OnFieldChanged(key, value)
  if not self.draft then
    return
  end
  self.draft[key] = value

  if S and S.SetDirty then
    S:SetDirty(true)
  end

  if key == "loadClassToken" and self.currentTab == "Conditions" then
    self:RenderTab("Conditions")
  else
    self:ValidateDraft()
    if self.ruleBuilder then
      self.ruleBuilder:SetDraft(self.draft)
    end
    if self.ruleSummaryText then
      local txt = ""
      local sid = tonumber(self.draft.spellID)
      if sid and sid > 0 and RuleRepo and RuleRepo.DescribeRuleForAura then
        txt = RuleRepo:DescribeRuleForAura(sid)
      end
      self.ruleSummaryText:SetText(txt ~= "" and txt or "No persisted rule yet. Save aura to apply trigger rule.")
    end
  end
end

function AuraEditorPanel:ClearTabFields()
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

  if self.ruleSummary then
    self.ruleSummary:Hide()
    self.ruleSummary:SetParent(nil)
  end
  self.ruleSummary = nil
  self.ruleSummaryText = nil
end

function AuraEditorPanel:RenderTab(tabKey)
  self.currentTab = tabKey
  self:ClearTabFields()

  if not self.content or not self.draft then
    return
  end

  local tab = Schemas and Schemas:GetTab(tabKey) or nil
  if not tab then
    return
  end

  local y = -8

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
    y = y - self.ruleBuilder.frame:GetHeight() - 8

    self.ruleSummary = CreateFrame("Frame", nil, self.content, "BackdropTemplate")
    createBackdrop(self.ruleSummary)
    self.ruleSummary:SetHeight(54)
    self.ruleSummary:SetPoint("TOPLEFT", 12, y)
    self.ruleSummary:SetPoint("RIGHT", -14, 0)

    local t = self.ruleSummary:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    t:SetPoint("TOPLEFT", 10, -8)
    t:SetText("Persisted rule")

    self.ruleSummaryText = self.ruleSummary:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    self.ruleSummaryText:SetPoint("TOPLEFT", 10, -24)
    self.ruleSummaryText:SetPoint("RIGHT", -10, 0)
    self.ruleSummaryText:SetJustifyH("LEFT")

    local desc = ""
    local sid = tonumber(self.draft.spellID)
    if sid and sid > 0 and RuleRepo and RuleRepo.DescribeRuleForAura then
      desc = RuleRepo:DescribeRuleForAura(sid)
    end
    self.ruleSummaryText:SetText(desc ~= "" and desc or "No persisted rule yet. Save aura to apply trigger rule.")

    y = y - 62
  end

  for i = 1, #(tab.fields or {}) do
    local field = tab.fields[i]
    local widget = FieldFactory:CreateField(self.content, field, self.draft, function(key, value)
      self:OnFieldChanged(key, value)
    end)
    widget:SetPoint("TOPLEFT", 14, y)
    widget:SetPoint("RIGHT", -18, 0)
    widget:Show()
    y = y - widget:GetHeight() - 6
    self.fieldWidgets[#self.fieldWidgets + 1] = widget
  end

  self.content:SetHeight(math.max(240, -y + 20))
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
  o.titleText:SetPoint("TOPLEFT", 10, -8)
  o.titleText:SetText("Aura Editor")

  o.statusText = o.frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  o.statusText:SetPoint("TOPRIGHT", -10, -10)
  o.statusText:SetText("Ready")

  o.tabStrip = CreateFrame("Frame", nil, o.frame)
  o.tabStrip:SetPoint("TOPLEFT", 8, -30)
  o.tabStrip:SetPoint("TOPRIGHT", -8, -30)
  o.tabStrip:SetHeight(24)

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
  o.scroll:SetPoint("TOPLEFT", 8, -58)
  o.scroll:SetPoint("BOTTOMRIGHT", -28, 42)

  o.content = CreateFrame("Frame", nil, o.scroll)
  o.content:SetSize(1, 1)
  o.scroll:SetScrollChild(o.content)

  o.btnSave = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnSave:SetSize(100, 24)
  o.btnSave:SetPoint("BOTTOMLEFT", 10, 10)
  o.btnSave:SetText("Save Aura")
  o.btnSave:SetScript("OnClick", function()
    o:SaveCurrent()
  end)

  o.btnReset = CreateFrame("Button", nil, o.frame, "UIPanelButtonTemplate")
  o.btnReset:SetSize(100, 24)
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
      if not state or not o.statusText then
        return
      end
      local dirtyTag = state.dirty and "Dirty" or "Saved"
      o.statusText:SetText(dirtyTag .. " | " .. tostring(state.activeTab or "Trigger"))
    end)
  end

  if V then
    V:Subscribe(function(snapshot)
      if not o.statusText then
        return
      end
      local status = snapshot and snapshot.status or "ok"
      if status == "error" then
        o.statusText:SetTextColor(1, 0.35, 0.35)
      elseif status == "warn" then
        o.statusText:SetTextColor(1, 0.82, 0.2)
      else
        o.statusText:SetTextColor(0.3, 1, 0.5)
      end
    end)
  end

  o:LoadAura(nil)
  return o
end

Panels.AuraEditorPanel = AuraEditorPanel
