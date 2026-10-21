# Module picking and inferred contact links

Click picks real panel faces; Shift+Click picks module envelopes; Ctrl+Click picks
assembly envelopes. During A/B picking the other module is excluded, including
its whole-assembly parent/child. Hover and commit use identical eligibility.
Fit/center/equal repeat still allow A and C on the same surrounding module;
measurement references may also share a module. Dragging outside pick mode is unchanged.
Excluded geometry remains visible and unmodified; real faces behind it remain pickable.

Add an explicit automatic-contact action for selected modules or members of
selected managed assemblies. Use real rectangular box-boundary faces, opposed
normals, projected positive overlap and measured nonnegative separation. A visible
maximum search distance defaults to 20 mm (0–1000). Skip occluded/farther faces,
duplicates, repeat copies and cyclic dependencies. Preserve current gaps exactly.
Never guess relationships from names or link empty bounding-box space.

Generated links are ordinary editable contact records: B follows A, two opposite
contacts permit existing resizing, and grouping remains explicit. Creation changes
only owned relationship metadata (and makes relevant shared assembly definitions
private); it never moves/scales/redraws modules. One Undo removes the batch.
No source SKP is written. Existing internal ATT formulas retain their ownership.

Acceptance: nested-module pointer picking; A/C reuse; parent/child exclusion;
touching/gapped/rotated/non-overlapping faces; blocked rays; repeated discovery
adds nothing; graph direction respects existing links; generated edits move B;
native transforms/vertices unchanged on creation; scope/copy isolation; Undo/Redo;
browser action and narrow layout; RuboCop/tests/package and native reload.
