# Mirrored panels in non-curved DCs

Continue DC conversion excluding curved panels/DADX. Accept axis-aligned reflected
child groups, including 180-degree rotations represented by two negative axes.
Read formulas first and keep the signs of the captured axes. Formula dimensions
are magnitudes; signed transforms place their bounds. The root envelope stays
fixed and changing a rotation/visibility/copy guard remains unsupported.
Preserve physical nominal spans with additive offsets (for example parent width
minus door margins) without multiplying the parent resize a second time. This
must use the same frame interpretation in numeric and editable cell formulas.

Acceptance: reflected leaf and nested group formulas produce ordered bounds,
correct editable size/position sheet formulas and stable repeated changes after
JSON round-trip. Reject shear, axis permutations and changing rotation. Native
verification uses independent copies and validates every new export before it
counts as converted. Source SKPs and previous verified exports stay unchanged.

Drawer inspection also found zero-thickness annotation/helper geometry and
scaled containers. Do not bypass those checks to increase conversion counts.
