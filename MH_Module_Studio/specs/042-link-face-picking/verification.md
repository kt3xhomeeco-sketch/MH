# Verification

Target: existing model `1`, SketchUp PID 25420 / VBO 53244. Independent QA
entities only. Original geometry, attributes, definitions, model-level link
payload and selection retained. Camera restored after picking tests. No SKP
source files written and no other SketchUp instance accessed.

- Scoped gate: 124 Ruby files, 253 tests / 2770 assertions, no failures/errors/skips. New portable
  coverage: modifier priority, six-face labels, immutable draft anchors and
  collapsed external dependency rejection. RuboCop clean.
- `native_face_picker_check.rb`: 52 checks passed in the earlier live-source run, including all six module and
  assembly faces in ordinary and reflected/rotated frames, real back face versus
  virtual open-front selection, near-edge tolerance, immediate modifier preview,
  Shift/Ctrl click dispatch, intact assembly grouping, opposed contacts, editing,
  Undo, cross-scope coordinates, real owned formula reconstruction at retained
  T1/T2 values, center/fit/angle and ordinary Shift grouping.
  Final rerun: 50 checks passed including the added cross-scope observer fingerprint
  check. The original live assembly 450543 was no longer present in the current
  user model, so the three additional live-source checks were skipped on this run;
  no source was reloaded or restored. The earlier native run verified those cases.
- `native_face_picker_async_check.rb`: five checks passed with actual observers,
  one Undo, queued Redo and independently fitted copied assemblies.
- Browser inspector smoke passed, including modifier guidance, fields, opposing
  boundary/fit, directions, layout and existing Parametric Read SketchUp behavior.

Artifacts: `outputs/face-picking-042/native.json`, `async.json` and the browser
capture in `outputs/assembly-029/`.

Additional legacy Scale regression on the user's currently modified T1=50 source:
10/11 cases passed. Shared T1 ->20 is rejected by cabinet Core.plan's existing
fixed-envelope check even before any native grouping/contact operation. All
calculation files are byte-identical to the preceding 041 RBZ (verified before
packaging 042 in `core-baseline.json`). This separate formula limitation remains;
do not claim that shared-T1 scenario passed. Source state was retained.

Whole-assembly external links intentionally retain existing wrappers at model
level; they do not create a new common outer component. Whole-assembly repeat
and self-containing dependencies are rejected explicitly. New interaction
mockups for resize/add/remove remain outside this implementation.

Packaged `outputs/MH_Module_Studio-0.1.0.rbz` from the explicit runtime manifest.
Final pinned VBO reload succeeded in model `1`; user root fingerprints, definition
identities, global links and selection were retained. The user's current Select
tool stayed active; the new modifiers activate only inside Link Modules.
