# Verification

Target: already-open model `1`, SketchUp PID 25420, VBO port 53244. QA used
independent copies of managed assembly 450543; original geometry, rule/value
payloads, definitions and selection were retained. No source SKP was rewritten.

- `bundle exec ruby tools/check.rb`: 117 Ruby files, no RuboCop offenses;
  247 tests, 2685 assertions, zero failures/errors/skips.
- `tools/native_assembly_scale_check.rb`: 11 successful cases, including repeated
  Scale on each axis, enlarged/shrunken aggregate, shared T1=20/18.6/17.6,
  atomic failed edit, rotated/mirrored wrapper and two side-by-side cabinets.
- `tools/native_assembly_scale_async_check.rb`: seven successful checks using
  actual observers, exact requested aggregate bounds, common T1, single Undo,
  queued Redo and subsequent Scale. Originals retained.
- The two-cabinet combined-width case already worked before this fix; no general
  size threshold was established. The reproduced fault was the door's thickness
  being incorrectly treated as a fixed envelope axis, followed by aggregate drift.

Detailed captures: `outputs/assembly-scale-040/after.json` and `async.json`.
Packaged `outputs/MH_Module_Studio-0.1.0.rbz` using the explicit runtime manifest.
Final pinned VBO reload succeeded in model `1`; selection remained assembly
450543, source state was retained and the legacy door policy resolved to axis Y.
The unrelated full HUD native suite was not rerun for this change. New aggregate
envelope fitting excludes repeat layouts and rejects impossible constraints.
