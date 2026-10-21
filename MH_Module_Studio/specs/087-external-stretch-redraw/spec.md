# 087 — External Scale / Stretch and linked construction dimensions

## Problem
MH_stretch can edit child definitions without changing root scale. The redraw
observer previously watched only root scale. Component adoption could also reset
another root's pending repair. Link observation discarded pending work on a
context notification/temporary abort. Opposed-door reservations treated a scaled
host-plus-door selection as a host-only scale, adding restored T and clearance
back onto the requested total depth (600 mm could become 606.4 mm).

## Requirements
- Detect internal geometric edits to owned modules after commit, reconstruct T
  and ATT using current geometry, and retain new free dimensions.
- Acknowledge app-owned geometry changes per instance; preserve unrelated pending
  external edits. Keep Undo/Redo and no-op edits coherent.
- Resolve contacts from current geometry after Stretch. Preserve pending link
  work through a cancelled temporary operation or unchanged active context.
- Direct deformation of a managed assembly supplies a new construction envelope;
  a rigid member Move is still governed by its links.
- When a host and all its opposed doors Scale together along their depth axis,
  preserve the scaled total construction depth, subtracting exact door T + gap
  from the host. Host-only Stretch supplies a new host depth. Parameter edits
  retain the independent construction target.
- Read scale magnitudes from transformation-matrix basis vectors because
  SketchUp's `xaxis`/`yaxis`/`zaxis` direction accessors normalize them.
- Coalesce MH_stretch's Scale, DC-dimension sync, and DC-redraw commits before
  applying Studio geometry; postpone contact solving until that redraw is idle.
- For linked roots, reconstruct T and resolve contacts/reservations in the same
  transparent transaction. Never commit a T-only intermediate envelope. Count
  Studio repair commits and inspect their envelopes in native regression checks.
- Modify only Module Studio. Do not patch MH_stretch, real SKP files or prefs.

## Acceptance
Portable observer regressions; native MH_stretch Scale and vertex Stretch on
private copies, repeated shrink/grow, current contact planes, exact T and 600 mm
host-plus-door total. Subsequent T edits must retain the new target. Check managed
assembly Scale/Stretch, cleanup, source independence and Undo/Redo.
