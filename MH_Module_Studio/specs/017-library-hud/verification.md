# Verification

- Scoped RuboCop + Ruby: 137 tests / 1,640 assertions; no failures/errors/skips.
- Chromium: ui_smoke, rules_ui_smoke, parametric_window_smoke,
  module_options_smoke and library_ui_smoke passed. Picker acknowledgement,
  thumbnail sizes/grid/list, tree/filter, escaping, viewport fit and Studio
  preservation checked. Production has no Electron dependency.
- Native VBO PID26424: native-library-017.json verifies portable SKP rules/current
  values/visibility, component parent/group panels, private copies, edit, Undo,
  Redo, actual image textures, ghost edges, key callbacks, cleanup/source retained.
- Native-coordinate-geometry-017.json: 8-panel captured DC with nonzero local
  panel origin; combined thickness/back/setback/rail-height changes, repeat edit,
  Undo/Redo, export and removal of QA geometry passed.
- Native-coordinate-import-017.json: the edited coordinate module imports twice,
  retains values and visibility, edits independently and keeps its ATT state.
- coordinate_native_ui_017.json: actual SketchUp CEF shows 12 editable ATT and
  numeric/ƒ X/Y/Z cells, no pending request/dirty editor/parametric diagnostic.
- library_native_ui_017.json: actual CEF Library/HUD controls present, Studio
  state retained, no pending request or horizontal overflow.
- Ruby reloaded through VBO in module session26424 and working session12360;
  no user model save or source-DC writes. Existing editor backup retained.
- Physical keyboard QA remains manual: multiple SketchUp processes were active;
  the guard refused keystrokes when the intended process did not hold focus. No
  shortcut preferences were changed and no global hooks installed.

Manual check: assign the Extensions HUD command in Shortcuts, open HUD in the
intended model, type a normally assigned letter (e.g. B/R), verify search keeps
the HUD active, select/place a module, repeat the letter, then Esc and Space in
separate sessions. After exit the original SketchUp shortcut should work.
