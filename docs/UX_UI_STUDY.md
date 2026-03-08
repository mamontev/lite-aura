# AuraLite UX/UI Study (Retail 12.x)

## Objective
Design a configuration UI that is:
- easy for first-time users
- fast for experienced users
- modular and maintainable in Lua
- consistent with AuraLite's "visual/audio tracker" scope

## User Profiles
1. New player
- needs a guided flow
- wants to add one aura quickly
- should avoid advanced technical fields by default

2. Intermediate player
- wants to configure groups and low-time alerts
- needs clear visual hierarchy and fewer accidental mistakes

3. Advanced player
- wants full control over texture paths, anchor offsets and sound routing
- accepts denser UI when needed

## Information Architecture
Top-level workflow:
1. `Auras` workspace: pick/create aura
2. `Editor` workspace: configure the selected aura
3. `Split` workspace: list + editor side by side (power-user mode)

Inside editor:
- `General`: spell/unit/group and core conditions
- `Display`: icon/bar and text placement
- `Sounds`: gain/low/expire sound states

## UX Decisions Implemented
- Added custom segmented workspace control (`Auras`, `Editor`, `Split`).
- Added `Guided UI` mode:
  - hides advanced controls by default
  - keeps core setup fields visible
  - reduces cognitive load for non-expert users
- Added dynamic hint text to communicate current workflow and mode.
- Added adaptive panel layout:
  - full-width `Auras` mode
  - full-width `Editor` mode
  - split mode for fast editing
- Added responsive aura-list row width to avoid cramped list entries.

## Component Strategy
Reusable custom components:
- `CreateSection`
- `CreateDropdown`
- `CreateEditBox`
- `CreateSegmentedControl` (new)

This keeps UI code modular and enables easier future restyling.

## Accessibility & Clarity Notes
- Keep labels short and action-oriented.
- Keep default language English with complete Italian support.
- Use guided defaults first, advanced controls on demand.
- Preserve keyboard-friendly behaviors in edit fields and autocomplete.

## Future Iterations
1. Add inline validation states (green/red) for input fields.
2. Add quick templates (Proc, Defensive, Cooldown bar) in guided mode.
3. Add optional onboarding tooltip tour for first run.
