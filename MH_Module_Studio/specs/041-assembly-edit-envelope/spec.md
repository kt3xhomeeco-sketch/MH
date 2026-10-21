# Assembly edits preserve aggregate envelope and avoid redundant redraw

When parameters change on a member or a common T1/T2 row, retain the managed
parent assembly's pre-edit local bounds and anchor. Resize internal modules using
their own formulas and existing contacts. Never scale thickness itself to force
a fit; preserve explicit B-follows-A and stored gaps. Impossible combinations
abort atomically. Repeat layouts keep their current source/copy semantics.

Measure the real edit pipeline on independent copies in the already-open model
1. Reduce demonstrated redundant calculation/redraw rather than remove geometry
verification or suppress errors. Keep calculations portable, private copies
independent and Undo/Redo atomic. Avoid repeated dialog refresh/thumbnail work.

Acceptance: repeated T1/T2 and private edits preserve the aggregate box and all
contacts; Scale still reaches requested bounds; copying, invalid edits and
Undo/Redo remain correct. Record before/after timings and native redraw counts,
run scoped RuboCop/portable tests, package and reload through pinned VBO. Original
selected geometry and source SKPs must remain untouched by verification.
