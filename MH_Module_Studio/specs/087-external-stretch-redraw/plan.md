# Plan
Keep numeric ATT planning in ScalePlan. Extend the native redraw observer with
cached definition bounds/child frames; Runtime stamp acknowledges only its root.
Extend assembly observation with pending lifecycle and native before frames for
external deformations and paired host/door scale. Existing reservation and
assembly-envelope owners apply explicit targets in their ordinary transaction.
Use app-scoped tests and isolated native fixtures; package and reload only after
verification. No changes to MH_stretch.

Follow-up: debounce alone cannot prevent the T-only commit from preceding the
contact solver. For linked models the Scale observer delegates its candidate
anchors to the existing Assembly transaction, which reconstructs T, reserves
door depth and solves contacts before committing. Its reset cancels the old
assembly timer. Keep the standalone Scale transaction for unlinked models and
avoid a second Undo when the assembly transaction already rolled back.
