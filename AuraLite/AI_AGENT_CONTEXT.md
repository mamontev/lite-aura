# AuraLite - AI Agent Context

This file gives operational context for AI agents working on AuraLite (WoW Retail/Midnight 12.x).

## Scope
- AuraLite is a visual+audio tracker (WeakAuras-like), not a rotation helper.
- No protected automation, no secure action templates, no protected frame manipulation in combat.

## Core Modules
- `Core.lua`: bootstrap, SavedVariables, module wiring.
- `EventRouter.lua`: event routing and refresh.
- `ProcRuleEngine.lua`: produce/consume rules and synthetic aura runtime state.
- `TrackerGroupManager.lua`: on-screen icon/bar rendering and layout.
- `AuraAPIAdapter.lua`: safe API wrapper for aura/spell/cooldown reads.

## Config/Data Layer
- `SettingsData.lua`: persistent aura/watchlist model.
- `ConfigUI.lua`: slash/config entrypoints.
- `SoundManager.lua`, `Localization.lua`, `ProfileManager.lua`, `PresetLibrary.lua`.

## UI v2 (current editor stack)
Directory: `AuraLite/UI/`
- `UIBootstrap.lua`: open/toggle UI.
- `UIState.lua`: selected aura / active tab / dirty state.
- `UIEvents.lua`: UI event bus.
- `ValidationBus.lua`: validation warnings/errors.
- `Schemas/EditorTabs.lua`: data-driven tab definitions.
- `FieldFactory.lua`: generated widgets (text/number/dropdown/checkbox/spell-aware).
- `SpellInput.lua`: spell token normalization (name/id -> id) and CSV resolve.
- `Repositories/AuraRepository.lua`: draft <-> SettingsData.
- `Repositories/RuleRepository.lua`: draft <-> ProcRuleEngine rule persistence.
- `Panels/ConfigFrame.lua`, `Panels/AuraListPanel.lua`, `Panels/AuraEditorPanel.lua`, `Panels/GlobalPanel.lua`, `Panels/AuraWizard.lua`.
- `Widgets/RuleBuilderWidget.lua`, `Widgets/ConditionTreeWidget.lua`, `Widgets/PreviewPanelWidget.lua`.

## Current Rule Model
Rules are persisted in `AuraLiteDB.procRules` and compiled by `ProcRuleEngine.lua`.

Supported patterns:
- Produce/Show: cast + optional conditions -> show aura for local duration.
- Consume/Hide: cast + optional conditions -> hide aura.

Important UI behavior:
- Trigger tab has explicit mode selector:
  - `Show / Produce`
  - `Consume / Hide`
- `RuleRepository:SaveRuleFromDraft()` saves one rule using current draft mode.
- `RuleRepository:GetRuleForAuraByMode()` loads produce or consume rule into editor.

## WoW Constraints to Respect
- Aura timing fields can be restricted/secret in combat; avoid hard dependency.
- Use event-driven local timers and deterministic rules.
- Avoid taint sources:
  - no `SecureActionButtonTemplate`
  - no `SetAttribute` action flows
  - no protected frame anchor/show/hide mutations in combat

## Load Order Notes
Keep TOC dependency order valid.
- UI files load after core utility/runtime modules.
- `UI/SpellInput.lua` must load before `UI/FieldFactory.lua`.

## Local Dev Workflow
Deploy:
- `powershell -ExecutionPolicy Bypass -File .\deploy.ps1`

Minimal syntax validation (example):
- `lua -e "assert(loadfile('AuraLite/UI/Panels/AuraEditorPanel.lua'))"`
- `lua -e "assert(loadfile('AuraLite/UI/FieldFactory.lua'))"`

In-game smoke test:
1. `/reload`
2. Open config.
3. Select/create aura with valid spellID.
4. In Trigger tab save one Show rule and one Consume rule.
5. Verify both rules appear in persisted rules area.
6. Test behavior in and out of combat.

## Common Failures and Checks
1) Rule not triggering
- Verify trigger mode selected while editing (produce vs consume).
- Verify cast spellIDs and aura spellID are set.

2) Sound picker issues
- Ensure sound fields in schema use dropdown options provider.
- Verify `SoundManager:GetDropdownOptions(true)` returns data.

3) Spell name inputs unclear
- Use autocomplete suggestions (if available in current branch).
- Ensure SpellCatalog search functions are loaded.

4) UI overlap
- Check fixed heights and scroll child sizing in editor panel/widgets.

## Coding Guidelines
- Prefer data-driven tab schema over hardcoded per-tab logic.
- Keep runtime behavior stable unless explicitly requested.
- Keep UI updates event-driven and lightweight.
- Preserve SavedVariables compatibility.

## Recommended Entry Points for New Agents
1. `AuraLite/AuraLite.toc`
2. `AuraLite/Core.lua`
3. `AuraLite/ProcRuleEngine.lua`
4. `AuraLite/UI/Panels/ConfigFrame.lua`
5. `AuraLite/UI/Panels/AuraEditorPanel.lua`
6. `AuraLite/UI/Repositories/RuleRepository.lua`
