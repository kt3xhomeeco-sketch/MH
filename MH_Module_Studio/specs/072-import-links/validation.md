# Validation — 2026-10-18

- Scoped production gate: 200 Ruby files inspected; no RuboCop offenses.
  374 tests, 4375 assertions, zero failures/errors/skips.
- New native runner also checked separately with scoped RuboCop; no offenses.
- `test/import_template_browser.cjs` passed: five-slot preset, explicit Cánh role,
  per-face gaps, partial template and Save SKP payload.
- Existing `test/list_manual_input_browser.cjs` passed after UI integration.
- `tools/native_import_links_check.rb` executed through VBO in SketchUp PID 2724,
  port 7891. Receipt: `outputs/import-072/native.json`.
  Native fixtures use actual owned component/panel geometry and translated ATT;
  they are test fixtures, not a claim that every source DC has been audited.
  Geometry, definitions, selection and camera were restored; model_retained=true.

Native checks cover real five-face/one-face/two-face picking, read-only hover,
filled host draw invocation, atomic Undo/Redo, current contact gaps, removal and
deletion restoration, maximum shared mounting reservation, explicit Group and
regroup master identity, source independence and assembly SKP persistence.

Independent opposed-door T=20/40/17.6/18.6 mm was checked with a configurable
3 mm mounting gap. The aggregate remained 200 mm deep, host span was exactly
200 - T - 3, and host panel T did not change. Reverting the gap to 1 recomputed
from the original target without cumulative trimming.

For a nested ATT module, host 600 x 200 x 500 with five saved 2 mm inner gaps:

| Host T | Child W x D x H (mm) | State |
|---|---|---|
| 18 | 560 x 100 x 460 | Separate connected modules |
| 20 | 556 x 100 x 456 | Actual transaction observer redraw |
| 17.6 | 560.8 x 100 x 460.8 | Actual observer redraw; then Group |
| 40 | 516 x 100 x 416 | Grouped master edit |
| 18.6 | 558.8 x 100 x 458.8 | Grouped master edit |
| 18.6 | 678.8 x 100 x 558.8 | Native Scale host/group to 720 x 200 x 600 |
| 20 | 676 x 100 x 556 | Saved/reopened assembly |
| 17.6 | 680.8 x 100 x 560.8 | Saved/reopened assembly |

All five gaps, physical T, free child depth, and link verification remained
correct through repeated changes. Editing a reopened assembly left the original
assembly unchanged. Native highlight draw executed without an exception;
viewport image export is not used as pixel proof of overlay colors.

Runtime owners were reloaded through VBO. No existing Studio dialogs were open.
`python tools/package.py` produced `outputs/MH_Module_Studio-0.1.0.rbz`; developer
fixtures, Spec Kit and test tooling are excluded by the runtime manifest.

Limits: matching is for cardinal planar boundaries in the host frame. Missing
surfaces are unbound. Incompatible fixed ATT dimensions still abort atomically;
the importer does not invent a rule that overrides a fixed dimension.
