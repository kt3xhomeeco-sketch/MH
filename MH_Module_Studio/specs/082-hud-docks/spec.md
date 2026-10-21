# HUD spacing, explicit number keys and viewport docks

Implement now per the user's changed decision; the existing 05:30 21/10/2026
automation now performs only checked project-scoped Git commit, not implementation.

Add an Edit-enabled spacing slider independent of icon/image size. Preserve
existing radial positions at 100%. Highlight must visibly tint a thumbnail,
not disappear behind its white pixels. Remove HUD title MH LIBRARY, close X,
all guidance below icons; retain Esc/Space, right-click settings and compact
page controls only when multiple pages exist. Errors remain visible in tooltips
or appropriate settings/modal feedback rather than hidden under the ring.

Edit click-release on an icon opens an optional single digit 0–9 assignment.
Dragging after a threshold moves it instead. Assigned keys are unique within
the board and follow file identity across move/rename/config transfer; no implicit
position digits remain. Clear a key with an empty value. Keys import their icon
from anywhere in the active board, including docks and noncurrent radial pages.

Four edge docks accept exact sparse drops from Library or the current HUD.
Internal moves swap occupied slots, external drops replace them. Ring holes and
edge holes remain. Docks anchor to viewport top/bottom/left/right and wrap when
necessary; user can reorder directly. Empty dock drop targets appear during Edit;
normal dock picking is limited to actual icons and has priority over radial
direction. Preserve named boards, letter shortcuts, normal ring direction,
source previews, modifier placement, Replace, Escape and model geometry.

Migrate old board config without adding numeric assignments or moving existing
icons. Export/import and remapping include docks, spacing and key mappings.
Validate portable layout/data, HtmlDialog behavior and native Tool events/rendering
with isolated config/fixtures, then scoped gate/package/reload. Do not commit now.
