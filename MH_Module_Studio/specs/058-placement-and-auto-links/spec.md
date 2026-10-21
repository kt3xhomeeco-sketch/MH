# Real placement latency and visible selection inference

After the icon preview was improved, uncached legacy cabinet placement still
took about1s; cached placement took0.37s. The user wants the delay after the
placement click reduced, plus an explicit automatic-link button from selection.

Prepare the selected icon's portable JSON/formula upgrade on one background Ruby
worker while the user positions the ghost. No SketchUp/UI/ABF access is allowed
on that worker. Share the bounded in-memory content cache with placement;
serialize cache misses, return private data, do not cache errors. Rapid selection
starts at most one worker; cancelled preparation may finish only as data cache.
The worker yields Ruby's GVL in bounded time slices, with a worker-only trace
that is removed on success or failure; do not trace or pause the main thread.
If placement must wait, disable worker pacing and restore normal worker priority
so the pending click does not pay background responsiveness overhead.
Immediate clicks still wait for any remaining preparation. Never promise zero
latency, change library SKPs, trust preview geometry or add a blocking UI timer.

Reuse the native geometry validation's calculated base plan. Newly upgraded
parameter keys already present at the same evaluated values do not require a
second plan/redraw. If actual Parametric targets differ, calculate that target
plan. Apply/stamp once and verify native geometry before committing. Preserve
Copies, visibility, cavity fitting, replacement, private definitions and Undo.

Show **Tự tạo liên kết từ vùng chọn** at the top of the Liên kết module utility,
without expanding a hidden section. It uses the existing explicit selected-module
contact inference, saves measured gaps without movement/grouping, and leaves
ordinary editable links. Search distance is optional. Do not infer on import.

Acceptance: concurrent cache ownership/failure tests, actual native preview and
placement measurements, unchanged formulas/geometry/selection/source files,
stale/mismatched geometry rejection, browser visible button and dispatch, native
selected-face batch inference, scoped RuboCop/test gate and runtime package.
