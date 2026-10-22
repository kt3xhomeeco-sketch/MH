# Guide points and thickness redraw

Investigate the selected Canh phai instance in 2.skp without changing its source
until independent-copy verification passes. Captured mesh already measures T1
17.6 mm while native Y bounds are 605.64 mm due to two untransformed guide points.

Direct construction points must follow the same part-local affine change as
their owning faces/edges across Scale, parameter redraw, import and file updates.
Do not transform descendant meshes twice. Recover legacy unmarked points only
when they lie outside the current mesh and their unchanged native coordinates
fit the captured ATT node's local bounds; map through the original captured
ancestry/mesh bounds. Preserve their position ratios rather than clamp/delete.
Mark owned guides once so later intentional edits are not repeatedly recovered.

Automatic redraw must not skip a guide-only repair because mesh changed_count
is zero. Preserve existing Scale observers, T/ATT validation, copies and Undo.
Record actual asynchronous observer results, repeated Y scales, subsequent edits,
source/sibling independence and native bounds including guides.
