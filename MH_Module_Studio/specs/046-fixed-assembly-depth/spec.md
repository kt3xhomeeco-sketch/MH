# Preserve assembly depth during thickness edits

Selected live assembly 463750 has a cabinet, double door and plinth with eight
contacts. Its local aggregate depth is 619.356498496493 mm. Common T1=30→40
currently grows depth to 629.356498496493 mm; returning to 18.6 leaves that larger
frame. Proven readonly door-depth growth currently expands the target before
trying the free cabinet/plinth depth freedoms.

Prefer the pre-edit aggregate bounds and anchor. First solve contacts and resize
free internal module dimensions. User-confirmed priority: physical T first,
then aggregate bounds and linked dimensions; individual module sizes may change.
Preserve exact chosen thickness and all contact
gaps. Readonly output growth permits fallback expansion only after measured
freedoms cannot fit positive sizes into the original frame. Native Scale targets
never permit this fallback, even in a request with parameter updates.

Do not overwrite the selected user's current dimensions, rewrite source SKPs, or
silently reset the already expanded object to a historical size. Fix subsequent
edits using the current frame. Verify private copies of the selected assembly,
repeated edits, large-thickness fallback, explicit Scale, copy isolation, options
callback, failed edits and native Undo/Redo. Record timing and actual limits.
