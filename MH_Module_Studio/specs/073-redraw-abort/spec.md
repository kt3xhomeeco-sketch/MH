# Preserve pending Scale redraw after unrelated aborts

The open file `1` contains an owned `Khung noc lot` at depth 580 mm whose back
has scaled from saved 8 mm to 23.2 mm. The existing planner can repair it without
changing the requested envelope. The watcher has already accepted its transform.

Native reproduction on a private copy: a normal Scale and a Scale followed by a
second commit both redraw correctly. A committed Scale followed immediately by
an unrelated cancelled operation resets the watcher before its queued timer.
The timer becomes stale, leaving the back at 8.8 instead of 8 mm.
Actual SketchUp dispatch reports this cancellation through Undo and an unchanged
edit-path callback as well. Handling only onTransactionAbort does not fix it.

On abort, re-evaluate actual transforms against the last acknowledged baseline.
Keep any earlier committed Scale pending; discard a cancelled Scale that truly
restored the baseline. Ignore recursive callbacks while applying. Preserve Undo,
Redo, copy independence, fixed ATT dimensions and safe transaction behavior.
Only an already pending committed Scale may be resumed by Undo/abort or a same-
path notification. A completed Undo must not start a new repair or erase Redo.

Verify event scheduling in isolated tests and real model geometry on private
copies. Repair the selected already-scaled instance in a separate Undo operation,
keeping its current placement, outer size, parameters and other model objects.
