# Automatic redraw after Scale

User request: automatically recalculate owned modules after SketchUp Scale.

At the end of a Scale transaction, preserve its new physical envelope and
instance transform (placement, anchor, rotation, reflection). Restore saved
parameter inputs and rebuild panel dimensions/positions with imported ATT and
the current own rules. Work without Studio or Options being open. Multiple
selected modules and shared component definitions must remain independent.
One Undo reverses Scale and redraw together; Redo restores the complete result.
Further parameter edits must work without reading the module again.

Only owned top-level modules are watched. Ordinary DCs and other extensions'
objects are not modified. Scaling individual inner panels, exploding a module,
new topology/visibility/rotation branches, and observation-only formula engines
are outside this feature. Invalid geometry or unsupported rules must reject the
whole triggering Scale transaction, restore the previous valid state, and explain
the reason. Never silently accept stretched thickness or a partial repair.

Acceptance: nonuniform/uniform/repeated Scale; ATT + own spreadsheet rules;
ordinary geometric constraints; multiple instances; rotated/mirrored placement;
post-Scale parameter edits; single Undo/Redo; invalid shrink and rollback;
observer registration on extension load and model open; native execution.
