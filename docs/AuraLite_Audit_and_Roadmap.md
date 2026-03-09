# AuraLite Audit, UX/UI Plan, and API-Safe Roadmap (Retail 12.x / Midnight)

Date: 2026-03-08

## 1) Current Functional Audit

### What works well today
- Event-driven runtime core instead of continuous aura timing dependence.
- Synthetic proc/consume state for deterministic trackers.
- Rules-only mode for combat-safe behavior.
- Cooldown restriction detection and fallback handling.
- Split UI modules (`SettingsUI`, `SettingsUI.Rules`, `SettingsUI.Auras`) with reusable components.
- Sound routing via presets + custom files + LibSharedMedia.

### Current weaknesses
- Rule Builder usability still technical for non-expert users.
- Multiple layout edge-cases under dynamic resize/workspace switching.
- Debug signal quality is good but can still be noisy if enabled globally.
- Rule validation can be more proactive (e.g. empty cast IDs, missing aura in rule).

## 2) API Constraints (Retail 12.x) and Design Implications

### Constraints
- Aura fields can be secret/restricted in combat context.
- Cooldown APIs can return hidden values when restrictions are active.
- Protected function contamination (taint) causes Blizzard blocked-action popup.

### Design implications
- Never rely on aura duration/expiration as single source of truth in combat.
- Use cast-attempt confirmation + local timers for stable behavior.
- Keep UI frames passive and non-secure; no protected action paths.

## 3) WeakAuras Migration Matrix (Safe vs Unsafe)

### Safe to migrate
- Trigger/Condition/Action mental model.
- Presets/templates for common aura patterns.
- Icon + side bar display presets.
- Shared media catalogs (sounds/statusbars/fonts).
- Guided workflow and validation hints.

### Not safe / out of scope
- Secure/protected interactions.
- Rotation helper recommendations.
- Deep internals that rely on unrestricted live aura timing.

## 4) UX/UI Redesign Principles

- Guided first: defaults that produce a working rule quickly.
- Progressive disclosure: advanced controls only when needed.
- One clear path: Select Aura -> Build Rule -> Display/Audio -> Save -> Test.
- Contextual feedback: health badge + warnings when setup is incomplete.
- Stable geometry: deterministic anchors and responsive relayouts.

## 5) Implementation Roadmap

### Phase A (done/ongoing)
- Rule panel relayout foundation.
- Workspace segmentation and guided mode.
- Rules-only mode as default safety path.

### Phase B (next)
- Clause builder with explicit AND/OR blocks and reusable condition chips.
- Rule template library (proc, consume, cooldown tracker, defensive window).
- Inline field validation + actionability messages.

### Phase C
- Import/export for rule packs.
- Profile-aware template suggestions per class/spec.
- Performance pass on redraw, debounced UI refresh, and list virtualization if needed.

## 6) Performance Targets

- Keep render/layout separation (`RenderLayout` vs visual updates).
- Avoid full list rebuilds on every tick.
- Debounce expensive UI refresh while typing.
- Keep ticker frequency bounded and only active when needed.

## 7) Taint Safety Checklist (enforced)

- No `SecureActionButtonTemplate`.
- No `SetAttribute` in runtime paths.
- No click-casting handlers for protected actions.
- No parenting/custom manipulation of protected Blizzard descendants.
- Use taint log for root-cause if popup reappears:
  - `/console taintLog 2`
  - inspect `_retail_/Logs/taint.log`.

## 8) Acceptance Criteria

- No Blizzard blocked-action popup during normal usage.
- Rules trigger and consume reliably in combat for deterministic cases.
- UI remains readable in split/editor modes with no overlap.
- New users can create a rule in under 60 seconds via guided flow.
