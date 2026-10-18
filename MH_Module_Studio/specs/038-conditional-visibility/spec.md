# Conditional ATT inputs and existing-part visibility

Implement the two approved priorities: toggle existing geometry from ATT hidden
formulas and recognize inputs with dormant conditional effects. Copies generation,
rotation changes and Piecewise Affine algebra remain outside this feature.

New native snapshots capture each node's own hidden flag and tag visibility.
Versioned visibility-capable programs compute inherited visibility independently
of bounds. A part becoming visible must get its current formula geometry first;
inactive geometry stays frozen until needed. Tags and manual ancestor visibility
are preserved. Bind node updates through stable descendant part keys/ancestor
depths, not native PIDs. Existing programs without this metadata keep legacy guards.
All changes are transactional, verified, copy-independent and undoable; fixed
module envelope, collision, box/non-box and structural guards remain enforced.

Recognize transitive root-input dependencies across all supported AST branches.
Use bounded multi-value/threshold-adjacent probes as evidence, not replacement
formulas. Inputs with conditional potential remain identifiable even when local
probes produce no motion; disclose this status. Numeric and visibility-only scalar
inputs use the same safe evaluator. Structural-only inputs remain unsupported.

Acceptance: dormant IF/MIN/ROUND inputs, ancestor hidden propagation, tag masks,
hidden->visible after thickness/Scale changes, visible->hidden->visible, no-op
repeat, actual geometry/visibility verification, collision/invalid-size rollback,
repeated Scale and Undo/Redo, import/save round trip, legacy and 95-file regression.
Run scoped RuboCop/portable tests, actual VBO checks, package and reload only the
existing SketchUp session. Do not edit source DCs or launch SketchUp.
