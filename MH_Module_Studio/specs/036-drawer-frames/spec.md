# Drawer conversion: flat auxiliary geometry and nested ATT frames

Upgrade the existing ATT interpreter and geometry planning for the selected
`1.QQ Ngan keo 1 tang 550.skp`, then retry related drawer sources in the MH library.
Never modify the selected source DC or the original library. Export only verified
own-rule copies into Modul_studio, preserving component parent/group children.

Treat a constant zero length on an actually flat (<= 0.001 mm) auxiliary axis as
metadata; retain captured axis transform, while references still evaluate to zero.
Do not permit a nonflat solid to collapse to zero. Support ordinary relative
formulas under scaled containers alongside the existing physical-nominal formulas.
Every accepted program must still match all captured part bounds, keep topology,
hidden/copy/rotation guards and pass fixed-envelope/collision checks.

Wire-only guides may be transformed as wires, including flat dimensions; do not
invent solids from bounding boxes. Non-box solids may translate rigidly, never
deform. Box panels retain the existing positive-size and collision requirements.
Numeric, symbolic positions, editable cell formulas and native geometry application
must use the same flat-axis rule. No imported opaque Ruby/ABF code execution.

Plan: isolated DCFrames policy and GeometryMotion calculations; delegate from
numeric/symbolic/cell-frame owners and native Runtime. Portable drawer/nesting/
zero/unsafe-geometry regressions, scoped gate, native conversion/reimport/edit/
Scale/Undo on independent copies, source hashes, package and VBO reload.
