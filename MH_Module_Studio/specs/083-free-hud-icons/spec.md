# Free HUD icons with horizontal/vertical alignment

Extend Edit beyond ring slots and viewport-edge docks: release a dragged icon on
any free viewport location. Internal movement preserves its assigned digit and
leaves a hole at its old slot. Existing target icons retain swap behavior;
external Library drops replace occupied targets or add a free icon at the drop.
Native click-release still edits a digit and is never interpreted as dragging.

While dragging in free space, snap X/Y independently within 10 logical pixels
of ring icon centers and other displayed icons. Show dashed horizontal/vertical
guides and the snapped preview. Ring references may be retained on an axis so
alignment follows the ring when opening at the cursor or changing radius.
Other coordinates persist as normalized viewport positions. Clamp icon centers
inside the viewport when dimensions change; never move native model geometry.

Schema3 adds explicit free positions per entry while migrating schema1/2 without
moving existing ring/dock icons. Named boards, digit mappings, images, config
transfer and file identity remapping include free icons. Free picking precedes
radial directional selection; shortcuts and deletion work in every location.
No change to module placement, Fit, Replace or inter-module rules.

Acceptance: portable migration/snap/resize/remap and moves; native editing and
external drop events, guides/rendering, digit choice and reopen persistence;
scoped gate, browser regressions, package verification and existing-session reload.

Module Options follow-up: remove the updating/can-keep-typing status line.
Retain automatic apply, queued edits, disabled busy actions and meaningful errors.
Browser verification must exercise an in-flight edit, queued values and errors.
