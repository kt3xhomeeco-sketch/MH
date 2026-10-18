# Target is only a measured envelope

The replaced object supplies its current bounds, position, orientation and scale.
Its T, DC formulas, MH rule JSON, geometry validity or internal assembly records
must not authorize/block rebuilding the imported source. The source's own program
still controls reconstruction. Do not infer/inherit parameters from the target.

Use a separate atomic replacement operation for top-level detached targets. Do
not read their internal rules/links or run unrelated assembly solvers. Leave raw
model link metadata and unrelated objects untouched. For externally linked or
scoped targets, preserve existing reference remapping but skip pre-replacement
redraw of the discarded target and skip parsing a discarded whole-wrapper's
internal links. Other ordinary assembly operations keep their current policy.

Verify malformed target ATT/own JSON, scaled wrappers with malformed internal
records, unverified/open geometry, global stale link metadata, actual measured
dimensions, shared copies and rollback when source reconstruction fails. Run
scoped tests/RuboCop, native SketchUp, reload and package.
