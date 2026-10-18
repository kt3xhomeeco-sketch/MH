# Live library metadata refresh

Reflect external SKP additions, renames, edits and deletions in Library and HUD,
including subfolders. Preserve cache keys and selected view for untouched files.
Do not read SKP contents, render images or change native models during scanning.
Use one incremental enumerator, yielding between paths with a 4 ms Ruby work
budget per UI tick. Poll metadata while Library or HUD is open; stop UI timers
when both close. Two stable observations debounce
multi-step saves. Reopening schedules a fresh check without blocking warm HUD
opening. Manual refresh remains available.

Apply changes on the UI thread; preserve search, surviving selected items,
folders and HUD pages. Defer reconciliation during placement or icon dragging.
Removed/stale thumbnail requests must acknowledge their batch without preventing
other images from loading. Files disappearing mid-scan retry without publishing
a partial catalog. Missing roots clear stale entries and can recover. The budget
does not preempt one operating-system directory/stat call (slow/network disks
can still take longer). No background Ruby thread is required: native testing
found that idle SketchUp does not schedule these workers reliably.

Verify temp-directory add/rename/delete/edit, stable debounce, root switching,
no-change suppression, unchanged thumbnail keys, UI thumbnail races, lifecycle
and native timing. Run RuboCop/tests/browser checks, VBO reload and package.
