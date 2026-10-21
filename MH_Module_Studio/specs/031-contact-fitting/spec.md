# 031 — Filled assembly faces and automatic contact fitting

Selected assembly reference/target faces must have translucent surface fill as
well as the outline. Held faces remain darker. Update the viewport, not Studio.

When a second contact holds the opposite face of the same target module, preserve
both offsets by changing the target size along the required axis. Keep translation
for contacts that already fit; no unnecessary resize. Own ATT modules reconstruct
their internal panels through ScaleRedraw so thickness is preserved. Use measured
response for internal inset faces as well as outer faces. Persist both links so
subsequent offset or reference-thickness edits solve again.

Identical faces with incompatible offsets, impossible/nonpositive dimensions,
unsupported source DC reconstruction, and genuine conflicting constraints still
abort atomically with a readable explanation rather than a rule UUID.

Verify raw and owned modules, expansion/contraction, two-axis fitting, internal
panel anchors, copied assemblies, rollback, unchanged references, and native face
draw calls. Use only the existing SketchUp session via VBO; retain user's model.
