# Unified cavity fit and import offsets

User approved plan: in cavity import, fit the available region after selected
contact clearances, rather than first filling the old cavity then fighting those
contacts. Prefer actual inner panel planes. At an open boundary, an explicitly
enabled slot may use the corresponding host envelope plane, persist that ordinary
module anchor, and distinguish it from a real highlighted face. Disabled slots do
not acquire new saved links. Fit supplies the initial remaining free dimensions;
saved selected plane relations remain responsible for subsequent constrained motion.
Preserve inset-door thickness and opposed-door reservation behavior.

All gaps and preview dimensions use actual millimetres, including nonuniform,
rotated, reflected host transforms. Extract scale from the transformation matrix,
not normalized SketchUp xaxis/yaxis/zaxis accessors. Maintain physical T and fixed
ATT dimensions; impossible targets fail atomically with a useful size diagnostic.

Acceptance: real file-1 cabinet/drawer copies, front 80 mm + back 0 and top 80 mm,
preview/native dimensions agree, unscaled and rotated/mirrored scaled frames,
post-import host T edits keep selected distances, one Undo/Redo and library
assembly save/load retain actual/virtual anchors; no source SKP/model changes.
Run prior door/import regressions, scoped RuboCop, unit tests and package/reload.
