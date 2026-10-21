# 030 — Assembly components and direct face/body dragging

After saving a link, collect its connected modules inside an ordinary SketchUp
component, preserving their geometry and individual module rules. Existing grouped
links remain editable without opening Studio. Merge connected assemblies when a new
link joins them. Retain one Undo for grouping plus solve. Copies must have independent
assembly instance identities and links; moved/rotated/scaled wrappers keep references.

Remove all XYZ/center/gap handles. Click-hold the linked target face to change its
offset along the normal; click-hold another surface of a module for free movement
projected to its allowed directions. Highlight the held face with a darker fill and
outline. Click without drag creates no Undo; Escape restores preview. A/B picking
continues to work through the assembly wrapper. Update inspector instructions.

Keep scope persistence/grouping in a native adapter; local assembly plane math stays
portable and internal ATT remains unchanged. Test grouping, merge, copied components,
rotated contexts, fit/repeat, direct dragging, Undo/Redo, file reopen and user reload.
