# Direct placement, batch parameters and contact dimensions

Confirmed: after choosing a Library icon, modifiers at the model placement click
control the operation. Ctrl replaces; Shift inserts freely at original size;
plain click uses the saved contact template. No template or no found contacts
also inserts at original size. Only two selected opposing faces resize an axis;
one face aligns at its gap while preserving size, no face leaves that axis free.

Multi-select owned modules/managed assemblies: same compatible symbols merge at
the top of Module Options; mismatched values display mixed. One edit updates all
selected targets atomically, with model/selection/token/input guards. Private
parameters remain grouped under member names. Does not group model geometry.

Replace the automatic left-tree/right-inspector HUD with direct saved-contact
visuals. Nonzero contact gaps show a prism projected from the smaller face,
without A/B letters. Draw an editable dimension; click it for numeric input
(similar to MH_stretch), click the prism to open advanced link settings. Zero
contacts retain a clickable 0 dimension but no volume. Closing settings returns
to the model. Native Move/Scale keep mouse priority when the link tool is inactive.
Keep creating, auto-detecting, grouping and other relation modes reachable via
context menu/settings. All edits keep existing Assembly transactions and Undo.

Checks: modifier transitions without moving pointer, click-time flags, raw/no-link
fallback and two-face resizing; shared-symbol batch guards/rollback; projected
small-face geometry, hit priority and dimensions including zero, native rendering,
dim edit, settings, Move/Scale priority and saved relation persistence. No source
SKP or unrelated plugin changes. Read MH_stretch UI as a reference only.
