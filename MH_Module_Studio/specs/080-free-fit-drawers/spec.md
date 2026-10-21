# Unlinked Fit and drawer size variants

User supersedes the original-size Shift policy: Shift placement detects the free
rectangular host cavity and fits without creating links. Outside a detected cavity
it retains raw placement. Normal saved-link behavior remains opposing-face-only;
Ctrl retains Replace priority and continuous mode.

Read MH_Superimp as a reference only. Its drawer chooser stays in the same group,
subtracts 15 mm for concealed slides / 5 mm for ball-bearing slides, then selects
the longest standard 200–700 mm size <= usable depth + 0.5 mm. Studio must not
load, modify or call that plugin. Current Library has corresponding one-tier
drawer file series under Ngan keo. Match same normalized filename family and
folder, preserving kind, tier/row count and thickness suffix. Do not confuse fronts
or drawer frames with hardware drawers. Unsized entries can choose a sized sibling.

Use actual world-mm cavity depth, including host Scale. Choose before preview and
commit, re-evaluating at placement click. Keep the user's chosen seed stable while
hovering different cavities; show the effective size. A drawer's readonly nominal
depth stays exact, front-aligned for free Fit; width and height fill the cavity.
Do not stretch a 500 mm slide to fill a 580 mm cavity. Normal linked placements
retain checked contacts and exact gap semantics. Unsupported conflicting fixed
depth contacts fail atomically rather than dropping requested links.

Selection/continuous Replace also choose per target depth. Preserve atomic batch
Undo: no nested preview operations inside replacement. Cache only bounded plain
preview JSON keyed by model, entry and file fingerprint, never live bindings.
Geometry/T/ATT verification remains enabled. No source SKP writes. Native QA uses
independent copies, ordinary/rotated/mirrored scale, real drawer files, Undo and
failure rollback; document anything not actually verified.
