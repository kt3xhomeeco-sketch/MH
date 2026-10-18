# Formula-driven panel thickness inside assemblies

User keeps existing explicit B-follows-A direction. Do not change contact modes,
surface orientation rules, dependency ordering or auto-swap selected A/B.

In model 1 / PID25420 / VBO53244, assembly450543 contains cabinet450372 and
door450538 with opposing X/Z contacts. The door's root LenY has access NONE and
explicit formula a0Van. Its actual thickness is therefore an output, while X/Z
remain parent dimensions. Older stored programs lack an envelope policy. Changing
shared T1 aborts on the door's fixed-envelope check; cabinet alone plans correctly.
Scale involving the door's thickness axis also fails before contact fitting.

Extend the proved derived-axis policy to hidden readonly NONE dimensions only
when an explicit supported root length formula exists and neither that declaration
nor complete child geometry/visibility depends on the same root axis. Check the
declared length against actual predicted union span for every target, not only the
captured baseline. Keep unsupported/cyclic/input dimensions fixed. Existing VIEW
proof remains, with explicit declarations checked when present.

Migrate missing/older subset policies in owned rule copies on validation using
the same proof. Reject forged extra axes or malformed policies. Persist migrated
rules only through existing owned updates/Scale/export; never rewrite source SKPs.

Verify legacy door/cabinet captured fixtures, common T1 repeated changes and all
contacts, repeated enlarged/shrunken Scale, copy independence and atomic failure.
Test an actual two-cabinet side-by-side aggregate (combined width twice either
member). Do not invent a size threshold: this aggregate already scales before
the change; distinguish the reproduced thickness-output error from other reports.
Use only independent native QA copies; preserve original source assembly, rules,
values, files, definitions and selection. Run scoped RuboCop/core tests, native
assembly regressions, package and reload only already-open model 1.

Additional reproduced Scale fault: preserving single-panel thickness can leave
the shrunken aggregate bounds different from the user's requested bounds. Capture
the requested wrapper-local box before normalizing its Scale. After ordinary
internal redraw/contact solving, measure dimension responses, distribute any
remaining span error over actual free dimensions, solve contacts again and align
the resulting box with Scale's anchor. Derived thickness axes are not resize
freedoms. All edits remain inside the same transaction. Impossible geometry must
abort; never change T1 or stored gap values to force the box. Repeat layouts retain
their existing source/copy pipeline and are excluded from this new envelope fit.
