# Unlinked Fit and drawer size variants

User supersedes the original-size Shift policy: Shift placement fits without
creating links. It prefers a detected rectangular host cavity only when the fit
region reaches at least one side of the host envelope, proving it is open to the
outside; a fully enclosed void in a closed box is not an accessible cavity. If
no accessible cavity is found,
it fits to the bounds of the hovered group/component/DC/module without requiring
ATT metadata. A loose face is a planar target: fit the module's X/Z footprint to
the face bounds, orient its depth to the face normal, and preserve its source Y
depth/T. During Shift Fit, show the full target volume with a translucent fill
and clear outline, like MH_Superimp's fit preview; do not show only SketchUp's
hovered entity inference. If no bounded target is under the cursor, show a fit
prompt and do not place at the raw InputPoint. Normal saved-link behavior remains
unchanged; Ctrl retains Replace priority and continuous mode.

Read MH_Superimp as a reference only. Its drawer chooser stays in the same group,
subtracts 15 mm for concealed slides / 5 mm for ball-bearing slides, then selects
the longest standard 200–700 mm size <= usable depth + 0.5 mm. Studio must not
load, modify or call that plugin. Current Library has corresponding one-tier
drawer file series under Ngan keo. Match same normalized filename family and
folder, preserving kind, tier/row count and thickness suffix. Do not confuse fronts
or drawer frames with hardware drawers. Unsized entries can choose a sized sibling.

Use actual world-mm cavity depth, including host Scale. For a group/component
target without a cavity, use its transformed 3D bounds; for a loose face, use its
projected planar bounds and keep source depth. Choose before preview and commit,
re-evaluating at placement click. Keep the user's chosen seed stable while
hovering different regions; show the effective size. A drawer's readonly nominal
depth stays exact, front-aligned for free Fit; width and height fill a cavity.
Do not stretch a 500 mm slide to fill a 580 mm cavity. Normal linked placements
retain checked contacts and exact gap semantics. Unsupported conflicting fixed
depth contacts fail atomically rather than dropping requested links.

Selection/continuous Replace also choose per target depth. Preserve atomic batch
Undo: no nested preview operations inside replacement. Cache only bounded plain
preview JSON keyed by model, entry and file fingerprint, never live bindings.
Geometry/T/ATT verification remains enabled. No source SKP writes. Native QA uses
independent copies, ordinary/rotated/mirrored scale, real drawer files, Undo and
failure rollback; document anything not actually verified.
