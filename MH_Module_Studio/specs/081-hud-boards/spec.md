# Explicit icon boards and directional HUD selection

HUD boards are independent of Library folders. Create, rename, delete, add pages
and clear slots only in Edit. Each board exposes its own SketchUp UI::Command in
Preferences → Shortcuts; alphabetic key events pass through the HUD to SketchUp.
Keep Library browsing separate from the destination board during drag. Preserve
existing explicitly stored icon orders once; do not generate boards or icons from
discovered folders. Legacy per-board A–Z keys are discarded during normalization.

Slots are sparse and persist exactly. External drops occupy the pointer's slot,
replacing its previous icon; internal dragging swaps slots. Never compact holes,
insert at a different index, append files from a folder, or grow a page implicitly.
Missing files become holes. Config import/export and file/folder rename remapping
preserve board identities, names and slot indexes. SketchUp shortcut assignments
remain in SketchUp Preferences and are not part of the exported HUD config.

Outside Edit, the pointer's angular sector selects/highlights one of eight icons
without requiring a direct icon hit. Center dead zone and explicit close/page
controls have priority. Empty sectors do nothing. Edit retains exact circular
drop targets so background clicks cannot move icons accidentally. The large ring
around the inner circle draws its outline only. Native placement modifier,
numeric icon shortcuts, Replace continuation and Escape behavior remain intact.

Validation: portable sparse/migration/remap/sector tests, HtmlDialog browser
interaction including name spaces and duplicate board names, native HUD rendering,
pointer hover/click, exact external drop, swap, reopen and geometry-free config edits.
