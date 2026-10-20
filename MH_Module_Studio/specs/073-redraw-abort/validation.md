# Validation — 2026-10-20

Target: existing SketchUp PID 14572, VBO port 7891, open model `1` at
`E:/MAC/OneDrive/Desktop/1.skp`. Selected owned component `Khung noc lot`,
persistent ID 472610. No SketchUp process or model was opened by this check.

Initial read-only inspection measured outer size 600 x 580 x 500 mm, root Y
scale 2.9, saved back T=8 mm and actual back T=23.2 mm. ScalePlan could repair
three parts while preserving the requested envelope; watcher error was nil.

Private native reproduction showed normal Scale and Scale followed by a second
commit already worked. Scale followed by an unrelated abort left three parts
unrepaired, back T=8.8 instead of 8. Native callbacks include Undo and unchanged
active-path notifications, so a change to the Abort callback alone was insufficient.

After preserving the pending committed job across those callbacks:

- Isolated regression covers pending abort, unchanged/changed edit paths,
  cancelled Scale, Undo before/after completed redraw, applying guard and a
  second unrelated commit. 13 assertions pass.
- `tools/native_redraw_abort_check.rb` passed 16 geometry/transaction checks on
  private copies of the selected real module. Repeated enlargement/shrink and
  multiple immediate aborts retained actual back T=8 mm with zero remaining
  plan changes. One Undo and Redo restored exact prior geometry and values.
  Cancelled Scale and a shared-definition sibling remained unchanged.
- Native QA restored original geometry, definitions and selection; source
  geometry/rule/input fingerprint matched. Receipt: `outputs/redraw-073/native.json`.
- The actual selected instance was then repaired in one separate transaction.
  It remains 600 x 580 x 500 mm at its original transform with identical inputs,
  actual back T=8 mm and zero remaining redraw changes. Other model geometry
  was verified unchanged. Receipt: `outputs/redraw-073/repaired.json`.
- Runtime was reloaded through VBO. The open model was not saved to disk.
- Final scoped gate: 203 Ruby files, no RuboCop offenses; 375 tests and 4388
  assertions, no failures/errors/skips. An earlier unrelated LibraryMonitor
  metadata timing check failed once under load; isolated rerun and final full
  gate passed without changing that feature.
- Runtime RBZ rebuilt with `python tools/package.py`; developer checks excluded.
