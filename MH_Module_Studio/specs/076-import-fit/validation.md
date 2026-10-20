# Validation — 2026-10-20

- Scoped gate: 210 Ruby files clean; 390 tests / 4454 assertions passed.
- Portable import cases cover interval-first fitting, explicit virtual front,
  real-face priority, signed gaps, inset-door thickness and invalid intervals.
  Assembly-tool tests cover positive HUD/Measurements values, plus/minus, flip
  and leaving the envelope-contact mode without leaking its sign convention.
- `tools/native_import_fit_check.rb` ran on private copies of the actual file-1
  sources `Khung noc lot LC50` (450756) and `Khung ngăn kéo` (453969). Final native
  check used the reopened file-1 session PID 23188 / port 52157. 44 checks passed:
  front/top 80 mm, real/virtual drawing, preview/native agreement, physical T,
  contact edits through HUD/Measurements, Undo/Redo, host T 17.6↔20,
  grouping, SKP round trip, nonuniform Scale, rotated/mirrored and unit frames.
  Results: `outputs/import-076/native.json`, original model retained.
- Real measured imported size at host T=17.6: 828.045 × 511.614 × 790.390 mm,
  front/top offsets 80.000 mm. Changing host T to 20 gives width 823.245 and
  height 785.590 mm, retaining front/top 80 and the original drawer T.
- A positive 70 mm wide target that conflicts with fixed ATT columns fails
  atomically; no extra component, definitions or contacts remain. Error includes
  module, requested real-mm size and the underlying ATT condition.
- Prior import/door native suite: 131 checks passed in the already open second
  session PID 13124. Updated two old assertions to the explicitly approved
  cavity-fit/open-envelope semantics; opposed/inset doors, master T, reservations,
  regrouping, copied assemblies and dependency redraw still pass.
- Browsers: `import_template_browser.cjs` and `assembly_hud_browser.cjs` passed.
- No production source SKP/library files written. Native QA exported only inside
  outputs/import-076 and restored geometry, definitions, materials, links,
  selection and camera. Existing incomplete imported links are not silently
  migrated; import the old item again to acquire its missing front reference.

Runtime RBZ rebuilt and source bytes verified against the manifest. Developer
checks remain outside the package. Final VBO check on file 1: own source PIDs
450756/453969 intact, native QA passed/model_retained=true, no Assembly error.
