# 089 — Responsiveness before total redraw speed

The user prioritizes continuous interaction over the time required to finish an
update. Exact T, fixed ATT dimensions and linked envelopes still apply.

## Behavior

- Scale/Stretch repair, Module Options edits and manual Redraw prepare portable
  calculations away from the SketchUp event thread. Workers receive owned data,
  never model entities, native bindings, view objects or host API calls.
- Return control between bounded preparation steps. Abort any tentative native
  operation before yielding; never leave an operation open while a worker runs.
- Use a final atomic transaction for T recovery, linked contact/reservation
  solving and metadata. Intermediate tentative geometry must not become visible.
- New edits supersede older pending input. Preserve every outstanding field,
  acknowledge the matching request revision, and ignore obsolete replies.
- Undo, external model edits, changed context/model or a changed selection for
  Module Options invalidate pending results. Do not overwrite newer geometry.
- Keep a bounded calculation cache local to a job, with explicit ownership and
  complete rule/geometry/value keys. A late unexpected cache miss fails safely.
- Synchronous internal APIs remain available for existing native transactions.

## Verification

Portable tests cover supersession, cancellation, failure rollback, empty native
operations, data isolation and no open transaction between callbacks. Browser
checks cover rapid edits, stale replies, retained focus and model switching.
Native checks use private copies in the running SketchUp session, verify exact
T/envelopes and one final repair commit, and measure event-loop gaps and callback
duration. Preserve the actual model, selection and saved preferences. Report
measured limitations; do not infer zero stutter from geometry tests alone.
