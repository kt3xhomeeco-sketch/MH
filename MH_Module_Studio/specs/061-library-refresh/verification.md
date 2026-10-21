# Verification — 2026-10-17

Portable checks cover stable add/edit/rename/delete observations, unchanged file
fingerprints, root switch/missing-root recovery, partial-tick yielding and a file
removed between ticks. Controller checks cover timer lifecycle, retained view
cache, placement deferral, unsolicited updates and removed-thumbnail replies.

Both browser checks passed:

- `test/library_refresh_browser.cjs`: rename/delete catalog updates, search and
  surviving selection, cached images, late stale image responses, command state
  and close/reopen visibility.
- `test/library_views_browser.cjs`: existing per-icon views, asynchronous cache
  invalidation, unsubmitted view retention and HUD settings behavior.

`outputs/native-061.json` passed in SketchUp 2025 PID 17844 through VBO. Actual
UI timers observed temp-folder rename/delete/add (including a new subfolder),
retained the thumbnail manager and stopped monitoring when closed. Current
model identity, modified flag, entity count and selected entity bounds remained
unchanged. No native model mutations or source SKP writes occur in the check.

Measured in this session:

- Existing library: 116 SKPs; one unchunked metadata scan took 68.3 ms.
- Incremental scan of that library completed over 1761 ms of elapsed time,
  returning to SketchUp between slices.
- Maximum measured monitor callback, including reconciliation: 4.53 ms.
- Temp-folder changes were applied after 4166 ms (stable-observation debounce).
- Maximum 100 ms UI heartbeat gap was 184.5 ms across the session. This includes
  other SketchUp activity; it is not attributed solely to the monitor. These
  measurements do not guarantee zero lag on other disks/libraries.

Native Ruby worker scheduling proved unreliable for the initial design. The
shipped implementation uses no worker threads: a resumable metadata enumerator
has a 4 ms Ruby work budget per tick. One OS directory/stat call can overrun that
budget. Original sources stay unchanged and unchanged files keep their image
keys; thumbnail rendering remains in the existing on-demand image path.

Final scoped gate and package results are recorded in tasks.md.
