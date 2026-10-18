# Library placement and replacement

HUD library placement stays in the existing SketchUp session. Normal click on
the visible inside of a rectangular cabinet fits the imported module into its
empty compartment. Ctrl + click replaces the pointed module using its local
envelope and orientation. No runtime dependency on MH_Superimp.

Acceptance:
- Preview the measured compartment/replacement box before committing.
- Measure current visible panel geometry, including shelves and braces; open
  faces end at the host envelope. Reject occupied space as an interior cavity.
- Redraw imported own rules at the new envelope; preserve physical thickness.
- Preserve replacement instance identity, orientation and compatible assembly
  references. Copied assemblies remain independent. Ambiguous anchors abort.
- One Undo restores the target and links; failed fitting rolls everything back.
- Free placement, HUD return after placing, Esc/Space and ordinary library
  behavior continue to work. Existing DC source/library files are read only.

Scope: conservative rectangular compartments with orthogonal host axes. Irregular
parts use occupied bounds; arbitrary concave packing and manual depth extrusion
are outside this feature.
