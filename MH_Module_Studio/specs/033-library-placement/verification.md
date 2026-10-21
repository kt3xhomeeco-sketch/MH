# Verification — 2026-10-16

- `bundle exec ruby tools/check.rb`: 90 Ruby files, no RuboCop offenses;
  200 tests / 2409 assertions, no failures or errors.
- VBO native execution in the existing SketchUp 2025 process 19224, port 7891:
  83 checks passed, including previous assembly/ATT/options regressions.
- Actual PickHelper cavity with shelf and partial brace; all-three-axis fitting,
  18.6 mm physical board thickness, rotated/mirrored/nonuniformly scaled host,
  nonzero definition origin, free placement, component identity, raw Group
  conversion, linked panel remapping, copied-wrapper independence, single Undo,
  invalid fit rollback and ambiguous anchor rollback passed.
- Actual HUD Tool callbacks exercised modifier press/release, preview rendering,
  Ctrl mouse flags, placement completion and return to icons. This is callback
  verification; no claim that new physical keyboard/mouse input was sent.
- Cleanup confirmed original entities/metadata, definitions and selection retained;
  camera/global links restored. Source DCs and the 69 library files were not written.
- Hot reload through VBO retained the user model, rescanned 69 library files and
  confirmed no native keyboard hook remained active after QA.
- `python tools/package.py` builds and verifies the explicit-manifest RBZ.

Evidence: `outputs/placement-033/gate.log`, `native.json`, `reload.json`.
Rectangular conservative bounds only; irregular parts occupy their bounding boxes.
Interior placement fits once; it does not silently create persistent assembly links.
