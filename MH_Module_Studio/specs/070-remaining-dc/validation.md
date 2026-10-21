# Validation and remaining work

- Full scoped gate: 195 Ruby files clean; 363 tests / 4283 assertions, zero
  failures/errors/skips. Includes unchanged legacy import-recovery and drawer
  frame regressions alongside the new construction/inactive geometry fixtures.
- Previously passing active sources: 130/130 portable baseline and Scale plans
  pass (`outputs/repair-070/regression-*.json`). These are not native tests.
- 19 staged SKPs: real SketchUp 2025 save/reload, parameter edits and three
  consecutive native Scales pass. Model geometry/definitions/selection retained
  after each aborted QA transaction. Final evidence:
  `outputs/repair-070/native-verified.json`; the bevel guide recheck supersedes
  its failed pre-fix row, retained in `native-before-guide.json`.
- Source integrity: SHA-256 matches all 227 source DCs before publication.
- Published 13 newly converted sources to the existing library's `New folder`;
  all 300 previously present library SKPs retained byte-for-byte. Six verified
  sources already had successful historical records, so no deleted/renamed old
  path was restored. Journal, report backup and publication results are under
  `outputs/repair-070` and the library's `.conversion` folder.
- Active scope: 149/159. Cumulative original report: 171/227, with 46 failed
  sources excluded and ten active failures. Read the Vietnamese per-file report
  `outputs/repair-070/ket-qua-va-file-con-lai.md` for actual limitations.
- Packaged the explicit runtime manifest and verified RBZ entries/CRC using
  `python tools/package.py`. Reloaded changed owners in SketchUp PID 17900 via
  VBO and refreshed Library: 171 visible catalog entries, selected folder Khung
  preserved. Reload changed neither model geometry nor selection; evidence in
  `outputs/repair-070/reload.json`.

Not completed: the ten reported cases need native parent context, consistent
source geometry or additional frame/CAM semantics. Numeric-unit probing did not
find an all-parts-matching correction for the fridge or either remaining drawer.
No guessed COPY placements, profile extrusion or opaque ABF execution was added.
Manual-input LIST options remain a separate unfinished feature.
