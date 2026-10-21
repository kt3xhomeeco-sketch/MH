# Fast Library HUD open

Measured before the fix: eight icons spent2.33s redoing ink/trim on every open;
PNG reading/upload took only a few milliseconds each. Scan was0.15s and is not
repeated on every open. Preserve current views,2x ink, margin crop, zoom/circles,
placement, keyboard behavior and source files.

Reuse versioned prepared PNGs in a temporary HUD cache keyed by the Library
thumbnail identity. Cold images show their raw thumbnail immediately; enhance
one visible image per UI timer tick and store it for later opens/sessions. Warm
opens load prepared PNGs without pixel processing. No SketchUp API on threads.

Changing view/file keys invalidates images. Page/folder changes discard stale
jobs; Esc/deactivation/model change must not update released textures or spin
timers. Failed enhancement keeps the raw image usable. Cache write failure must
not disable placement. Verify cold/open vs warm timings, actual native GPU
replacement and cancellation, scoped tests and package.
