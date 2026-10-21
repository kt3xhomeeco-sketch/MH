# Plan

Keep absolute reconstruction in ScaleRedraw, separate from Core.plan's normal
ATT baseline validation. Evaluate the safe imported ATT program at the new
envelope with stored inputs, then solve own constraints and spreadsheet cells.
For geometric modules solve thickness/contact rules using stored values instead
of measuring the stretched drivers. Validate actual boxes and the strict 0.001mm
envelope invariant before applying.

A persistent app/model observer detects changes in root axis scale lengths.
Transaction callbacks only read and schedule a zero-delay timer. In that timer,
preflight the entire changed batch, then use a transparent operation to merge
with Scale. Keep root transforms; conjugate physical deltas through existing
Reader frames. make_unique isolates root and descendants before vertex changes.
On an unexpected apply failure, commit the transparent operation and undo the
combined chain; never abort a transparent operation. On preflight failure undo
the triggering transaction. Undo/abort invalidate pending timers and reset
observed scale baselines. Redo rechecks the result: an already repaired result
does not create an operation, preserving the remaining Redo history. Replaying
a rejected Scale is validated again instead of accepting invalid geometry.

SketchUp API references:
- https://ruby.sketchup.com/Sketchup/ModelObserver.html (defer model edits)
- https://ruby.sketchup.com/Sketchup/Model.html#start_operation-instance_method

Portable regression tests, scoped RuboCop/test gate, actual native timer/geometry/
Undo/Redo/copy checks, then reload both working SketchUp sessions and package.
