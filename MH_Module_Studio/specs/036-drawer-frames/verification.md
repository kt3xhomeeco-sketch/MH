# Verification — 2026-10-16

- `bundle exec ruby tools/check.rb`: 102 Ruby files, no RuboCop offenses;
  214 tests / 2496 assertions, zero failures/errors/skips.
- Native existing SketchUp 2025 PID 9504, VBO port 7891, Untitled. The other
  SketchUp project/process was not used. No SketchUp process was launched.
- `outputs/drawer-036/native.json`: selected 550 drawer reimported as component
  parent/groups, nine sequential parameter edits, preserved rail-symbol vertices,
  fixed envelope, Undo, invalid-value rollback and two consecutive Scale redraws.
  Rail clearance 13.5 mm stays separate from board T2. Original DC and SKP intact.
- `reimport.json`: 25/25 newly converted actual SKP files imported and edited in
  aborted native operations. No-op rules idempotent, envelopes preserved, output
  hashes and original entities/definitions/selection unchanged.
- `regression-native.json`: all 102 native checks passed for assembly contact,
  automatic fit, component ownership/copy independence, options, import/replace,
  Esc lifecycle, persistent HUD, Undo and cleanup. Original selected drawer also
  retained the same recursive geometry/attribute fingerprint.
- Conversion results merged into the full `.conversion/report.json`, with
  backup JSON/CSV/Markdown retained: 94 converted, 133 still unsupported, total
  227. All 227 original source SHA-256 hashes verified unchanged. Drawer subset
  gained 25 conversions; four remaining failures retain specific diagnostics.
- Evidence/scripts/fixtures are developer-only. Production additions are listed
  explicitly in `runtime_manifest.json`; no imported Ruby functions are executed.
- Built `outputs/MH_Module_Studio-0.1.0.rbz` with manifest/ZIP verification.
  `reload.json`: 12 changed calculation/adapter files hot reloaded through VBO
  in the same PID 9504. Both the destination scan and actual active Library show
  94 entries, including the 550 sample. Reading its original DC yields 16 parts
  and zero baseline changes; model geometry and source hash remain unchanged.

Limits: arbitrary rotations, topology/hidden-state changes and malformed/stale
formulas remain guarded. This adds planar auxiliaries and rigid non-box movement,
not general non-box deformation. Scale/Undo was tested repeatedly on the selected
550 sample; all 25 received native import/thickness tests, not exhaustive testing
of every parameter combination or every SKU's Scale range.
