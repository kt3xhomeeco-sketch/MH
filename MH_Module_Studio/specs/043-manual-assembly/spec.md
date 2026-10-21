# Manual grouping, names and thickness envelope correction

Stop automatic component creation/regrouping on Save Link. New links remain
editable on their actual instances; user explicitly clicks Group after finishing
relationships. Keep parent Component/inner Group architecture. Adding further
links never destroys/regroups the existing wrapper automatically. Group must be
atomic, preserve rules, instances and stable remapped anchors, and support Undo.
Existing grouped projects retain their relationships until user explicitly groups.

Show both source and target module names in link lists/tree, resolved live after
rename. Allow real module instance names to be edited directly in the link panel.

Inspect actual double-door/kitchen models. Prefer preserving the current frame;
when supported thickness formulas require more room, permit the frame to expand
instead of blanket fixed-envelope rejection. Keep geometry/collision checks and
exact ATT dependency semantics. Do not silently shrink panels or change chosen
thickness. Diagnose large-thickness kitchen failures with actual formula data.
Record exact supported behavior and remaining unsupported cases. No source SKP
rewrites; native checks on private copies in the user's already-open SketchUp.
