# AuraLite

AuraLite is a lightweight WoW Retail aura tracker focused on fast setup, clean visuals, cast-driven timers, and a workflow familiar to WeakAuras users without the overhead of a fully open-ended scripting environment.

The addon is currently in active beta refinement.

## Highlights

- Modern in-game editor with:
  - aura library
  - guided configuration flow
  - live preview
- Standalone auras and grouped auras
- Group movers with shared layout and ordering
- Icon, bar, and icon+bar display modes
- Per-aura appearance controls
- Import/export for single auras and groups
- Synthetic proc/consume rules
- Stackable aura logic
- Reapply timer policies, including extend-to-cap
- Local audio presets bundled with the addon

## Current UI Flow

- Left panel:
  - aura library
  - search
  - grouped and ungrouped organization
- Center panel:
  - `Tracking`
  - `Appearance`
  - `More Options`
- Right panel:
  - `Live Preview`

Additional tools:
- `Groups` panel for shared group layout and movers
- `Global` panel for import and utility actions

## Features

### Tracking

- Track buffs, debuffs, procs, and cast-driven synthetic auras
- Confirmed and estimated tracking paths
- Rule-based `show/produce` and `consume/hide`
- Multi-spell triggers
- Talent/resource/condition support

### Appearance

- Icon size
- Bar width and height
- Timer visibility
- Bar color
- Bar texture picker
- Icon position relative to bar
- Layout presets for quick setup

### Groups

- Shared mover per group
- Shared direction, spacing, sort, wrap, and offsets
- Export group directly from the group header in the aura library
- Delete group container without deleting member auras

### Import / Export

- Export single aura from the editor
- Export group from:
  - the `Groups` panel
  - the group header in the aura library
- Import from a unified import panel
- Payload type autodetection (`aura` or `group`)

### Audio

Bundled addon-local sounds:

- `AuraLite/Media/Sounds/soft_ping.wav`
- `AuraLite/Media/Sounds/bright_chime.wav`
- `AuraLite/Media/Sounds/urgent_alarm.wav`

Custom file paths are also supported via:

`file:Interface\\AddOns\\AuraLite\\Media\\Sounds\\your_file.wav`

## Slash Commands

- `/al`
- `/al ui`
- `/al config`
  Opens or toggles the modern editor.

- `/al debug`
- `/al debug on|off|verbose`
  Controls debug logging.

- `/al examples warrior`
  Installs or refreshes bundled warrior example auras for testing.

Legacy slash handling still exists as fallback for older flows, but the modern V2 editor is the primary path.

## Project Structure

- [F:\testAddon\AuraLite\Core.lua](F:\testAddon\AuraLite\Core.lua)
  Addon bootstrap, slash routing, startup banner, event registration.
- [F:\testAddon\AuraLite\EventRouter.lua](F:\testAddon\AuraLite\EventRouter.lua)
  Runtime event processing, aura state rebuild, preview/runtime orchestration.
- [F:\testAddon\AuraLite\TrackerGroupManager.lua](F:\testAddon\AuraLite\TrackerGroupManager.lua)
  Runtime frame creation, group containers, layout, rendering.
- [F:\testAddon\AuraLite\SettingsData.lua](F:\testAddon\AuraLite\SettingsData.lua)
  Data model, CRUD, identity, group config, migrations.
- [F:\testAddon\AuraLite\ProcRuleEngine.lua](F:\testAddon\AuraLite\ProcRuleEngine.lua)
  Synthetic aura logic, consume rules, stack and reapply behavior.
- [F:\testAddon\AuraLite\ImportExport.lua](F:\testAddon\AuraLite\ImportExport.lua)
  Aura and group serialization/import logic.
- [F:\testAddon\AuraLite\UI\Panels\ConfigFrame.lua](F:\testAddon\AuraLite\UI\Panels\ConfigFrame.lua)
  Main editor shell.
- [F:\testAddon\AuraLite\UI\Panels\AuraEditorPanel.lua](F:\testAddon\AuraLite\UI\Panels\AuraEditorPanel.lua)
  Main aura editor.
- [F:\testAddon\AuraLite\UI\Panels\AuraListPanel.lua](F:\testAddon\AuraLite\UI\Panels\AuraListPanel.lua)
  Aura library and group headers.
- [F:\testAddon\AuraLite\UI\Panels\GroupsPanel.lua](F:\testAddon\AuraLite\UI\Panels\GroupsPanel.lua)
  Group management UI.

## Tests

Run the Lua test suite:

`powershell -ExecutionPolicy Bypass -File .\run-tests.ps1`

Run the beta readiness gate:

`powershell -ExecutionPolicy Bypass -File .\run-beta-gate.ps1`

The suite currently covers:

- stable aura identity (`instanceUID`) on create/update/rebuild
- position persistence and fallback state
- group create/move/delete/reorder behavior
- proc rule behavior:
  - stack
  - decrement consume
  - extend-to-cap
  - expiry
- aura/group import-export round trips
- release gate regression checks

The beta gate also checks:

- syntax of addon Lua files
- debug hygiene
- overall `GO / NO-GO` readiness

Latest expected outcome:

- `14 passed, 0 failed`
- `BETA READY: YES`

## Packaging

Create a local beta zip:

`powershell -ExecutionPolicy Bypass -File .\package.ps1 -Channel beta -Label beta1`

The package is written to `dist/` and contains `AuraLite/` as the zip root.

Release helpers:

- [F:\testAddon\docs\BETA_RELEASE_CHECKLIST.md](F:\testAddon\docs\BETA_RELEASE_CHECKLIST.md)
- [F:\testAddon\docs\RELEASE_TEXT_BETA.md](F:\testAddon\docs\RELEASE_TEXT_BETA.md)
- [F:\testAddon\.pkgmeta](F:\testAddon\.pkgmeta)

Current safe beta package example:

- [F:\testAddon\dist\AuraLite-0.1.0-beta-beta1-safe.zip](F:\testAddon\dist\AuraLite-0.1.0-beta-beta1-safe.zip)

## Media and Licensing Notes

The distributed addon package now includes only AuraLite-local bundled media and project dependencies needed for functionality.

No imported WeakAuras sound pack assets are included in the release package.

If you publish on CurseForge and want a conservative default, use:

- License: `All Rights Reserved`
- Distribution: disable third-party redistribution

## Documentation

- [F:\testAddon\docs\UX_UI_STUDY.md](F:\testAddon\docs\UX_UI_STUDY.md)
- [F:\testAddon\docs\AuraLite_Audit_and_Roadmap.md](F:\testAddon\docs\AuraLite_Audit_and_Roadmap.md)
- [F:\testAddon\docs\ui-ux-refactor-spec.md](F:\testAddon\docs\ui-ux-refactor-spec.md)

