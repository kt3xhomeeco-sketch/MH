# Verification — 2026-10-17

- `bundle exec ruby tools/check.rb`: 159 Ruby files, no RuboCop offenses;
  319 tests / 3922 assertions, zero failures/errors/skips.
- `node test/assembly_inspector_smoke.cjs`: passed, including focused pristine
  title recovery and preservation of genuine title/variable/formula drafts.
- Native SketchUp PID 5032: `outputs/native-060.json` passed 21 checks for hollow
  envelope planes, unchanged manual picking, rotated/reflected modules, signed
  parallel offsets and reversible edits, actual SKP roundtrip, legacy inferred
  panel migration and independent scoped shared assemblies.
- `outputs/undo-060.json`: six native checks passed for atomic migration,
  Undo/Redo, manual record retention and unchanged geometry.
- Native fixture execution isolated its model-level records inside fixture
  transactions because the previous user's model already contained one orphan
  manual link to deleted roots. Cleanup restored the original user records;
  these checks do not establish that existing orphan manual records are repaired.
- VBO live reload into current SketchUp PID 26508:
  `outputs/reload-060-26508.json` confirms updated adapters/main, parallel support,
  source-title recovery and unchanged current selected module geometry/name.
  No Studio/Parametric dialog was open in this new session; no window or source
  module was opened/renamed merely for reload. The updated UI loads on next open.
- `python tools/package.py`: built and archive-verified
  `outputs/MH_Module_Studio-0.1.0.rbz` from the explicit runtime manifest.

Name recovery changes the Parametric draft/display. Persisting a recovered or
edited title to a module/source SKP still uses normal explicit Update/Save SKP;
reading or reloading does not write source files.
