# Persistent assembly HUD

Show the mockup's expandable assembly/module/panel/link tree on the left inside
the native viewport and a compact editable relationship utility on the right.
Tree nodes select/highlight the actual instance; link rows load A/B/C and values.
Keep the HUD visible when native Move, Scale or Orbit replaces the assembly Tool.
Picking A/B/C explicitly reactivates the assembly Tool. Ordinary M/S shortcuts
remain native; consume mouse clicks only on visible HUD rectangles.

Do not change ATT math, inter-module solver, grouping or scale observers. Preserve
face/body drag, fit, centering, angle, repeat, measured gaps and Undo. Close removes
the overlay, timers and process-local mouse filter without changing the active
native Tool. Model switches close the session rather than editing another model.

Plan: separate persistent AssemblyHUD lifetime from AssemblyTool lifetime. Use
Sketchup::Overlay only for read-only rendering; route bounded viewport clicks to
UI-thread timer callbacks, never mutate from overlay events. Reuse HtmlDialog for
real numeric fields and advanced repeat/fit controls. No global keyboard hooks.

Acceptance: expandable/scrollable tree, actual model highlight, link selection,
compact UI controls, persistence over Move/Scale, explicit pick reactivation,
unconsumed off-HUD clicks/keys, native geometry and Undo regression suite, browser
smoke, scoped RuboCop/tests, package and VBO reload in the existing session.

User steering: face and held-face outlines are 1 px. Face A alpha 175/255,
face B 190/255 and held face 225/255 make the filled highlight darker and more
opaque while preserving the distinct teal/amber colors.
