# HUD input, icon editing and placement

The HUD must retain letters already assigned to SketchUp commands. Esc/Space
fully exits and normal shortcuts resume. Limit input capture to the current
SketchUp model window while this HUD is active; settings/Studio fields and
other applications remain usable. Do not edit the user's shortcut preferences.

Allow 24–140 logical-pixel HUD icons. Adapt badges/text/hit areas to small sizes.
Settings provide two position choices: cursor (anchor at opening cursor, then
remain stationary for selection) and viewport center; clamp to viewport edges.

Settings add Edit mode. Drag an icon onto another radial slot to reorder it.
Drag a Library card onto a HUD slot to insert/move that module there, including
cards from another folder. Preserve the 8-slot radial layout with paging. Persist
orders by active Library folder in preferences. On folder/root changes, deleted
files or cancelled drags, never import a model or mutate SKPs as a side effect.
Normal click selection/placement works after Edit is disabled.

Acceptance includes saved ordering, root/folder boundaries, small-icon layout,
cursor/center positioning, real native key routing with assigned shortcuts,
Escape/Space cleanup, manual and Library drags, existing placement/geometry
behavior, scoped RuboCop/tests, Chromium UI checks and native execution.
