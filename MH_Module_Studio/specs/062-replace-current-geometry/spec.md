# Replacement uses live target dimensions and restores import baselines

Ctrl+click replaces ordinary raw groups/components, DCs and owned modules using
the target's current oriented bounds, including existing scale, rotation,
reflection and nonzero origins. A target needs no ATT or MH rules. Preserve
unselected shared instances and perform replacement in one Undo transaction.
An explicitly selected managed parent can be replaced as a whole; otherwise
pick its member as before. Remove internal links with replaced contents; retain
external envelope links, rejecting unresolved external member references rather
than silently dropping them. The replacement keeps source T; target T is not
inherited automatically. Avoid redundant selection events when the surviving
component is already selected.

The reported Khung noc lot -> Khung noc lot LC50 failure occurred while reading
the source: its saved snapshot specifies 17.6 mm boards while initially loaded
native meshes included 11.306 mm boards. A separate SDK read of disk geometry
shows correct 17.6 mm boards, and later native loads are consistent; do not claim
that the disk file itself is corrupt. On the private imported copy only, reconstruct exact geometry
from the saved internally consistent formula snapshot before fitting the target.
Require identical part identities/topology/visibility and normal geometry-motion
validation; revalidate native results strictly. Do not weaken ordinary parameter
edit/export validation or rewrite the source SKP during import. Changed topology
or inconsistent saved formulas still abort atomically, retaining the target.
Verify serialized geometry after export, before replacing the destination.

Verify the actual source and LC50 files, raw Group/DC targets, scaled/mirrored
targets and shared instances, live bounds fit, physical T, retained references,
Undo and source hashes. Run scoped tests/RuboCop, native VBO and package.
