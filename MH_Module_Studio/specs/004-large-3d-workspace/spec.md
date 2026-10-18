# Approved large 3D workspace

Implement the approved mockup: dominant left 3D canvas (~73% width), compact
parameter sidebar, untitled tick column, collapsible panels/relations, formulas
and captured states. Preserve all bridge actions, editable selections, draft
values, one-state ATT analysis and Cancel recovery.

Opaque surfaces must occlude hidden faces and edges, independent of draw order.
Teal highlighting stays opaque. X-ray is a separate explicit mode. Include edge
toggle, perspective/orthographic/front/top/side views, fit, orbit, pan, zoom and
viewport expansion. Show source geometry before preview exists, and allow source
vs result switching. Continue displaying captured panel bounds, not claiming to
have imported arbitrary full meshes.

Acceptance includes pixel-based depth/hidden-edge checks, fallback rendering,
responsive layout, parameter actions, UI states, native VBO reload and an updated
runtime-only package. Source model geometry must not be modified for UI tests.
