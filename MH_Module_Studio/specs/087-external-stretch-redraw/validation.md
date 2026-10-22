# Validation — intermediate Scale/Stretch sizes

2026-10-21, SketchUp 2025, existing process 22980 / file 2.skp.

The native checker creates independent fixtures from the selected-model module
sources, executes actual MH_stretch Scale/Stretch methods, and deletes its
fixtures. It retains the source geometry, selection, preferences and links.

Before the atomic fix, transaction tracing reproduced three committed depths:
600.000000 mm after MH_stretch, 606.839861 mm after standalone T reconstruction,
then 600.000000 mm after the assembly contact solve. Debouncing did not remove
the second transaction's invalid envelope.

After the fix, the paired Scale emits exactly one Studio repair commit and its
depth is 600.000000 mm. Both redraw and assembly flags are active in that single
transaction. No T-only intermediate depth is committed. All 13 native checks
pass, covering exact T, repeated vertex Stretch, total depth, host Stretch,
subsequent T edit and the linked door following current host faces. Source,
selection and preferences retention checks all pass.

Scoped gate: 247 Ruby files clean in RuboCop; 447 tests, 4,797 assertions,
0 failures/errors/skips. Portable coverage includes the coordinated redraw
anchors and single-owner rollback, preserving the original reservation target.

This records transaction-level behavior on fixture copies. It is not a
frame-by-frame video of the user's viewport or a certification of every other
extension's redraw behavior. The native fixture does not exercise Undo/Redo of
a whole managed assembly; the portable rollback regression verifies no double
Undo by the Scale observer on an assembly failure.
