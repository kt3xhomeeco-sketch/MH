# Tasks: DC parameter learning

- [x] T001 Specify observed three-state behavior and fixed-control requirements.
- [x] T002 Map DC thickness inputs and units to observed panels in Core.
- [x] T003 Select controlled sample groups; store and validate fixed context.
- [x] T004 Wire parameter selection and evidence into Panel and UI.
- [x] T005 Add regression and UI tests; run the scoped quality gate.
- [x] T006 Reload the correct SketchUp instance and verify both rules/read-only previews.
- [x] T007 Refresh RBZ and document remaining limitations.

Evidence: 51 Ruby tests / 255 assertions passed; 20 UI checks passed. Actual
SketchUp PID 8120 learned back from states 2–3 and carcass from states 1–2.
Read-only back preview at 9 mm produced top/bottom depth 173 mm, preserved
carcass thickness 17.6 mm and envelope 600 x 200 x 500 mm. Native clone/Undo
was not exercised in this feature validation.
