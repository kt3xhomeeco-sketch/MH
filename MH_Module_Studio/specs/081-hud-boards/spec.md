# Explicit icon boards and directional HUD selection

HUD boards are independent of Library folders. Create, rename, assign a unique
A–Z key, delete, add pages and clear slots only in Edit. Keep Library browsing
separate from the destination board during drag. Preserve existing explicitly
stored icon orders once; do not generate boards or icons from discovered folders.
Existing boards without assigned keys remain readable until edited.

Slots are sparse and persist exactly. External drops occupy the pointer's slot,
replacing its previous icon; internal dragging swaps slots. Never compact holes,
insert at a different index, append files from a folder, or grow a page implicitly.
Missing files become holes. Config import/export and file/folder rename remapping
preserve board identities, names, shortcut keys and slot indexes.

Outside Edit, the pointer's angular sector selects/highlights one of eight icons
without requiring a direct icon hit. Center dead zone and explicit close/page
controls have priority. Empty sectors do nothing. Edit retains exact circular
drop targets so background clicks cannot move icons accidentally. The large ring
around the inner circle draws its outline only. Native placement modifier,
keyboard capture, Replace continuation and Escape behavior remain intact.

Validation: portable sparse/migration/remap/sector tests, HtmlDialog browser
interaction including name spaces and duplicate keys, native HUD rendering,
pointer hover/click, exact external drop, swap, reopen and geometry-free config edits.
