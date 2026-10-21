# Validation — 086

- Exact source: app-owned Canh phai, PID939919 in existing 2.skp / SketchUp
  PID22980, port7891. Two direct ConstructionPoints in part:0001 lay outside
  its already-repaired mesh. Physical mesh Y=17.6 mm, native bounds Y=605.6424 mm.
- Baseline on a private copy: the automatic observer did run and kept physical
  T1=17.6 after Y x2, but native bounds grew to 1211.2848 mm because guides stayed
  behind. Thus the reproduced issue was incomplete auxiliary geometry, not a
  missing automatic observer. Receipt: outputs/guide086/baseline.json.
- Fixed private copy: initial legacy recovery and asynchronous Y x2, Y x0.7
  all leave mesh AND native bounds at 17.6 mm. A subsequent T1=20 edit changes
  both to20 mm; two unchanged redraws preserve guide positions exactly.
  Receipt: outputs/guide086/fixed.json.
- Guide-only automatic repair: legacy bad guides with already-correct solid T
  followed by X x1.1 produce a330 ×17.6 ×300 mm native box. This exercises the
  zero-mesh-change early-return exception. outputs/guide086/guide-only.json.
- Source component and other model root bounds retained after each independent
  native fixture; only owned copies/definitions were removed. Selection was not
  changed. No source SKP, saved Library settings or active tool was opened/changed.
- Portable tests cover ancestry/missing/cyclic references, affine point positions
  and offsets, direct guide inclusion exactly once and descendant exclusion.
  Scoped gate:244 Ruby files clean;440 tests,4733 assertions, no failures/errors/skips.
- Updated explicit manifest and RBZ:110 runtime files verified byte-for-byte.
- Reloaded in both existing SketchUp processes, with model/selection/preferences
  retained. Original target was not rewritten: selection changed during work and
  a direct repair attempt stopped before mutation because the user had an active
  native tool. The next ordinary Scale/Redraw repairs its legacy guides through
  the verified runtime path. outputs/guide086/repair-result.json records that guard.
- No native Undo/Redo test added for this follow-up; guide motion uses the caller's
  existing transaction. Existing portable observer/boundary tests pass. No commit
  or push performed; concurrent plugin projects remain untouched.
