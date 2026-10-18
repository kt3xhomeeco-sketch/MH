# Plan

1. Determine whether a top-level target has readable external model references
   using only instance identities. A scoped target uses the existing linked
   replacement path. Unreadable global records remain verbatim rather than
   becoming a prerequisite for measuring/replacing a detached target.
2. Replace detached objects in a dedicated native transaction, without collecting
   old wrapper records, normalizing old children or running assembly solvers.
   Source fit/verification must succeed before the old definition is swapped.
3. For linked targets, exclude discarded whole-wrapper records and bypass
   pre-replacement target normalization/redraw. Keep ordinary transaction defaults
   unchanged, retain normal parent fitting and reference remapping after import.
4. Test policy without native objects; verify malformed own/DC attributes,
   malformed/scaled wrappers, open geometry, stale global metadata, rollback,
   scoped scaled broken targets and valid existing contacts in SketchUp.
5. Scoped RuboCop/tests, native Undo, live reload and verified RBZ.
