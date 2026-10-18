# Tasks

- [x] T001 Specify one module with all settings and combined trial behavior.
- [x] T002 Implement aggregate learning, validation and combined geometry plans.
- [x] T003 Retain all rules in project and trial metadata.
- [x] T004 Add unified parameter tables and target-map interaction.
- [x] T005 Run regression, quality and UI checks.
- [x] T006 Reload the correct SketchUp model and verify native preview/UI.
- [x] T007 Refresh RBZ and record validation limits.
- [x] T008 Add untitled export/edit checkboxes, persist selection in project and
  trial metadata, reject unchecked edits and retain explicit missing-rule status.

Checkbox validation: 68 Ruby tests / 403 assertions and 33 UI checks passed.
Empty selections, legacy defaults, project round-trip, trial public-field metadata,
read-only states and request payloads are covered. No source model edit was
required for this UI/configuration change.

Validation: 63 Ruby tests / 380 assertions and 26 UI checks passed. SketchUp PID
8120 learned one aggregate with 27 captured settings and two editable thickness
rules. Native preview at carcass 18 / back 9 mm produced top/bottom 564 x 173 x
18 mm and retained the 600 x 200 x 500 mm envelope. Native trial creation and
combined update were verified, and trial metadata retained both rules. Source
geometry/DC attributes were unchanged; the test copy and its private definitions
were removed. Undo was not verified: Sketchup.undo calls through the MCP bridge
had no effect in this session. No Undo success is claimed.
