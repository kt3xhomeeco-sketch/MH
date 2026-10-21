# Implementation plan

PlacementMath owns portable empty-box detection and affine fitting. LibraryPlacement
owns native picking, preview descriptors, fitted placement and atomic replacement.
Library builds validated instances before applying the requested transform.
LibraryHUD owns Ctrl state, live preview and click dispatch. Assembly.transact
accepts mutation anchors and a pre-solve block so replacement shares its existing
copy isolation, verification, persistence and rollback boundary.

Verify portable compartment cases and invalid fits, run scoped RuboCop/test gate,
then execute native temporary-fixture checks in the already-open SketchUp process.
Verify real PickHelper, geometry/thickness, rotated fitting, linked replacement,
copy isolation, Undo and rollback. Cleanup restores the user's entities, selection,
camera and saved links. Package and hot reload only after successful checks.
