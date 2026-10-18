# Tasks

- [x] Profiled eight actual thumbnails:2.33s in repeated pixel processing.
- [x] Add prepared PNG cache and immediately displayed raw cold thumbnails.
- [x] Queue one visible-image enhancement per timer; cancel stale/deactivated jobs.
- [x] Scoped gate:152 Ruby files clean;302 tests /3809 assertions passed.
  Browser Library/HUD interaction checks passed.
- [x] Portable pipeline regression covers no pixel processing before open,
  one-image ticks, persistent cache on reopen, changed view keys, page replacement,
  cancelled/model-switched jobs and retaining a usable raw image on failure.
- [x] Actual native benchmark:8 immediate cold previews in35ms; warm loads in
  34–41ms, no queued pixel work. One-time preparation2.40s is deferred and cached.
  Original measurement2.33s repeated pixel work. outputs/benchmark-055.json.
- [x] Actual UI timer prepared exactly one image, stopped the pending timer/job
  on cancellation and retained no work after100ms; no image job failures.
  outputs/timer-055.json. QA GPU textures released; live HUD retained.
- [x] Ruby reloaded via VBO; live HUD active without draw errors. Runtime RBZ
  rebuilt and archive/manifest verified.
