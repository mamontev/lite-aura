# AuraLite UI/UX Refactor Spec

## Goal

Refactor AuraLite's UI so it becomes:

- easier to learn for first-time users
- faster to operate for experienced users
- clearer about what is real state vs preview/draft state
- more visually consistent across all clickable components
- easier to maintain through a real component system instead of ad hoc styling

This spec is intentionally practical. It is designed to guide implementation, not just describe UX theory.

## External Principles Used

This plan is based on a mix of general UX heuristics and game-specific UI guidance:

- Nielsen Norman Group usability heuristics:
  - visibility of system status
  - recognition rather than recall
  - aesthetic and minimalist design
  - consistency and standards
  - error prevention
- Microsoft game UX and accessibility guidance:
  - clear context in menus
  - linear navigation and understandable hierarchy
  - readable, low-friction interaction under interrupted attention
- Game accessibility guidance:
  - simple menu structure
  - clear visual distinction between interactive elements
  - minimized ambiguity in controls and menu categories

Reference links:

- https://www.nngroup.com/articles/ten-usability-heuristics/
- https://learn.microsoft.com/en-us/gaming/gdk/_content/gc/system/overviews/game-ux-guidelines
- https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/114
- https://learn.microsoft.com/en-us/gaming/accessibility/xbox-accessibility-guidelines/101
- https://gameaccessibilityguidelines.com/

## Current UI Audit

### Strengths

- The current editor already has a strong left / center / right structure.
- The live preview path is now much better than before.
- The system already distinguishes confirmed target read vs estimated target debuff.
- The visual language is improving and is no longer pure Blizzard default UI.

### Main Problems

#### 1. The editor is still schema-driven instead of task-driven

The current editor still renders generic field lists and filters them based on context.

Impact:

- users see fields because the schema contains them, not because the current task needs them
- behavior is harder to scan quickly
- it is easy for the UI to feel "form-heavy"

Primary files:

- `AuraLite/UI/Panels/AuraEditorPanel.lua`
- `AuraLite/UI/Schemas/EditorTabs.lua`

#### 2. Preview state is helpful but not explicit enough

The selected aura is now previewed live, but the user is not clearly told:

- this is a draft preview
- these changes are not yet saved
- this placeholder is intentionally simulated

Impact:

- possible confusion between actual combat/runtime data and editor preview

Primary files:

- `AuraLite/UI/Panels/AuraEditorPanel.lua`
- `AuraLite/UI/Widgets/PreviewPanelWidget.lua`
- `AuraLite/EventRouter.lua`

#### 3. Clickable controls are closer stylistically, but still not a true system

Buttons, tabs, segmented toggles, dropdown triggers, list rows, checkboxes and swatches are still implemented as nearby cousins rather than distinct component families.

Impact:

- small alignment/style regressions keep reappearing
- controls do not always communicate their role clearly
- maintenance cost stays high

Primary files:

- `AuraLite/UISkin.lua`
- `AuraLite/UI/FieldFactory.lua`

#### 4. Information hierarchy is not yet sharp enough

The editor footer, top controls, preview area, and display controls are all better than before, but the most important choices are not always the most visually obvious.

Impact:

- users need extra scanning time
- the UI still leans too much on reading labels instead of quickly recognizing structure

Primary files:

- `AuraLite/UI/Panels/ConfigFrame.lua`
- `AuraLite/UI/Panels/AuraEditorPanel.lua`
- `AuraLite/UI/Panels/AuraListPanel.lua`

## Target Experience

The ideal flow should feel like this:

1. Select an aura.
2. Immediately see a visible live draft preview.
3. Adjust behavior in a small set of guided controls.
4. Adjust appearance in a focused panel that feels like a layout tool, not a raw config form.
5. Save with high confidence because the UI clearly shows what changed and what is still draft-only.

## Product Decisions

### Decision 1. Reduce the editor to 3 primary sections

Replace the current mental model of many tabs with:

- `Tracking`
- `Appearance`
- `Advanced`

Rules and conditions should appear only when relevant, and mostly inside `Advanced`.

Reason:

- matches progressive disclosure
- reduces first-use intimidation
- keeps power available without front-loading complexity

### Decision 2. Make preview state explicit everywhere

Whenever an aura is selected:

- show a `Live Draft Preview` banner in the editor header
- show whether the draft is saved or dirty
- label preview-rendered items as preview, not runtime truth

Suggested language:

- `Previewing selected aura`
- `Live draft preview`
- `Unsaved appearance changes`

### Decision 3. Separate clickable controls into families

We should define these families:

- `Action Button`
  - examples: Save, Delete, Quick New Aura
- `Navigation Tab`
  - examples: Tracking, Appearance, Advanced
- `Segmented Toggle`
  - examples: Confirmed vs Estimated, Produce vs Consume
- `Dropdown Trigger`
  - examples: Display Mode, Icon Position
- `Selectable List Row`
  - examples: aura list rows, autocomplete rows
- `Checkbox`
  - examples: Show Timer Text, In Combat Only
- `Color Swatch`
  - example: Bar Color

Each family should have:

- clear visual identity
- consistent hit area
- consistent spacing
- explicit selected/hover/pressed states

## Target Information Architecture

### Main Frame

#### Left Panel

Purpose:

- find and select an aura

Contents:

- search
- grouped aura list
- optional quick filter chips later

#### Center Panel

Purpose:

- edit selected aura

Contents:

- selected aura banner
- top-level section navigation
- task-oriented content
- footer with save actions

#### Right Panel

Purpose:

- show preview and contextual explanation

Contents:

- live preview card
- selected aura summary
- mode explanation
- optional test actions later

## Center Panel Structure

### Header Block

Should contain:

- aura name
- spellID
- tracking type
- group
- preview status
- dirty/saved status

Example:

`Rend`
`Target | Estimated from your cast | Group: target_debuffs`
`Live draft preview | Unsaved changes`

### Section Navigation

Use 3 pills/tabs:

- Tracking
- Appearance
- Advanced

Do not show conditions/actions as top-level siblings by default.

### Tracking Section

This must be the guided behavior editor.

#### For target auras

Use a segmented toggle:

- `Read Live Aura`
- `Estimate From My Cast`

Then show only the relevant controls.

#### For player rule-based auras

Show a simpler rule setup:

- aura spell
- trigger spell(s)
- optional produce/consume segmented toggle

### Appearance Section

This should stop looking like a generic form.

Use cards:

- `Layout`
- `Icon`
- `Bar`
- `Text`

#### Layout card

- display mode
- icon position
- group

#### Icon card

- width
- height
- icon source

#### Bar card

- width
- height
- texture
- color
- show timer text

#### Text card

- custom text
- anchor
- offsets

Only render the cards relevant to the selected display mode.

### Advanced Section

Keep more technical settings here:

- conditions
- load restrictions
- debug
- notes
- persisted rule details

## Visual System

### Spacing Scale

Adopt a fixed spacing system:

- 4
- 8
- 12
- 16
- 24

Use these consistently for:

- vertical rhythm between fields
- section padding
- footer/header spacing
- control groups

### Typography Hierarchy

Three consistent levels:

- title
- section label
- helper/status text

Avoid overusing the same WoW font style for all levels.

### Palette Direction

Keep the current cool, restrained, dark-blue family, but avoid:

- hot highlight glows
- yellow-selected text as a primary selected state
- overly saturated accents for neutral navigation

Recommended semantics:

- primary action: calm bright blue-cyan
- neutral action: slate / steel
- danger: muted red only where destructive
- selected nav: slightly brighter slate-blue, not gold

## Component Refactor Plan

### Phase 1. Establish component primitives

Create or normalize these APIs in `UISkin.lua` and/or dedicated UI component files:

- `ApplyActionButton(button, variant)`
- `ApplyNavTab(button, selected)`
- `ApplySegmentedToggle(button, selected, side)`
- `ApplyDropdown(frame)`
- `ApplyCheckbox(check)`
- `ApplyColorSwatch(button, color)`
- `ApplySelectableRow(row, state, variant)`
- `ApplyCloseButton(button)`

Goal:

- eliminate ad hoc per-panel visual tweaks

### Phase 2. Extract field controls from `FieldFactory.lua`

Move complex widgets into dedicated constructors:

- `CreateStyledDropdownField`
- `CreateNumberStepperField`
- `CreateColorField`
- `CreateCheckboxField`
- `CreateSpellField`

Goal:

- reduce fragility
- make alignment and behavior easier to fix centrally

### Phase 3. Refactor editor IA

Replace the current generic-tab filtering model with an explicit task layout:

- `RenderTrackingSection()`
- `RenderAppearanceSection()`
- `RenderAdvancedSection()`

Keep schema data only where it still adds value.

Goal:

- easier reasoning
- better UX copy
- less scattered conditional logic

### Phase 4. Add explicit preview status

Add a banner component near the editor header:

- preview badge
- dirty/saved indicator
- short helper text

Goal:

- visibility of system status

### Phase 5. Improve list and preview clarity

For the aura list:

- stronger selected state
- better meta line hierarchy
- optional preview badge for selected live draft

For preview panel:

- reflect selected aura state clearly
- show `Preview` vs `Live Combat` semantics

## Engineering Plan

### Milestone A. Design System Foundation

Files:

- `AuraLite/UISkin.lua`
- `AuraLite/UI/FieldFactory.lua`
- `AuraLite/UIComponents.lua`

Deliverables:

- explicit clickable control families
- shared spacing constants
- cleaned dropdown/checkbox/swatch/button implementations

Acceptance criteria:

- no control family depends on `UIPanelButtonTemplate` visuals showing through
- dropdown trigger, checkbox, and swatch all look intentional and aligned

### Milestone B. Editor Information Architecture

Files:

- `AuraLite/UI/Panels/AuraEditorPanel.lua`
- `AuraLite/UI/Schemas/EditorTabs.lua`

Deliverables:

- 3-section editor
- guided tracking section
- card-based appearance section
- advanced section containing technical depth

Acceptance criteria:

- a first-time user can configure common target/player auras without entering Advanced

### Milestone C. Preview Clarity

Files:

- `AuraLite/UI/Panels/AuraEditorPanel.lua`
- `AuraLite/UI/Widgets/PreviewPanelWidget.lua`
- `AuraLite/EventRouter.lua`

Deliverables:

- explicit preview banner
- clear labeling of live draft preview
- consistent selected aura preview behavior

Acceptance criteria:

- selected aura always appears in preview
- draft-only changes are visually marked as preview

### Milestone D. List and Navigation Polish

Files:

- `AuraLite/UI/Panels/AuraListPanel.lua`
- `AuraLite/UI/Panels/ConfigFrame.lua`
- `AuraLite/UI/Panels/AuraWizard.lua`

Deliverables:

- stronger hierarchy in list rows
- clearer top controls
- better relationship between selection and editing

Acceptance criteria:

- the most important action in each panel is visually dominant
- current selection is obvious at a glance

## UX-Specific Acceptance Checklist

### Learnability

- New users can create a basic aura without reading technical labels.
- The UI explains estimated vs confirmed tracking clearly.

### Clarity

- The user can always tell which aura is selected.
- The user can always tell if they are seeing preview state or saved/runtime behavior.

### Efficiency

- Common appearance changes can be made without saving repeatedly.
- High-frequency controls are visually grouped and easy to reach.

### Consistency

- All clickable controls share a coherent visual language.
- All controls of the same type behave and align consistently.

### Safety

- Destructive actions remain visually distinct.
- Draft changes remain clearly unsaved until persisted.

## Recommended Execution Order

1. Design system refactor in `UISkin.lua` and `FieldFactory.lua`
2. Explicit preview banner and preview semantics
3. Editor restructure into Tracking / Appearance / Advanced
4. Appearance card layout
5. List and preview polish
6. Final copy, spacing, and visual tuning pass

## Immediate Next Build

If we follow this spec, the best next implementation step is:

### Build 1

- add a top `Live Draft Preview` status block
- convert the current top tabs into:
  - `Tracking`
  - `Appearance`
  - `Advanced`
- move existing display fields into an `Appearance` card layout

This gives the biggest UX improvement for the least architectural risk.
