# Verification — 2026-10-16

- Scratch native DC `parse_formula` probes on an independently created 700 mm
  block: scalar `LenX/4` returns 17.5 under CENTIMETERS and 6.8897637795 under
  INCHES, for FLOAT/STRING formula units. Scratch operation aborted; source DC
  formulas were not executed. See `outputs/plinth-037/native-unit-probe.json`.
- Portable regression: native plinth fixture baseline, four COPY positions,
  thickness/setback edit, fixed envelope, scalar/literal units, symbolic position
  coefficients, Parametric attribute rows and editable X expression.
- Scoped gate: 104 Ruby files without RuboCop offenses; 218 tests /2524 assertions,
  no failures/errors/skips. Manifest unchanged: formula policy has one owner.
- Native original Untitled PID 9504, VBO 7891, source PID 664420. Conversion now
  exports 10 parts and six editable parameters. Native reimport has a Component
  parent/Group children and T1 board symbol. All six parameters edited, fixed
  envelope/idempotence checked, one Undo restores, invalid thickness rolls back,
  two repeated Scale redraws retain thickness and valid leg spacing. 13 checks.
- Full previous assembly/import/HUD native regression: 102 checks passed;
  selected original plinth recursive geometry/attribute fingerprint unchanged.
- Library compatibility audit: 95 actual SKPs imported in aborted operations;
  94 pass formula-baseline checks. Existing `2. Đợt di động.skp` fails its saved
  geometry/payload check identically under previous and updated formula policy;
  independently confirmed pre-existing in `audit-comparison.json`. That existing
  asset was left unchanged. No other import regression observed.
- Full conversion report updated with backups, 95 converted/132 unsupported out
  of 227. SHA-256 of all 227 original DC files remains unchanged.
- Packaged the explicit runtime manifest with ZIP verification. Hot reloaded
  `formulas.rb` in the existing VBO session and refreshed the actual active
  Library: 95 entries, `3.CC Chân bệ.skp` present, published file hash matches
  the native-tested export. Source/model fingerprint retained (`reload.json`).

The six editable parameters exclude dynamic copy-count/topology changes. Changing
the number of support legs is still guarded; this fix concerns existing copies'
formula positions and does not implement generation/removal of native copies.
