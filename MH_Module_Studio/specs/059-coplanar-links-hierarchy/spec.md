# Coplanar inference and module-first HUD hierarchy

The user reports missing automatically inferred coplanar faces and wants linked
module names on separate rows, followed by their relationship types. A grouped
assembly with three or more members must list every member under Links.

Extend explicit selection inference to nearby coplanar rectangular native faces,
including same-facing adjacent front/top/bottom faces with no area overlap.
Require parallel plane normals and at most0.02mm measured plane offset, plus
actual polygon proximity within the existing search range. Do not match remote
or merely overlapping projected bounding boxes. Retain measured signed offsets,
current geometry, Undo, duplicate suppression and dependency direction. Preserve
normal opposed-face inference. Coplanar links use the existing contact solver
with presentation metadata, so they remain editable and persist in saved SKPs.

The native left tree gets a visible selection-inference button, in addition to
the utility button. Under Links, group all relationships for each module pair:
one row per module name, then clickable relationship rows. Managed assemblies
show every member under their group, not just the first two anchors. Both HUD
surfaces share portable presentation data; no concatenated A→B name row.
Opening existing groups must show saved relationships without extra expansion.

Validate native coplanar inference, no-motion creation, subsequent edits,
rotated/reflected instances, selected grouped assemblies, saved metadata and Undo.
Test portable geometry and presentation ownership, native tree button dispatch,
browser ordering/click targets, both live SketchUp sessions and runtime package.
