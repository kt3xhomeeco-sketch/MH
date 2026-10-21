# Validation — 2026-10-20

- `test/assembly_tree_test.rb`: 4 cases / 13 assertions cover unlinked scene,
  same-named participants, repeat copies, scoped copied assemblies, wrapper link
  and filtering after records disappear.
- `tools/native_linked_tree_check.rb`: three checks passed in SketchUp PID 13124:
  linked raw groups shown, unrelated group absent, repeated rebuild read-only,
  deletion removes dead relation and isolated participant. Aborted all test data;
  original entities, definitions and links retained (`outputs/linked-tree-075/native.json`).
- `test/import_template_browser.cjs`: header button opens existing configuration,
  five-face preset / door / gap / partial selection round trip and Save SKP payload
  passed. Header has no overflow at 1200/1000/850 px; assembly config button disabled.
- Native import matching and save engine unchanged; no user library files rewritten.

- Scoped final gate: 209 Ruby files clean; 385 tests / 4429 assertions passed.
  Runtime RBZ rebuilt from the explicit manifest; active SketchUp backend reloaded via VBO.
