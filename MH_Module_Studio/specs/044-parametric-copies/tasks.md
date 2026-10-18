# Verification

- [x] Capture the selected owned Chân bệ and verify its explicit count/spacing ATT.
- [x] Separate portable family/planning from native geometry mutation.
- [x] Upgrade count editability without rewriting original source SKPs.
- [x] Real native count changes 5 → 7 → 3 → 8 → 5 → 2 → 5, stable further editing.
- [x] Count + thickness edits, Scale, and actual Module Options change callbacks.
- [x] Real SKP save/read roundtrip at changed count and size in outputs only.
- [x] Asynchronous Undo/Redo of additions and deletions preserves part IDs.
- [x] Decode/serve numeric LIST metadata in both windows, preserving labels.
- [x] Browser integer count entry, dropdown dispatch, focus acknowledgement and
  disabled controls; existing grouped Module Options smoke.
- [x] Final full scoped gate, package and VBO reload of both visible windows,
  preserving current draft state and model geometry/selection.

Explicit limits: leaf families only, no new rotations, no arbitrary user-added
Copies variable target inference; dynamic topology with custom geometric
overrides remains guarded. Dropdown presence does not prove every geometry/
rotation branch is supported; those rows retain their diagnostics and locks.

Evidence: outputs/native-copies-044.json (28 native checks, including Group and
Component leaf cloning, actual Options callbacks and changed-count SKP roundtrip),
outputs/copies-undo-044.json (12 checks, stable IDs through Undo/Redo),
outputs/reload-final-044.json (both actual dialogs refreshed, nine LIST rows in
the user's current module, model retained). Browser dc_inputs_browser.cjs and
module_options_browser.cjs pass. RBZ rebuilt at outputs/MH_Module_Studio-0.1.0.rbz.
No original source SKPs or original source object geometry were rewritten.

Final gate: 273 tests / 3,037 assertions, zero failures; 131 Ruby files clean in
the scoped RuboCop gate. Live CEF DOM verification confirms nine actual LIST
dropdowns in Parametric and two matching exposed dropdowns in Module Options
(actual-parametric-ui-044.json / actual-options-ui-044.json). Legacy programs
without visibility metadata can upgrade numeric copy controls without relaxing
their hidden-state guards.
