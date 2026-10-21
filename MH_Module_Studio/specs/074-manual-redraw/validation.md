# Validation — 2026-10-20

- Native VBO initially checked file `1`, PID 14572. Final checks used a private
  temporary copy of `Library/Khung/Khung noc lot.skp` in the already open model
  on PID 13124 / port 7891; did not open a different user model or write source SKP.
- `tools/native_manual_redraw_check.rb`: 18 checks passed after the combined rebuild
  change: button/token, registered command, repeated redraw, single Undo/Redo,
  shared linked assembly independence, retained 3 mm contact, atomic failure.
  `outputs/redraw-074/native.json`, `fixture-final.json`: original entities,
  definitions, materials, selection and source geometry retained.
- `tools/native_redraw_abort_check.rb`: 16 checks passed again on the temporary
  source: repeated Scale, commit/abort notifications, cancel, Undo/Redo, sibling.
- Phase profiling on the earlier open real module: total measured work ~649→485 ms;
  metadata stamp ~233→19 ms; geometry verification retained. Different runs and
  load affect timing; this is not a universal speed guarantee.
- Final temporary-source timings: unchanged Options refresh 49–58 ms, button
  587 ms, shortcut 537 ms, correct-module redraw 527 ms, two-member copied assembly
  3067 ms (previous double-preparation run 3614 ms). Group calculation remains costly.
- Browser: `redraw_options_browser.cjs`, `module_options_browser.cjs`,
  `list_manual_input_browser.cjs` passed; compact sizing, pending inputs, error,
  stale-safe payload and selection switching retained.

- Scoped final gate: 209 Ruby files clean; 385 tests / 4429 assertions passed.
  Runtime RBZ rebuilt from the explicit manifest; active SketchUp backend reloaded via VBO.
