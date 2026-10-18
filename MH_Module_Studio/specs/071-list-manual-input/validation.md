# Actual verification

- Scoped RuboCop: 196 Ruby files clean.
- Full suite: 368 tests / 4311 assertions, zero failures/errors/skips. The five
  new tests cover the captured drawer source, arbitrary depth, preset/manual
  switching, symbol rename, JSON round trip, hidden inline input, member IDs,
  duplicate suppression, initially selected native ATT and rejected references.
- Headless Chrome with actual generated state: both Parametric and compact
  Options pass. Preset/manual selection, unlocked source field, correct request
  values, stable acknowledgement nodes and 320 px layout verified. Existing
  grouped Options and Copies/LIST browser regressions also pass.
- Native SketchUp PID 17900: the real `1.QQ Ngan keo 1 tang 250.skp` compiled on
  a private copy. Actual ModuleOptions requests tested manual 290 → 473.25,
  preset 450 → manual 473.25, second edit 487.5 and Undo to 473.25. Exported
  private SKP reopened with its formula and accepted another 496.75 mm edit.
  Native geometry, source SHA-256, original entities/definitions/selection were
  verified; temporary objects were removed. Evidence: `outputs/list-071/native.json`.
- Browser evidence/state and a private test SKP are under `outputs/list-071`.
  No DC source or user library SKP was rewritten for this fix.
- Packaged and CRC/manifest-verified the RBZ; reloaded through VBO in PID 17900.
  Both affected dialogs were closed, so no visible draft was reset. Model and
  selection retained; evidence in `outputs/list-071/reload.json`.

Supported expression scope is direct root numeric TEXTBOX reference, such as
`=hsxpei34m2`, with matching units. Other expression kinds remain disabled.
Member routing was checked portably; this test did not create a native linked
assembly or assert every possible drawer parameter combination.
