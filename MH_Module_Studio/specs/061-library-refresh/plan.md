# Plan

1. Use the existing portable catalog traversal and file fingerprints. Reuse each
   path's stat/canonical path instead of repeating filesystem operations, keeping
   boundary/symlink checks and fingerprint semantics.
2. Make traversal yield between paths. One enumerator resumes within a 4 ms Ruby
   work budget on 100 ms UI ticks, with scans spaced by 2 seconds when unchanged.
   Two equal changed observations debounce writes. Reset discards pending work
   when the root changes; failed scans never replace the current catalog.
3. Library owns timer lifetime based on the Library tab and HUD visibility.
   Reconcile only changed catalogs, retain the thumbnail-view cache, and defer
   during placement/drag. Opening schedules a fresh check; manual refresh stays.
4. Browser preserves search/valid selection/images, acknowledges removed image
   requests, retries late outdated image responses and distinguishes unsolicited
   catalog pushes from command acknowledgements.
5. Verify portable races/boundaries, browser behavior, actual native timers and
   per-tick cost on the user's library, then scoped gate/VBO reload/RBZ.

Native validation rejected the initial background-thread approach because idle
SketchUp did not reliably schedule it. Incremental traversal avoids background
thread coordination and bounds Ruby work directly. Individual OS filesystem
calls remain outside the budget's preemption control.
