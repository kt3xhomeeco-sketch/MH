# Verification — 2026-10-20

- Scoped RuboCop: 216 Ruby files, no offenses. Full Ruby suite: 400 tests,
  4497 assertions, zero failures/errors/skips.
- Five headless browser checks passed: module options (including batch action
  visibility), redraw options, manual LIST input, assembly settings, import template.
- Actual SketchUp file `1`, PID 23188: 22 native checks passed using temporary
  copies of real cabinet/drawer library SKPs. Shared T1 without thickness-role
  metadata edits both roots; Undo/Redo and injected second-member failure rollback
  retain both modules. Shift raw placement retains physical size/no contacts.
- Five-face placement preserves source height when top is disabled. Front uses
  the host envelope despite its upper brace; actual offset is 80 mm. No-template
  placement remains original size.
- Five native contact dimensions render; the nonzero front box uses the smaller
  face area. Actual tool dimension click changes 80 to 90 mm; box click opens
  settings, closing it keeps the overlay. Switching to native tools does not
  leave the old mouse hook active. Native PrintWindow screenshot visually checked
  the 80 mm prism/dimensions in outputs/direct-links-077/native-screen.png.
- Receipt: outputs/direct-links-077/native.json, status=passed,
  model_retained=true. Source SKPs untouched; temporary roots/definitions/materials
  removed, saved links/selection/camera restored. QA operations create Undo history.
- Portable regressions additionally cover click-time modifiers, copied wrappers
  sharing child IDs, mixed values, incompatible units, zero/oblique contacts and
  dimension hit priority. Native repeated-wrapper batch edits are not separately
  claimed by this receipt.
