# 032 — Thickness symbols and linked module options

Normalize verified thickness input symbols to T1 for 17–18.6 mm, T2 for positive
thickness below 17 mm. Identify actual thickness drivers, not arbitrary numeric
values or panel offsets. Preserve original ATT bindings, retained variable IDs and
source evidence. Migrate own variable/detail references through ParameterRename.
Keep the assigned role stable after subsequent value changes. New imports/builds
use the same normalization. Migrate existing app-library SKPs with backup and
verification; source DC library remains read-only.

User explicitly selected merging multiple inputs in the same category into one
T1/T2 variable. Retain secondary ATT input keys as validated binding aliases of
the common variable. Use the panel/board input as primary, otherwise first input.
The common value drives every aliased input. Preserve a secondary panel's outer
high face when needed by generating its own position formula from the envelope.

The compact ModuleOptions dialog must work when selecting a managed assembly
Component and when selecting an individual member. Show shared T1/T2 at top,
private parameters beneath module name separators. Show mixed common values
explicitly. Respect existing visibility checkboxes. Apply common or private edits
and assembly solving in one transaction, preserving copy independence and Undo.
Reject stale tokens, external rule changes, invalid input and failed geometry
without partial updates. No new SketchUp process.
